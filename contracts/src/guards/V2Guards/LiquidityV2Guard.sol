// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ITokenGuard, TokenGuardResult} from "../interfaces/ITokenGuard.sol";
import {IUniswapV2Factory, IUniswapV2Pair, IUniswapV2Router} from "../interfaces/IUniswapV2Interfaces.sol";

/**
 * @title  LiquidityGuard
 * @notice Pre-transaction safety guard for Uniswap V2 liquidity operations.
 *         Works for both token/token pairs and ETH pairs (via WETH substitution).
 * @author Sourav-IITBPL
 *
 * @dev Three-phase flow:
 *
 *  Phase 1 – [eth_call, zero gas]
 *      checkLiquidity(router, tokenA, tokenB, amountADesired, amountBDesired, operationType)
 *      Returns a fully-populated LiquidityV2GuardResult. Inspect flags in the UI.
 *
 *  Phase 2 – [on-chain tx via PreFlightRouter]
 *      storeCheck(router, tokenA, tokenB, amountADesired, amountBDesired, user, operationType)
 *      Records a keccak256 fingerprint of the current pool state for `user`.
 *      Returns the stored result for NFT minting.
 *
 *  Phase 3 – [on-chain tx, SAME BLOCK as Phase 2, via LiquidityV2Executor]
 *      validateCheck(router, tokenA, tokenB, amountADesired, amountBDesired, user, operationType)
 *      Re-runs the check, compares fingerprint. Reverts if state changed.
 *      Hard-block flags are always re-evaluated regardless of stored state.
 */

contract LiquidityGuard is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    //  Result struct
    /**
     * @dev All flags default to false (safe). true = risk signal.
     */

    /// @notice Liquidity-operation findings emitted by the guard.
    struct LiquidityV2GuardResult {
        bool ROUTER_NOT_TRUSTED;
        bool PAIR_NOT_EXISTS;
        bool ZERO_LIQUIDITY;
        bool LOW_LIQUIDITY; //either raw reserve < MINIMUM_RAW_RESERVE
        bool LOW_LP_SUPPLY; //totalSupply < THRESHOLD_LP_SUPPLY
        bool FIRST_DEPOSITOR_RISK; // totalSupply == 0 — ratio set adversarially
        bool SEVERE_IMBALANCE; // one reserve < 1 % of the other
        bool K_INVARIANT_BROKEN; // current k < kLast (reserve drain)
        bool POOL_TOO_NEW; //pool younger than MIN_POOL_AGE_BLOCKS
        bool AMOUNT_RATIO_DEVIATION; // provided amounts deviate > MAX_RATIO_BPS from pool ratio
        bool HIGH_LP_IMPACT; // deposit exceeds MAX_LP_IMPACT_BPS of pool
        bool FLASHLOAN_RISK;
        bool ZERO_LP_OUT; // ADD: estimated LP mint rounds to 0
        bool ZERO_AMOUNTS_OUT; // REMOVE: estimated token out rounds to 0
        bool DUST_LP; // LP amount below MIN_LP
        TokenGuardResult tokenAResult;
        TokenGuardResult tokenBResult;
    }

    /**
     * @dev Identifies which of the four Uniswap V2 liquidity operations is being checked.
     */

    /// @notice Identifies the Uniswap V2 liquidity operation under review.
    enum LiquidityOperationType {
        ADD,
        ADD_ETH,
        REMOVE,
        REMOVE_ETH
    }

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MINIMUM_RAW_RESERVE = 1_000;
    uint256 public constant THRESHOLD_LP_SUPPLY = 1_000e18;
    uint256 public constant SEVERE_IMBALANCE_BPS = 100;
    uint256 public constant MIN_POOL_AGE_BLOCKS = 300;
    uint256 public constant MAX_RATIO_DEVIATION = 500; // 5% tolerance on amount ratio
    uint256 public constant MAX_LP_IMPACT_BPS = 1_000; // 10% of pool
    uint256 public constant MIN_LP = 1_000;

    ITokenGuard public tokenGuard;
    /// @notice Routers whose factory/pair combination is trusted by this guard.
    mapping(address => bool) public trustedRouters;

    /// @dev user => router => uint96 stored at check time.  uint96 for gas optimization .
    mapping(address => mapping(address => uint96)) internal storedUserChecksPerRouter;

    /// @notice Addresses allowed to call storeCheck and validateCheck.
    mapping(address => bool) public trustedCallers;

    /// @notice Block number at which each pair address was first observed.
    mapping(address => uint256) public poolFirstSeenBlock;

    /// @dev user => router => block number of last stored check.
    mapping(address => mapping(address => uint256)) public lastCheckBlock;

    event LiquidityCheckPerformed(
        address indexed user, address tokenA, address tokenB, LiquidityOperationType operationType
    );
    /// @notice Emitted when a user's liquidity check is stored for same-block validation.
    event CheckStored(address indexed user, address indexed router, uint256 blockNumber);
    /// @notice Emitted when a trusted router entry is updated.
    event TrustedRoutersSet(address indexed router, bool status);
    /// @notice Emitted when a trusted caller entry is updated.
    event TrustedCallersAuthorized(address indexed caller, bool authorized);

    /// @dev Restricts stateful flows to trusted preflight callers.
    modifier onlyTrustedCaller() {
        require(trustedCallers[msg.sender], "NOT_AUTHORIZED_CALLER");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice UUPS initializer.
     * @param _tokenGuard Address of the deployed TokenGuard contract.
     */
    function initialize(address _tokenGuard) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        tokenGuard = ITokenGuard(_tokenGuard);
    }

    /// @dev Authorizes UUPS upgrades through the contract owner.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// ADMIN FUNCTION ///
    /**
     * @notice Whitelist or remove a Uniswap V2-compatible router.
     * @param router The router address to configure.
     * @param status true = trusted, false = untrusted.
     */
    function setTrustedRouter(address router, bool status) external onlyOwner {
        trustedRouters[router] = status;
        emit TrustedRoutersSet(router, status);
    }

    /**
     * @notice Grant or revoke call permissions for storeCheck / validateCheck.
     * @param caller     The address to configure.
     * @param authorized true = allowed, false = blocked.
     */
    function setTrustedCaller(address caller, bool authorized) external onlyOwner {
        require(caller != address(0), "ZERO_ADDRESS");
        trustedCallers[caller] = authorized;
        emit TrustedCallersAuthorized(caller, authorized);
    }

    /**
     * @notice Run all  Core safety checks for a liquidity operation.
     * @param user           the user who is performing the operation.
     * @param router         Uniswap V2-compatible router address.
     * @param tokenA         First token address. Use address(0) for ETH.
     * @param tokenB         Second token address. Use address(0) for ETH.
     * @param amountADesired For ADD/ADD_ETH: desired tokenA amount. For REMOVE: LP amount to burn.
     * @param amountBDesired For ADD: desired tokenB amount. Zero for remove ops.
     * @param operationType  Which of the four liquidity operations to validate.
     * @return result        Fully-populated LiquidityV2GuardResult. All false = safe.
     */
    function checkLiquidity(
        address user,
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        LiquidityOperationType operationType
    ) external returns (LiquidityV2GuardResult memory result) {
        emit LiquidityCheckPerformed(user, tokenA, tokenB, operationType);
        return _checkLiquidity(router, tokenA, tokenB, amountADesired, amountBDesired, operationType);
    }

    /**
     * @notice Record the current pool state fingerprint for `user`.
     *         MUST be called in the same block as the Phase 3 execution.
     * @param router         Uniswap V2-compatible router.
     * @param tokenA         First token. address(0) resolves to WETH.
     * @param tokenB         Second token. address(0) resolves to WETH.
     * @param amountADesired ADD: tokenA desired. REMOVE: LP amount.
     * @param amountBDesired ADD: tokenB desired. REMOVE: 0.
     * @param user           Address whose check is being stored.
     * @param operationType             Liquidity operation type.
     * @return result        The LiquidityV2GuardResult at storage time.
     */
    function storeCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOperationType operationType
    ) external nonReentrant onlyTrustedCaller returns (LiquidityV2GuardResult memory result) {
        result = _checkLiquidity(router, tokenA, tokenB, amountADesired, amountBDesired, operationType);
        storedUserChecksPerRouter[user][router] = _packed(result);
        lastCheckBlock[user][router] = block.number;

        emit CheckStored(user, router, block.number);

        return result;
    }

    /**
     * @notice Validates a stored liquidity check and reverts if pool state changed.
     * @param router Must match the router used in `storeCheck`.
     * @param tokenA Must match the first token used in `storeCheck`.
     * @param tokenB Must match the second token used in `storeCheck`.
     * @param amountADesired Must match the first amount used in `storeCheck`.
     * @param amountBDesired Must match the second amount used in `storeCheck`.
     * @param user User whose stored fingerprint is being validated.
     * @param operationType Must match the operation type used in `storeCheck`.
     */
    function validateCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOperationType operationType
    ) external view {
        require(lastCheckBlock[user][router] == block.number, "STALE_LIQ_CHECK");
        LiquidityV2GuardResult memory currentResult =
            _checkLiquidity(router, tokenA, tokenB, amountADesired, amountBDesired, operationType);
        uint96 currentFingerprint = _packed(currentResult);
        uint96 storedFingerprint = storedUserChecksPerRouter[user][router];

        require(currentFingerprint == storedFingerprint, "LIQ_STATE_CHANGED");
    }

    /**
     * @notice Returns the stored check result for a given user and router.
     * @param user   The address whose check was stored.
     * @param router The router used at check time.
     * @return currentResult  The decoded LiquidityV2GuardResult stored for this user/router pair.
     */
    function getStoredCheck(address user, address router)
        external
        view
        returns (LiquidityV2GuardResult memory currentResult)
    {
        uint96 packed = storedUserChecksPerRouter[user][router];
        return _unpacked(packed);
    }

    /// INTERNAL FUNCTIONS ///

    /**
     * @dev Internal check logic shared by checkLiquidity, storeCheck, and validateCheck.
     * @param router         Uniswap V2-compatible router.
     * @param tokenA         First token. address(0) resolves to WETH.
     * @param tokenB         Second token. address(0) resolves to WETH.
     * @param amountADesired ADD: tokenA desired in. REMOVE: LP tokens to burn.
     * @param amountBDesired ADD: tokenB desired in. REMOVE: 0 (unused).
     * @param operationType  Liquidity operation type.
     * @return result        Populated LiquidityV2GuardResult struct.
     */
    function _checkLiquidity(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        LiquidityOperationType operationType
    ) internal view returns (LiquidityV2GuardResult memory result) {
        if (!trustedRouters[router]) {
            result.ROUTER_NOT_TRUSTED = true;
        }

        require(tokenA != tokenB, "INVALID_TOKEN_ADDRESS");

        address weth = IUniswapV2Router(router).WETH();
        if (tokenA == address(0)) tokenA = weth;
        if (tokenB == address(0)) tokenB = weth;

        result.tokenAResult = tokenGuard.checkToken(tokenA);
        result.tokenBResult = tokenGuard.checkToken(tokenB);

        address pair;
        uint112 token0Reserve;
        uint112 token1Reserve;
        uint32 lastBlockTimestamp;

        {
            address factory = IUniswapV2Router(router).factory();
            pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        }

        if (pair == address(0)) {
            result.PAIR_NOT_EXISTS = true;
            return result;
        }

        {
            IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
            (token0Reserve, token1Reserve, lastBlockTimestamp) = pairContract.getReserves();
        }

        if (token0Reserve == 0 || token1Reserve == 0) {
            result.ZERO_LIQUIDITY = true;
            result.FIRST_DEPOSITOR_RISK = true;
            return result;
        }

        uint256 reserveA;
        uint256 reserveB;

        {
            // Align reserves to tokenA / tokenB
            (reserveA, reserveB) = (tokenA == IUniswapV2Pair(pair).token0())
                ? (uint256(token0Reserve), uint256(token1Reserve))
                : (uint256(token1Reserve), uint256(token0Reserve));
        }

        uint256 lpTotalSupply = IUniswapV2Pair(pair).totalSupply();

        {
            uint256 rawReserveA = reserveA / (10 ** _safeDecimals(tokenA));
            uint256 rawReserveB = reserveB / (10 ** _safeDecimals(tokenB));

            if (rawReserveA < MINIMUM_RAW_RESERVE || rawReserveB < MINIMUM_RAW_RESERVE) result.LOW_LIQUIDITY = true;
            if (_isSeverelyImbalanced(rawReserveA, rawReserveB)) result.SEVERE_IMBALANCE = true;
        }

        if (lpTotalSupply < THRESHOLD_LP_SUPPLY) result.LOW_LP_SUPPLY = true;
        if (lpTotalSupply == 0) result.FIRST_DEPOSITOR_RISK = true;

        {
            uint256 kLast = IUniswapV2Pair(pair).kLast();
            if (kLast > 0 && uint256(token0Reserve) * uint256(token1Reserve) < kLast) {
                result.K_INVARIANT_BROKEN = true;
            }
        }

        {
            uint256 firstSeen = poolFirstSeenBlock[pair];
            if (firstSeen != 0 && block.number - firstSeen < MIN_POOL_AGE_BLOCKS) {
                result.POOL_TOO_NEW = true;
            }
        }

        if (uint32(block.timestamp) == lastBlockTimestamp) result.FLASHLOAN_RISK = true;

        if (operationType == LiquidityOperationType.ADD || operationType == LiquidityOperationType.ADD_ETH) {
            _checkAdd(amountADesired, amountBDesired, reserveA, reserveB, lpTotalSupply, result);
        } else {
            _checkRemove(amountADesired, reserveA, reserveB, lpTotalSupply, result);
        }
    }

    /**
     * @dev Validates add-liquidity specific conditions.
     * @param amountA   Desired tokenA input amount.
     * @param amountB   Desired tokenB input amount.
     * @param reserveA  Current pool reserveA aligned to tokenA.
     * @param reserveB  Current pool reserveB aligned to tokenB.
     * @param lpSupply  Current LP token total supply.
     * @param result    Result struct mutated in place.
     */
    function _checkAdd(
        uint256 amountA,
        uint256 amountB,
        uint256 reserveA,
        uint256 reserveB,
        uint256 lpSupply,
        LiquidityV2GuardResult memory result
    ) private pure {
        if (amountA > 0 && amountB > 0 && reserveA > 0 && reserveB > 0) {
            uint256 poolRatio = (reserveB * 1e18) / reserveA;
            uint256 inputRatio = (amountB * 1e18) / amountA;
            uint256 delta = poolRatio > inputRatio ? poolRatio - inputRatio : inputRatio - poolRatio;
            if ((delta * MAX_BPS) / poolRatio > MAX_RATIO_DEVIATION) result.AMOUNT_RATIO_DEVIATION = true;

            if ((amountA * MAX_BPS) / reserveA > MAX_LP_IMPACT_BPS) result.HIGH_LP_IMPACT = true;
        }

        if (lpSupply > 0 && reserveA > 0) {
            uint256 lpEst = (amountA * lpSupply) / reserveA;
            if (lpEst == 0) result.ZERO_LP_OUT = true;
            if (lpEst > 0 && lpEst < MIN_LP) result.DUST_LP = true;
        }
    }

    /**
     * @dev Validates remove-liquidity specific conditions.
     * @param lpAmount  LP token amount to burn.
     * @param reserveA        Current pool reserveA aligned to tokenA.
     * @param reserveB        Current pool reserveB aligned to tokenB.
     * @param lpSupply  Current LP token total supply.
     * @param result    Result struct mutated in place.
     */
    function _checkRemove(
        uint256 lpAmount,
        uint256 reserveA,
        uint256 reserveB,
        uint256 lpSupply,
        LiquidityV2GuardResult memory result
    ) private pure {
        if (lpAmount == 0 || lpAmount < MIN_LP) {
            result.DUST_LP = true;
            return;
        }
        if (lpSupply > 0) {
            uint256 AmountOutA = (lpAmount * reserveA) / lpSupply;
            uint256 AmountOutB = (lpAmount * reserveB) / lpSupply;
            if (AmountOutA == 0 || AmountOutB == 0) result.ZERO_AMOUNTS_OUT = true;
        }
    }

    /// INTERNAL HELPER FUNCTIONS ///
    /**
     * @dev Safe decimals read — returns 18 if the token does not implement decimals().
     * @param token The ERC-20 token address to query.
     * @return The token's decimal places, or 18 as a safe default.
     */
    function _safeDecimals(address token) internal view returns (uint256) {
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            return d;
        } catch {
            return 18;
        }
    }

    /**
     * @dev Returns true if one reserve is less than SEVERE_IMBALANCE_BPS percent of the other.
     * @param token0Reserve First normalised reserve value.
     * @param token1Reserve Second normalised reserve value.
     * @return True if the pool is severely imbalanced.
     */
    function _isSeverelyImbalanced(uint256 token0Reserve, uint256 token1Reserve) internal pure returns (bool) {
        // token0Reserve < 1% of token1Reserve  OR  token1Reserve < 1% of token0Reserve
        return token0Reserve * 10_000 < token1Reserve * SEVERE_IMBALANCE_BPS
            || token1Reserve * 10_000 < token0Reserve * SEVERE_IMBALANCE_BPS;
    }

    function _packed(LiquidityV2GuardResult memory r) internal pure returns (uint96 result) {
        // Liquidity flags (0–14)
        if (r.ROUTER_NOT_TRUSTED) result |= uint96(1) << 0;
        if (r.PAIR_NOT_EXISTS) result |= uint96(1) << 1;
        if (r.ZERO_LIQUIDITY) result |= uint96(1) << 2;
        if (r.LOW_LIQUIDITY) result |= uint96(1) << 3;
        if (r.LOW_LP_SUPPLY) result |= uint96(1) << 4;
        if (r.FIRST_DEPOSITOR_RISK) result |= uint96(1) << 5;
        if (r.SEVERE_IMBALANCE) result |= uint96(1) << 6;
        if (r.K_INVARIANT_BROKEN) result |= uint96(1) << 7;
        if (r.POOL_TOO_NEW) result |= uint96(1) << 8;
        if (r.AMOUNT_RATIO_DEVIATION) result |= uint96(1) << 9;
        if (r.HIGH_LP_IMPACT) result |= uint96(1) << 10;
        if (r.FLASHLOAN_RISK) result |= uint96(1) << 11;
        if (r.ZERO_LP_OUT) result |= uint96(1) << 12;
        if (r.ZERO_AMOUNTS_OUT) result |= uint96(1) << 13;
        if (r.DUST_LP) result |= uint96(1) << 14;

        TokenGuardResult memory a = r.tokenAResult;
        TokenGuardResult memory b = r.tokenBResult;

        // Token A (15–43)
        if (a.NOT_A_CONTRACT) result |= uint96(1) << 15;
        if (a.EMPTY_BYTECODE) result |= uint96(1) << 16;
        if (a.DECIMALS_REVERT) result |= uint96(1) << 17;
        if (a.WEIRD_DECIMALS) result |= uint96(1) << 18;
        if (a.HIGH_DECIMALS) result |= uint96(1) << 19;
        if (a.TOTAL_SUPPLY_REVERT) result |= uint96(1) << 20;
        if (a.ZERO_TOTAL_SUPPLY) result |= uint96(1) << 21;
        if (a.VERY_LOW_TOTAL_SUPPLY) result |= uint96(1) << 22;
        if (a.SYMBOL_REVERT) result |= uint96(1) << 23;
        if (a.NAME_REVERT) result |= uint96(1) << 24;
        if (a.IS_EIP1967_PROXY) result |= uint96(1) << 25;
        if (a.IS_EIP1822_PROXY) result |= uint96(1) << 26;
        if (a.IS_MINIMAL_PROXY) result |= uint96(1) << 27;
        if (a.HAS_OWNER) result |= uint96(1) << 28;
        if (a.OWNERSHIP_RENOUNCED) result |= uint96(1) << 29;
        if (a.OWNER_IS_EOA) result |= uint96(1) << 30;
        if (a.IS_PAUSABLE) result |= uint96(1) << 31;
        if (a.IS_CURRENTLY_PAUSED) result |= uint96(1) << 32;
        if (a.HAS_BLACKLIST) result |= uint96(1) << 33;
        if (a.HAS_BLOCKLIST) result |= uint96(1) << 34;
        if (a.POSSIBLE_FEE_ON_TRANSFER) result |= uint96(1) << 35;
        if (a.HAS_TRANSFER_FEE_GETTER) result |= uint96(1) << 36;
        if (a.HAS_TAX_FUNCTION) result |= uint96(1) << 37;
        if (a.POSSIBLE_REBASING) result |= uint96(1) << 38;
        if (a.HAS_MINT_CAPABILITY) result |= uint96(1) << 39;
        if (a.HAS_BURN_CAPABILITY) result |= uint96(1) << 40;
        if (a.HAS_PERMIT) result |= uint96(1) << 41;
        if (a.HAS_FLASH_MINT) result |= uint96(1) << 42;

        // Token B (43–72)
        if (b.NOT_A_CONTRACT) result |= uint96(1) << 43;
        if (b.EMPTY_BYTECODE) result |= uint96(1) << 44;
        if (b.DECIMALS_REVERT) result |= uint96(1) << 45;
        if (b.WEIRD_DECIMALS) result |= uint96(1) << 46;
        if (b.HIGH_DECIMALS) result |= uint96(1) << 47;
        if (b.TOTAL_SUPPLY_REVERT) result |= uint96(1) << 48;
        if (b.ZERO_TOTAL_SUPPLY) result |= uint96(1) << 49;
        if (b.VERY_LOW_TOTAL_SUPPLY) result |= uint96(1) << 50;
        if (b.SYMBOL_REVERT) result |= uint96(1) << 51;
        if (b.NAME_REVERT) result |= uint96(1) << 52;
        if (b.IS_EIP1967_PROXY) result |= uint96(1) << 53;
        if (b.IS_EIP1822_PROXY) result |= uint96(1) << 54;
        if (b.IS_MINIMAL_PROXY) result |= uint96(1) << 55;
        if (b.HAS_OWNER) result |= uint96(1) << 56;
        if (b.OWNERSHIP_RENOUNCED) result |= uint96(1) << 57;
        if (b.OWNER_IS_EOA) result |= uint96(1) << 58;
        if (b.IS_PAUSABLE) result |= uint96(1) << 59;
        if (b.IS_CURRENTLY_PAUSED) result |= uint96(1) << 60;
        if (b.HAS_BLACKLIST) result |= uint96(1) << 61;
        if (b.HAS_BLOCKLIST) result |= uint96(1) << 62;
        if (b.POSSIBLE_FEE_ON_TRANSFER) result |= uint96(1) << 63;
        if (b.HAS_TRANSFER_FEE_GETTER) result |= uint96(1) << 64;
        if (b.HAS_TAX_FUNCTION) result |= uint96(1) << 65;
        if (b.POSSIBLE_REBASING) result |= uint96(1) << 66;
        if (b.HAS_MINT_CAPABILITY) result |= uint96(1) << 67;
        if (b.HAS_BURN_CAPABILITY) result |= uint96(1) << 68;
        if (b.HAS_PERMIT) result |= uint96(1) << 69;
        if (b.HAS_FLASH_MINT) result |= uint96(1) << 70;
    }

    function _unpacked(uint96 packed) internal pure returns (LiquidityV2GuardResult memory r) {
        r.ROUTER_NOT_TRUSTED = (packed >> 0) & 1 == 1;
        r.PAIR_NOT_EXISTS = (packed >> 1) & 1 == 1;
        r.ZERO_LIQUIDITY = (packed >> 2) & 1 == 1;
        r.LOW_LIQUIDITY = (packed >> 3) & 1 == 1;
        r.LOW_LP_SUPPLY = (packed >> 4) & 1 == 1;
        r.FIRST_DEPOSITOR_RISK = (packed >> 5) & 1 == 1;
        r.SEVERE_IMBALANCE = (packed >> 6) & 1 == 1;
        r.K_INVARIANT_BROKEN = (packed >> 7) & 1 == 1;
        r.POOL_TOO_NEW = (packed >> 8) & 1 == 1;
        r.AMOUNT_RATIO_DEVIATION = (packed >> 9) & 1 == 1;
        r.HIGH_LP_IMPACT = (packed >> 10) & 1 == 1;
        r.FLASHLOAN_RISK = (packed >> 11) & 1 == 1;
        r.ZERO_LP_OUT = (packed >> 12) & 1 == 1;
        r.ZERO_AMOUNTS_OUT = (packed >> 13) & 1 == 1;
        r.DUST_LP = (packed >> 14) & 1 == 1;

        TokenGuardResult memory a;
        TokenGuardResult memory b;

        a.NOT_A_CONTRACT = (packed >> 15) & 1 == 1;
        a.EMPTY_BYTECODE = (packed >> 16) & 1 == 1;
        a.DECIMALS_REVERT = (packed >> 17) & 1 == 1;
        a.WEIRD_DECIMALS = (packed >> 18) & 1 == 1;
        a.HIGH_DECIMALS = (packed >> 19) & 1 == 1;
        a.TOTAL_SUPPLY_REVERT = (packed >> 20) & 1 == 1;
        a.ZERO_TOTAL_SUPPLY = (packed >> 21) & 1 == 1;
        a.VERY_LOW_TOTAL_SUPPLY = (packed >> 22) & 1 == 1;
        a.SYMBOL_REVERT = (packed >> 23) & 1 == 1;
        a.NAME_REVERT = (packed >> 24) & 1 == 1;
        a.IS_EIP1967_PROXY = (packed >> 25) & 1 == 1;
        a.IS_EIP1822_PROXY = (packed >> 26) & 1 == 1;
        a.IS_MINIMAL_PROXY = (packed >> 27) & 1 == 1;
        a.HAS_OWNER = (packed >> 28) & 1 == 1;
        a.OWNERSHIP_RENOUNCED = (packed >> 29) & 1 == 1;
        a.OWNER_IS_EOA = (packed >> 30) & 1 == 1;
        a.IS_PAUSABLE = (packed >> 31) & 1 == 1;
        a.IS_CURRENTLY_PAUSED = (packed >> 32) & 1 == 1;
        a.HAS_BLACKLIST = (packed >> 33) & 1 == 1;
        a.HAS_BLOCKLIST = (packed >> 34) & 1 == 1;
        a.POSSIBLE_FEE_ON_TRANSFER = (packed >> 35) & 1 == 1;
        a.HAS_TRANSFER_FEE_GETTER = (packed >> 36) & 1 == 1;
        a.HAS_TAX_FUNCTION = (packed >> 37) & 1 == 1;
        a.POSSIBLE_REBASING = (packed >> 38) & 1 == 1;
        a.HAS_MINT_CAPABILITY = (packed >> 39) & 1 == 1;
        a.HAS_BURN_CAPABILITY = (packed >> 40) & 1 == 1;
        a.HAS_PERMIT = (packed >> 41) & 1 == 1;
        a.HAS_FLASH_MINT = (packed >> 42) & 1 == 1;

        b.NOT_A_CONTRACT = (packed >> 43) & 1 == 1;
        b.EMPTY_BYTECODE = (packed >> 44) & 1 == 1;
        b.DECIMALS_REVERT = (packed >> 45) & 1 == 1;
        b.WEIRD_DECIMALS = (packed >> 46) & 1 == 1;
        b.HIGH_DECIMALS = (packed >> 47) & 1 == 1;
        b.TOTAL_SUPPLY_REVERT = (packed >> 48) & 1 == 1;
        b.ZERO_TOTAL_SUPPLY = (packed >> 49) & 1 == 1;
        b.VERY_LOW_TOTAL_SUPPLY = (packed >> 50) & 1 == 1;
        b.SYMBOL_REVERT = (packed >> 51) & 1 == 1;
        b.NAME_REVERT = (packed >> 52) & 1 == 1;
        b.IS_EIP1967_PROXY = (packed >> 53) & 1 == 1;
        b.IS_EIP1822_PROXY = (packed >> 54) & 1 == 1;
        b.IS_MINIMAL_PROXY = (packed >> 55) & 1 == 1;
        b.HAS_OWNER = (packed >> 56) & 1 == 1;
        b.OWNERSHIP_RENOUNCED = (packed >> 57) & 1 == 1;
        b.OWNER_IS_EOA = (packed >> 58) & 1 == 1;
        b.IS_PAUSABLE = (packed >> 59) & 1 == 1;
        b.IS_CURRENTLY_PAUSED = (packed >> 60) & 1 == 1;
        b.HAS_BLACKLIST = (packed >> 61) & 1 == 1;
        b.HAS_BLOCKLIST = (packed >> 62) & 1 == 1;
        b.POSSIBLE_FEE_ON_TRANSFER = (packed >> 63) & 1 == 1;
        b.HAS_TRANSFER_FEE_GETTER = (packed >> 64) & 1 == 1;
        b.HAS_TAX_FUNCTION = (packed >> 65) & 1 == 1;
        b.POSSIBLE_REBASING = (packed >> 66) & 1 == 1;
        b.HAS_MINT_CAPABILITY = (packed >> 67) & 1 == 1;
        b.HAS_BURN_CAPABILITY = (packed >> 68) & 1 == 1;
        b.HAS_PERMIT = (packed >> 69) & 1 == 1;
        b.HAS_FLASH_MINT = (packed >> 70) & 1 == 1;

        r.tokenAResult = a;
        r.tokenBResult = b;
    }
}
