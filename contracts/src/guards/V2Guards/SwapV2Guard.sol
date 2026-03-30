// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IUniswapV2Factory, IUniswapV2Pair, IUniswapV2Router} from "../interfaces/IUniswapV2Interfaces.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ITokenGuard, TokenGuardResult} from "../interfaces/ITokenGuard.sol";

/**
 * @title  SwapV2Guard
 * @author Sourav-IITBPL
 * @notice Pre-transaction guard for Uniswap V2-compatible swaps or forked versions .
 *         Provides swapCheckV2 (view simulation), storeSwapCheckFor (fingerprint
 *         storage), and validateSwapFor (state-change detection before execution).
 *         Chainlink Automation keeps TWAP snapshots fresh for price-manipulation detection.
 */
contract SwapV2Guard is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, AutomationCompatibleInterface {
    /// @notice Full guard result. All flags default to false (safe).
    /// A true flag signals a risk condition. Callers should decide whether to proceed based on which flags are set and their risk tolerance.
    struct SwapV2GuardResult {
        bool ROUTER_NOT_TRUSTED; // router not in our trusted list
        bool FACTORY_NOT_TRUSTED; // factory not in our trusted list
        bool DEEP_MULTIHOP; // path length > MAX_PATH_LEN
        bool DUPLICATE_TOKEN_IN_PATH; // same token appears twice (circular route)
        // --- Per-pool flags (true if ANY hop triggered it) ---
        bool POOL_NOT_EXISTS;
        bool FACTORY_MISMATCH; // pool's stored factory != router's factory
        bool ZERO_LIQUIDITY; // either reserve is 0
        bool LOW_LIQUIDITY; // either reserve below MINIMUM_RESERVE
        bool LOW_LP_SUPPLY; // total LP supply below THRESHOLD_LP_SUPPLY
        bool POOL_TOO_NEW; // pool created < MIN_POOL_AGE_BLOCKS ago
        bool SEVERE_IMBALANCE; // one reserve is < SEVERE_IMBALANCE_BPS of the other
        bool K_INVARIANT_BROKEN; // current k < kLast (fee switch off — reserve drained)
        bool HIGH_SWAP_IMPACT; // amountIn would consume > MAX_IMPACT_BPS of reserve
        bool FLASHLOAN_RISK; // reserve was touched in the current block
        bool PRICE_MANIPULATED; // spot deviates from TWAP beyond MAX_DEVIATION_BPS
        // --- Token-level flags (checked for all tokens in the path) ---
        TokenGuardResult[] tokenResult; // result of TokenGuard checks on token
    }

    /// @notice Per-pool TWAP snapshot stored by Chainlink Automation.
    struct PriceSnapshot {
        /// @notice Cumulative price of token0 at snapshot time.
        uint256 cumulative0; // price0CumulativeLast at snapshot time + current-block accrual
        /// @notice Cumulative price of token1 at snapshot time.
        uint256 cumulative1;
        /// @notice Block timestamp associated with the snapshot.
        uint32 timestamp; // block.timestamp at snapshot
        /// @notice Block number at which the snapshot was recorded.
        uint256 lastBlock; // block.number at snapshot
    }

    /// @notice Compact same-block fingerprint stored for swap validation.
    struct StoredSwapCheck {
        /// @notice Packed compact form of the stored guard result.
        uint256 packed;
        /// @notice Bytes payload used when the stored check exceeds compact packing.
        bytes data;
        /// @notice Number of token-level entries encoded in the stored check.
        uint8 length;
        /// @notice Whether the compact packed representation is used.
        bool isCompact;
        /// @notice Amount associated with the stored swap check.
        uint256 value;
    }

    // CONSTANTS

    /// Minimum reserve (raw units). Below this we flag LOW_LIQUIDITY.
    uint256 public constant MINIMUM_RAW_RESERVE = 1_000;
    /// Minimum LP token total supply.
    uint256 public constant THRESHOLD_LP_SUPPLY = 1_000e18;
    /// Maximum swap price deviation from TWAP (basis points, 500 = 5%).
    uint256 public constant MAX_DEVIATION_BPS = 500;
    /// Minimum TWAP window before we trust it (seconds).
    uint256 public constant MIN_TWAP_WINDOW = 60;
    /// Maximum path length before flagging deep multihop.
    uint256 public constant MAX_PATH_LEN = 4;
    /// Max swap impact as % of the input-side reserve (basis points, 1000 = 10%).
    uint256 public constant MAX_IMPACT_BPS = 1_000;
    /// A pool younger than this many blocks is flagged as risky.
    uint256 public constant MIN_POOL_AGE_BLOCKS = 300; // ~1 hour on mainnet
    /// If one reserve < this fraction of the other (bps), flag SEVERE_IMBALANCE.
    uint256 public constant SEVERE_IMBALANCE_BPS = 100; // 1% — very skewed

    /// STORAGE

    ITokenGuard public tokenGuard; // Address of the TokenGuard contract for token-level checks.
    address public automationForwarder; // Authorised Chainlink Automation forwarder address.
    mapping(address => PriceSnapshot) public snapshots;
    address[] public trackedPools;

    mapping(address => bool) public trustedRouters;
    mapping(address => bool) public trustedFactories;
    mapping(address => bool) public authorizedPreflightCallers;
    mapping(address => uint256) public poolFirstSeenBlock; // Block number at which a pool was first snapshotted (used as a proxy for pool age when the pair contract itself doesn't store creation block).
    uint256 public snapshotBlockInterval; // How many blocks between Chainlink Automation snapshots.
    /// user => router => bytes
    mapping(address => mapping(address => StoredSwapCheck)) internal storedUserChecksPerRouter;
    mapping(address => mapping(address => uint256)) public lastCheckBlock; // user => router => block number of last stored check (used to prevent replaying old checks)

    /// EVENTS

    /// @notice Emitted when a router's trust status is updated.
    event RouterTrustSet(address indexed router, bool status);
    /// @notice Emitted when a factory's trust status is updated.
    event FactoryTrustSet(address indexed factory, bool status);
    /// @notice Emitted when a pool is added to the TWAP tracking set.
    event PoolTracked(address indexed pool);
    /// @notice Emitted when a new TWAP snapshot is recorded for a pool.
    event SnapshotRecorded(address indexed pool, uint256 block_);
    /// @notice Emitted when the authorized Chainlink forwarder is updated.
    event ForwarderSet(address indexed forwarder);
    /// @notice Emitted when the snapshot cadence is updated.
    event SnapshotBlockIntervalSet(uint256 blocks);
    /// @notice Emitted when a preflight caller is authorized or revoked.
    event PreflightCallerSet(address indexed caller, bool authorized);
    /// @notice Emitted when a user's swap check is stored for same-block validation.
    event SwapCheckStored(
        address indexed user, address indexed router, SwapV2GuardResult indexed result, uint256 blockNumber
    );
    /// @notice Emitted when a swap guard check is executed.
    event SwapCheckPerformed(
        address indexed router, address[] indexed path, uint256 amountIn, SwapV2GuardResult indexed result
    );

    /// @dev Restricts stateful swap check storage to authorized preflight callers.
    modifier onlyPreflightCaller() {
        require(authorizedPreflightCallers[msg.sender], "NOT_AUTHORIZED_PREFLIGHT_CALLER");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the upgradeable swap guard.
     * @param _snapshotBlockInterval Minimum block interval between TWAP snapshots.
     * @param _tokenGuard Address of the TokenGuard contract used for token checks.
     */
    function initialize(uint256 _snapshotBlockInterval, address _tokenGuard) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        snapshotBlockInterval = _snapshotBlockInterval == 0 ? 1 : _snapshotBlockInterval;
        tokenGuard = ITokenGuard(_tokenGuard);
    }

    /// @dev Authorizes UUPS upgrades through the contract owner.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    //--------------------------------------------// ADMIN FUNCTIONS //---------------------------------------------//

    /**
     * @notice Adds a pool to the tracked set and immediately records a baseline snapshot.
     * @param pool Pair address to begin tracking.
     */
    function addTrackedPool(address pool) external onlyOwner {
        require(pool != address(0), "ZERO_ADDRESS");
        trackedPools.push(pool);

        if (poolFirstSeenBlock[pool] == 0) {
            poolFirstSeenBlock[pool] = block.number;
        }

        _recordSnapshot(pool);
        emit PoolTracked(pool);
    }

    /**
     * @notice Removes a pool from the tracked set.
     * @param pool Pair address to stop tracking.
     */
    function removeTrackedPool(address pool) external onlyOwner {
        uint256 len = trackedPools.length;
        for (uint256 i = 0; i < len;) {
            if (trackedPools[i] == pool) {
                trackedPools[i] = trackedPools[len - 1];
                trackedPools.pop();
                return;
            }
            unchecked {
                ++i;
            }
        }
        revert("POOL_NOT_TRACKED");
    }

    /**
     * @notice Updates the minimum block interval between TWAP snapshots.
     * @param blocks_ Snapshot interval measured in blocks.
     */
    function setSnapshotBlockInterval(uint256 blocks_) external onlyOwner {
        require(blocks_ > 0, "ZERO_INTERVAL");
        snapshotBlockInterval = blocks_;
        emit SnapshotBlockIntervalSet(blocks_);
    }

    /**
     * @notice Marks a router as trusted or untrusted.
     * @param router Router address to configure.
     * @param status Whether the router should be trusted.
     */
    function setTrustedRouter(address router, bool status) external onlyOwner {
        trustedRouters[router] = status;
        emit RouterTrustSet(router, status);
    }

    /**
     * @notice Marks a factory as trusted or untrusted.
     * @param factory Factory address to configure.
     * @param status Whether the factory should be trusted.
     */
    function setTrustedFactory(address factory, bool status) external onlyOwner {
        trustedFactories[factory] = status;
        emit FactoryTrustSet(factory, status);
    }

    /**
     * @notice Set the Chainlink Automation forwarder address.
     * @param forwarder Forwarder address allowed to call `performUpkeep`.
     */
    function setAutomationForwarder(address forwarder) external onlyOwner {
        require(forwarder != address(0), "ZERO_ADDRESS");
        automationForwarder = forwarder;
        emit ForwarderSet(forwarder);
    }

    /**
     * @notice Grants or revokes permission for preflight routers to store checks.
     * @param caller Caller address to configure.
     * @param authorized Whether the caller should be authorized.
     */
    function setPreflightCaller(address caller, bool authorized) external onlyOwner {
        require(caller != address(0), "ZERO_ADDRESS");
        authorizedPreflightCallers[caller] = authorized;
        emit PreflightCallerSet(caller, authorized);
    }

    /**
     * @notice Returns the number of pools currently tracked for TWAP snapshots.
     * @return Number of tracked pools.
     */
    function trackedPoolsLength() external view returns (uint256) {
        return trackedPools.length;
    }

    // EXTERNAL FUNCTION //

    /**
     * @notice Runs a swap guard check and returns the computed router quote.
     * @param router Router address to inspect.
     * @param path Swap path to evaluate.
     * @param amount Exact-input or exact-output amount used for the quote.
     * @param isExactTokenIn Whether `amount` represents exact input.
     * @return result Swap risk findings for the path.
     * @return amountsOut Router quote corresponding to the swap mode.
     */
    function swapCheckV2(address router, address[] calldata path, uint256 amount, bool isExactTokenIn)
        external
        returns (SwapV2GuardResult memory result, uint256[] memory amountsOut)
    {
        return _swapCheckV2(router, path, amount, isExactTokenIn);
    }

    /**
     * @notice Validate that pool state has not changed since storeSwapCheck.
     *         Called by SwapV2Executor before executing swaps.
     * @param router Router address used for the stored check.
     * @param path Swap path used for the stored check.
     * @param amount Exact-input or exact-output amount used for the stored check.
     * @param isExactTokenIn Whether `amount` represents exact input.
     * @param user User whose stored check is being validated.
     */
    function validateSwapCheck(
        address router,
        address[] calldata path,
        uint256 amount,
        bool isExactTokenIn,
        address user
    ) external {
        require(lastCheckBlock[user][router] == block.number, "STALE_CHECK");

        SwapV2GuardResult memory currentResult;
        uint256[] memory amountsOut;
        (currentResult, amountsOut) = _swapCheckV2(router, path, amount, isExactTokenIn);

        uint256 amountOut;
        if (amountsOut.length == 0) {
            // This can happen if the path is invalid or if getAmountsOut/getAmountsIn reverts. In either case, we want to fail validation.
            revert("INVALID_PATH_OR_AMOUNT");
        }

        if (isExactTokenIn) amountOut = amountsOut[amountsOut.length - 1];
        else amountOut = amountsOut[0];

        StoredSwapCheck memory currentCheck = _packedCheck(currentResult, amountOut);
        StoredSwapCheck memory storedCheck = storedUserChecksPerRouter[user][router];

        bytes32 currentFingerprint = keccak256(abi.encode(currentCheck));
        bytes32 storedFingerprint = keccak256(abi.encode(storedCheck));
        require(currentFingerprint == storedFingerprint, "SWAP_STATE_CHANGED");
    }

    /**
     * @notice Store swap state fingerprint for `user`. Called by PreFlightRouter.
     *         The fingerprint covers pool reserves and TWAP snapshots for all hops.
     * @param router Router address to inspect.
     * @param path Swap path to fingerprint.
     * @param amount Exact-input or exact-output amount used for the check.
     * @param isExactTokenIn Whether `amount` represents exact input.
     * @param user User whose fingerprint is being stored.
     * @return Swap guard findings stored for the user.
     */
    function storeSwapCheck(address router, address[] calldata path, uint256 amount, bool isExactTokenIn, address user)
        external
        nonReentrant
        onlyPreflightCaller
        returns (SwapV2GuardResult memory)
    {
        require(user != address(0), "INVALID_USER");
        require(amount > 0, "AMOUNT_IN_IS_ZERO");

        SwapV2GuardResult memory result;
        uint256[] memory amountsOut;
        (result, amountsOut) = _swapCheckV2(router, path, amount, isExactTokenIn);
        uint256 amountOut;

        if (amountsOut.length == 0) {
            // This can happen if the path is invalid or if getAmountsOut/getAmountsIn reverts.
            revert("INVALID_PATH_OR_AMOUNT");
        }

        if (isExactTokenIn) amountOut = amountsOut[amountsOut.length - 1];
        else amountOut = amountsOut[0];

        storedUserChecksPerRouter[user][router] = _packedCheck(result, amountOut);
        lastCheckBlock[user][router] = block.number;

        emit SwapCheckStored(user, router, result, block.number);
        return result;
    }

    /**
     * @notice Returns the latest stored swap fingerprint decoded back into guard output.
     * @param user User whose stored check is requested.
     * @param router Router used when the check was stored.
     * @return result Decoded stored swap guard result.
     * @return amountOut Stored output-side quote associated with the check.
     */
    function getStoredCheck(address user, address router)
        external
        view
        returns (SwapV2GuardResult memory result, uint256 amountOut)
    {
        require(lastCheckBlock[user][router] == block.number, "NO_STORED_CHECK");
        StoredSwapCheck memory storedCheck = storedUserChecksPerRouter[user][router];
        (result, amountOut) = _unpackedCheck(storedCheck);
        return (result, amountOut);
    }

    /**
     * @notice Returns the current TWAP for a tracked pool.
     *         Prices are in UQ112x112 format (multiply by 1e18 / 2^112 for decimal).
     * @return twap0UQ TWAP of token0 priced in token1 (UQ112x112)
     * @return twap1UQ TWAP of token1 priced in token0 (UQ112x112)
     * @return windowSeconds Duration of the TWAP window
     */
    /**
     * @notice Returns the current TWAP-derived cumulative values for a tracked pair.
     * @param pair Pair address whose snapshot window is queried.
     * @return twap0UQ Time-weighted cumulative price for token0.
     * @return twap1UQ Time-weighted cumulative price for token1.
     * @return windowSeconds Elapsed snapshot window in seconds.
     */
    function getTWAP(address pair) external view returns (uint256 twap0UQ, uint256 twap1UQ, uint32 windowSeconds) {
        PriceSnapshot memory snap = snapshots[pair];
        if (snap.timestamp == 0) return (0, 0, 0);

        uint32 elapsed = uint32(block.timestamp) - snap.timestamp;
        if (elapsed == 0) return (0, 0, 0);

        (uint112 r0, uint112 r1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();

        uint32 timeElapsedSinceTrade = uint32(block.timestamp) - blockTimestampLast;
        uint256 price0UQ = r0 > 0 ? (uint256(r1) << 112) / uint256(r0) : 0;
        uint256 price1UQ = r1 > 0 ? (uint256(r0) << 112) / uint256(r1) : 0;

        IUniswapV2Pair p = IUniswapV2Pair(pair);
        uint256 current0 = p.price0CumulativeLast() + price0UQ * timeElapsedSinceTrade;
        uint256 current1 = p.price1CumulativeLast() + price1UQ * timeElapsedSinceTrade;

        twap0UQ = (current0 - snap.cumulative0) / elapsed;
        twap1UQ = (current1 - snap.cumulative1) / elapsed;
        windowSeconds = elapsed;
    }

    /**
     * @notice Chainlink Automation checkUpkeep — identifies pools needing a snapshot.
     */
    /**
     * @notice Chainlink Automation hook that reports whether tracked pools need fresh snapshots.
     * @return upkeepNeeded True when at least one tracked pool has exceeded the snapshot interval.
     * @return performData ABI-encoded pool list that should be snapshotted by `performUpkeep`.
     */
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 total = trackedPools.length;
        address[] memory temp = new address[](total);
        uint256 count;

        for (uint256 i = 0; i < total;) {
            address pool = trackedPools[i];
            if (block.number - snapshots[pool].lastBlock >= snapshotBlockInterval) {
                temp[count] = pool;
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (count == 0) return (false, "");

        address[] memory pools = new address[](count);
        for (uint256 i = 0; i < count;) {
            pools[i] = temp[i];
            unchecked {
                ++i;
            }
        }

        return (true, abi.encode(pools));
    }

    /**
     * @notice Chainlink Automation performUpkeep — records snapshots.
     */
    /**
     * @notice Records fresh snapshots for the pools selected by `checkUpkeep`.
     * @param data ABI-encoded array of pair addresses to snapshot.
     */
    function performUpkeep(bytes calldata data) external override nonReentrant {
        require(msg.sender == automationForwarder || msg.sender == owner(), "UNAUTHORIZED_UPKEEP");

        address[] memory pools = abi.decode(data, (address[]));
        uint256 len = pools.length;

        for (uint256 i = 0; i < len;) {
            address pool = pools[i];
            if (block.number - snapshots[pool].lastBlock >= snapshotBlockInterval) {
                _recordSnapshot(pool);
            }
            unchecked {
                ++i;
            }
        }
    }

    //------------------------------// INTERNAL PURE HELPER FUNCTIONS//-------------------------------------------//

    /**
     * @notice Core Pre-transaction swap check function. Called as a static call before submitting a swap.
     *
     * @param router    The Uniswap V2-compatible/forked router to be used.
     * @param path      Token path (e.g. [WETH, USDC] for a single-hop).
     * @param amount  The exact input/output amount for the swap (used for impact check).
     *                  Pass 0 to skip the impact check.
     * @param isExactTokenIn Whether the provided amount is the exact input (true) or exact output (false) for the swap. This determines which side of the first/last pool we check for swap impact.
     * @return result   SwapV2GuardResult flags struct. All false = clean.
     */
    function _swapCheckV2(address router, address[] calldata path, uint256 amount, bool isExactTokenIn)
        internal
        returns (SwapV2GuardResult memory result, uint256[] memory amountsOut)
    {
        if (!trustedRouters[router]) {
            result.ROUTER_NOT_TRUSTED = true;
        }

        uint256 len = path.length;
        require(len >= 2, "PATH_TOO_SHORT");
        result.tokenResult = new TokenGuardResult[](len);

        if (len > MAX_PATH_LEN) {
            result.DEEP_MULTIHOP = true;
        }

        if (_hasDuplicateToken(path)) {
            result.DUPLICATE_TOKEN_IN_PATH = true;
        }

        address factory = IUniswapV2Router(router).factory();
        if (!trustedFactories[factory]) {
            result.FACTORY_NOT_TRUSTED = true;
        }

        for (uint256 i = 0; i < len - 1;) {
            address tokenIn = path[i];
            address tokenOut = path[i + 1];

            address pair = IUniswapV2Factory(factory).getPair(tokenIn, tokenOut);

            if (pair == address(0)) {
                result.POOL_NOT_EXISTS = true;
                unchecked {
                    ++i;
                }
                continue;
            }

            uint112 r0;
            uint112 r1;
            uint32 blockTimestampLast;
            address token0;
            {
                IUniswapV2Pair pairContract = IUniswapV2Pair(pair);

                // Factory stored inside the pair must match the router's factory.
                if (pairContract.factory() != factory) {
                    result.FACTORY_MISMATCH = true;
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                (r0, r1, blockTimestampLast) = pairContract.getReserves();

                if (r0 == 0 || r1 == 0) {
                    result.ZERO_LIQUIDITY = true;
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                token0 = pairContract.token0();
            }

            // this will check the token
            result.tokenResult[i] = tokenGuard.checkToken(tokenIn);

            {
                uint8 poolFlags = _checkPoolState(pair, r0, r1, blockTimestampLast);
                if ((poolFlags & 1) != 0) result.LOW_LIQUIDITY = true;
                if ((poolFlags & 2) != 0) result.SEVERE_IMBALANCE = true;
                if ((poolFlags & 4) != 0) result.LOW_LP_SUPPLY = true;
                if ((poolFlags & 8) != 0) result.POOL_TOO_NEW = true;
                if ((poolFlags & 16) != 0) result.K_INVARIANT_BROKEN = true;
                if ((poolFlags & 32) != 0) result.FLASHLOAN_RISK = true;
            }

            if (i == len - 2) {
                // also check the final output token
                result.tokenResult[i + 1] = tokenGuard.checkToken(tokenOut);
            }

            //  Swap impact
            if (amount > 0 && i == 0 && isExactTokenIn) {
                // Check impact only on the first hop (subsequent hops depend on output).
                uint256 reserveIn = (tokenIn == token0) ? uint256(r0) : uint256(r1);
                if (_isHighImpact(amount, reserveIn)) {
                    result.HIGH_SWAP_IMPACT = true;
                }
            }

            //Swap impact of last pair  for !isExactTokenIn
            if (amount > 0 && i == len - 2 && !isExactTokenIn) {
                // Check impact only on the first hop (subsequent hops depend on output).
                uint256 reserveIn = (tokenOut == token0) ? uint256(r0) : uint256(r1);
                if (_isHighImpact(amount, reserveIn)) {
                    result.HIGH_SWAP_IMPACT = true;
                }
            }

            if (_isPriceManipulated(pair, tokenIn, r0, r1, blockTimestampLast)) {
                result.PRICE_MANIPULATED = true;
            }

            unchecked {
                ++i;
            }
        }

        if (isExactTokenIn) {
            amountsOut = IUniswapV2Router(router).getAmountsOut(amount, path);
        }

        if (!isExactTokenIn) {
            amountsOut = IUniswapV2Router(router).getAmountsIn(amount, path);
        }

        emit SwapCheckPerformed(router, path, amount, result);
    }

    function _checkPoolState(address pair, uint112 r0, uint112 r1, uint32 blockTimestampLast)
        internal
        view
        returns (uint8 flags)
    {
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        address token0 = pairContract.token0();
        address token1 = pairContract.token1();
        uint256 rawReserve0 = uint256(r0) / (10 ** IERC20Metadata(token0).decimals());
        uint256 rawReserve1 = uint256(r1) / (10 ** IERC20Metadata(token1).decimals());

        if (rawReserve0 < MINIMUM_RAW_RESERVE || rawReserve1 < MINIMUM_RAW_RESERVE) {
            flags |= 1;
        }

        if (_isSeverelyImbalanced(rawReserve0, rawReserve1)) {
            flags |= 2;
        }

        if (pairContract.totalSupply() < THRESHOLD_LP_SUPPLY) {
            flags |= 4;
        }

        uint256 firstSeen = poolFirstSeenBlock[pair];
        if (firstSeen != 0 && block.number - firstSeen < MIN_POOL_AGE_BLOCKS) {
            flags |= 8;
        }

        uint256 kLast = pairContract.kLast();
        if (kLast > 0) {
            uint256 currentK = uint256(r0) * uint256(r1);
            if (currentK < kLast) {
                flags |= 16;
            }
        }

        if (uint32(block.timestamp) == blockTimestampLast) {
            flags |= 32;
        }
    }

    /**
     * @dev Records a TWAP snapshot with corrected cumulative price (includes
     *      current-block accrual so getFairPrice is always fresh).
     */
    function _recordSnapshot(address pair) internal {
        IUniswapV2Pair p = IUniswapV2Pair(pair);
        (uint112 r0, uint112 r1, uint32 blockTimestampLast) = p.getReserves();

        // Include accrual since last trade
        uint32 timeElapsedSinceTrade = uint32(block.timestamp) - blockTimestampLast;
        uint256 price0UQ = r0 > 0 ? (uint256(r1) << 112) / uint256(r0) : 0;
        uint256 price1UQ = r1 > 0 ? (uint256(r0) << 112) / uint256(r1) : 0;

        snapshots[pair] = PriceSnapshot({
            cumulative0: p.price0CumulativeLast() + price0UQ * timeElapsedSinceTrade,
            cumulative1: p.price1CumulativeLast() + price1UQ * timeElapsedSinceTrade,
            timestamp: uint32(block.timestamp),
            lastBlock: block.number
        });

        emit SnapshotRecorded(pair, block.number);
    }

    /**
     * @dev Detects any duplicate token address in the path (catches circular routes).
     */
    function _hasDuplicateToken(address[] calldata path) internal pure returns (bool) {
        uint256 len = path.length;
        for (uint256 i = 0; i < len;) {
            for (uint256 j = i + 1; j < len;) {
                if (path[i] == path[j]) return true;
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        return false;
    }

    /**
     * @dev True if one reserve is < SEVERE_IMBALANCE_BPS percent of the other.
     */
    function _isSeverelyImbalanced(uint256 r0, uint256 r1) internal pure returns (bool) {
        // r0 < 1% of r1  OR  r1 < 1% of r0
        return r0 * 10_000 < r1 * SEVERE_IMBALANCE_BPS || r1 * 10_000 < r0 * SEVERE_IMBALANCE_BPS;
    }

    /**
     * @dev True if amountIn would consume more than MAX_IMPACT_BPS of reserveIn.
     *      Uses the constant product formula to estimate actual price impact.
     *      amountInWithFee / (reserveIn + amountInWithFee) > MAX_IMPACT_BPS / 10000
     */
    function _isHighImpact(uint256 amountIn, uint256 reserveIn) internal pure returns (bool) {
        if (reserveIn == 0) return true;
        uint256 amountInWithFee = amountIn * 997; // 0.3% V2 fee
        uint256 numerator = amountInWithFee * 10_000;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        uint256 impactBps = numerator / denominator;
        return impactBps >= MAX_IMPACT_BPS;
    }

    /**
     * @dev TWAP deviation check. It returns true if the current spot price deviates from the TWAP by more than
     *     MAX_DEVIATION_BPS. This can indicate price manipulation attempts like sandwich attacks.
     * @param pair The Uniswap V2 pair address.
     * @param tokenIn The input token of the swap (used to determine price direction).
     * @param r0 Current reserve0 from getReserves().
     * @param r1 Current reserve1 from getReserves().
     * @param blockTimestampLast The last update timestamp from getReserves() (used for current cumulative price).
     */
    function _isPriceManipulated(address pair, address tokenIn, uint112 r0, uint112 r1, uint32 blockTimestampLast)
        internal
        view
        returns (bool)
    {
        PriceSnapshot memory snap = snapshots[pair];
        if (snap.lastBlock == 0) return false; // no snapshot yet

        uint32 windowElapsed = uint32(block.timestamp) - snap.timestamp;
        if (windowElapsed < MIN_TWAP_WINDOW) return false; // window too short to trust

        // Reconstruct the current cumulative price including elapsed time in this block.
        // Uniswap stores cumulative as sum(price * dt) where price is UQ112x112.
        uint32 timeElapsedSinceTrade = uint32(block.timestamp) - blockTimestampLast;

        uint256 current0;
        uint256 current1;
        {
            IUniswapV2Pair p = IUniswapV2Pair(pair);
            // price0 = r1/r0 in UQ112x112
            uint256 price0UQ = (uint256(r1) << 112) / uint256(r0);
            uint256 price1UQ = (uint256(r0) << 112) / uint256(r1);
            current0 = p.price0CumulativeLast() + price0UQ * timeElapsedSinceTrade;
            current1 = p.price1CumulativeLast() + price1UQ * timeElapsedSinceTrade;
        }

        // TWAP = delta_cumulative / delta_time ,  result is UQ112x112
        uint256 twap0UQ = (current0 - snap.cumulative0) / windowElapsed;
        uint256 twap1UQ = (current1 - snap.cumulative1) / windowElapsed;

        address token0 = IUniswapV2Pair(pair).token0();
        uint256 spotUQ;
        uint256 twapUQ;

        if (tokenIn == token0) {
            // We want: how much token1 per unit of token0
            spotUQ = (uint256(r1) << 112) / uint256(r0);
            twapUQ = twap0UQ;
        } else {
            // We want: how much token0 per unit of token1
            spotUQ = (uint256(r0) << 112) / uint256(r1);
            twapUQ = twap1UQ;
        }

        if (twapUQ == 0) return false;

        return !_withinDeviation(spotUQ, twapUQ);
    }

    /**
     * @dev Returns true when spot is within MAX_DEVIATION_BPS of twap.
     *      Both values must be in the same unit (UQ112x112).
     */
    function _withinDeviation(uint256 spot, uint256 twap) internal pure returns (bool) {
        uint256 diff = spot > twap ? spot - twap : twap - spot;
        return (diff * 10_000) / twap < MAX_DEVIATION_BPS;
    }

    function _packedCheck(SwapV2GuardResult memory result, uint256 amount)
        internal
        returns (StoredSwapCheck memory storedCheck)
    {
        uint16 core = _packSwapCore(result);

        uint8 length = uint8(result.tokenResult.length);
        uint32[] memory tokens = new uint32[](length);

        for (uint256 i; i < length; ++i) {
            tokens[i] = _packToken(result.tokenResult[i]);
        }

        if (length <= 7) {
            storedCheck.packed = _packSwapUint256(core, tokens);
            storedCheck.isCompact = true;
            storedCheck.length = length;
            storedCheck.value = amount;
        } else {
            storedCheck.data = _packSwapBytes(core, tokens);
            storedCheck.isCompact = false;
            storedCheck.length = length;
            storedCheck.packed = 0;
            storedCheck.value = amount;
        }
    }

    function _unpackedCheck(StoredSwapCheck memory storedCheck)
        internal
        view
        returns (SwapV2GuardResult memory result, uint256 amountOut)
    {
        bool isCompact = storedCheck.isCompact;
        uint8 length = storedCheck.length;

        uint16 core;
        uint32[] memory tokens;

        if (isCompact) {
            (core, tokens) = _unpackSwapUint256(storedCheck.packed, length);
        } else {
            (core, tokens) = _unpackSwapBytes(storedCheck.data);
        }
        result = _unpack(core, tokens);
        amountOut = storedCheck.value;

        return (result, amountOut);
    }

    function _unpack(uint16 core, uint32[] memory tokens) internal pure returns (SwapV2GuardResult memory r) {
        r = _unpackSwapCore(core);
        uint256 length = tokens.length;
        r.tokenResult = new TokenGuardResult[](length);
        for (uint256 i; i < length; ++i) {
            r.tokenResult[i] = _unpackToken(tokens[i]);
        }
    }

    function _packSwapUint256(uint16 core, uint32[] memory tokens) internal pure returns (uint256 packed) {
        require(tokens.length <= 7, "TOO_MANY_TOKENS");
        packed = uint256(core);
        uint256 size = tokens.length;
        for (uint256 i; i < size; ++i) {
            packed |= uint256(tokens[i]) << (16 + i * 32);
        }
    }

    function _unpackSwapUint256(uint256 packed, uint8 len) internal pure returns (uint16 core, uint32[] memory tokens) {
        core = uint16(packed);
        tokens = new uint32[](len);
        for (uint256 i; i < len; ++i) {
            tokens[i] = uint32(packed >> (16 + i * 32));
        }
    }

    function _packSwapBytes(uint16 core, uint32[] memory tokens) internal pure returns (bytes memory out) {
        uint256 len = tokens.length;
        out = new bytes(2 + len * 4);

        assembly {
            mstore(add(out, 32), shl(240, core))
        }

        for (uint256 i; i < len; ++i) {
            uint32 t = tokens[i];
            uint256 offset = 2 + i * 4;

            assembly {
                let ptr := add(add(out, 32), offset)
                mstore(ptr, shl(224, t))
            }
        }
    }

    function _unpackSwapBytes(bytes memory data) internal pure returns (uint16 core, uint32[] memory tokens) {
        assembly {
            core := shr(240, mload(add(data, 32)))
        }

        uint256 len = (data.length - 2) / 4;
        tokens = new uint32[](len);

        for (uint256 i; i < len; ++i) {
            uint32 t;
            uint256 offset = 2 + i * 4;

            assembly {
                let ptr := add(add(data, 32), offset)
                t := shr(224, mload(ptr))
            }

            tokens[i] = t;
        }
    }

    function _packSwapCore(SwapV2GuardResult memory guardResult) internal pure returns (uint16 result) {
        if (guardResult.ROUTER_NOT_TRUSTED) result |= uint16(1) << 0;
        if (guardResult.FACTORY_NOT_TRUSTED) result |= uint16(1) << 1;
        if (guardResult.DEEP_MULTIHOP) result |= uint16(1) << 2;
        if (guardResult.DUPLICATE_TOKEN_IN_PATH) result |= uint16(1) << 3;
        if (guardResult.POOL_NOT_EXISTS) result |= uint16(1) << 4;
        if (guardResult.FACTORY_MISMATCH) result |= uint16(1) << 5;
        if (guardResult.ZERO_LIQUIDITY) result |= uint16(1) << 6;
        if (guardResult.LOW_LIQUIDITY) result |= uint16(1) << 7;
        if (guardResult.LOW_LP_SUPPLY) result |= uint16(1) << 8;
        if (guardResult.POOL_TOO_NEW) result |= uint16(1) << 9;
        if (guardResult.SEVERE_IMBALANCE) result |= uint16(1) << 10;
        if (guardResult.K_INVARIANT_BROKEN) result |= uint16(1) << 11;
        if (guardResult.HIGH_SWAP_IMPACT) result |= uint16(1) << 12;
        if (guardResult.FLASHLOAN_RISK) result |= uint16(1) << 13;
        if (guardResult.PRICE_MANIPULATED) result |= uint16(1) << 14;
    }

    function _unpackSwapCore(uint16 packed) internal pure returns (SwapV2GuardResult memory result) {
        result.ROUTER_NOT_TRUSTED = (packed >> 0) & 1 == 1;
        result.FACTORY_NOT_TRUSTED = (packed >> 1) & 1 == 1;
        result.DEEP_MULTIHOP = (packed >> 2) & 1 == 1;
        result.DUPLICATE_TOKEN_IN_PATH = (packed >> 3) & 1 == 1;
        result.POOL_NOT_EXISTS = (packed >> 4) & 1 == 1;
        result.FACTORY_MISMATCH = (packed >> 5) & 1 == 1;
        result.ZERO_LIQUIDITY = (packed >> 6) & 1 == 1;
        result.LOW_LIQUIDITY = (packed >> 7) & 1 == 1;
        result.LOW_LP_SUPPLY = (packed >> 8) & 1 == 1;
        result.POOL_TOO_NEW = (packed >> 9) & 1 == 1;
        result.SEVERE_IMBALANCE = (packed >> 10) & 1 == 1;
        result.K_INVARIANT_BROKEN = (packed >> 11) & 1 == 1;
        result.HIGH_SWAP_IMPACT = (packed >> 12) & 1 == 1;
        result.FLASHLOAN_RISK = (packed >> 13) & 1 == 1;
        result.PRICE_MANIPULATED = (packed >> 14) & 1 == 1;
    }

    function _packToken(TokenGuardResult memory tokenResult) internal pure returns (uint32 result) {
        if (tokenResult.NOT_A_CONTRACT) result |= uint32(1) << 0;
        if (tokenResult.EMPTY_BYTECODE) result |= uint32(1) << 1;
        if (tokenResult.DECIMALS_REVERT) result |= uint32(1) << 2;
        if (tokenResult.WEIRD_DECIMALS) result |= uint32(1) << 3;
        if (tokenResult.HIGH_DECIMALS) result |= uint32(1) << 4;
        if (tokenResult.TOTAL_SUPPLY_REVERT) result |= uint32(1) << 5;
        if (tokenResult.ZERO_TOTAL_SUPPLY) result |= uint32(1) << 6;
        if (tokenResult.VERY_LOW_TOTAL_SUPPLY) result |= uint32(1) << 7;
        if (tokenResult.SYMBOL_REVERT) result |= uint32(1) << 8;
        if (tokenResult.NAME_REVERT) result |= uint32(1) << 9;
        if (tokenResult.IS_EIP1967_PROXY) result |= uint32(1) << 10;
        if (tokenResult.IS_EIP1822_PROXY) result |= uint32(1) << 11;
        if (tokenResult.IS_MINIMAL_PROXY) result |= uint32(1) << 12;
        if (tokenResult.HAS_OWNER) result |= uint32(1) << 13;
        if (tokenResult.OWNERSHIP_RENOUNCED) result |= uint32(1) << 14;
        if (tokenResult.OWNER_IS_EOA) result |= uint32(1) << 15;
        if (tokenResult.IS_PAUSABLE) result |= uint32(1) << 16;
        if (tokenResult.IS_CURRENTLY_PAUSED) result |= uint32(1) << 17;
        if (tokenResult.HAS_BLACKLIST) result |= uint32(1) << 18;
        if (tokenResult.HAS_BLOCKLIST) result |= uint32(1) << 19;
        if (tokenResult.POSSIBLE_FEE_ON_TRANSFER) result |= uint32(1) << 20;
        if (tokenResult.HAS_TRANSFER_FEE_GETTER) result |= uint32(1) << 21;
        if (tokenResult.HAS_TAX_FUNCTION) result |= uint32(1) << 22;
        if (tokenResult.POSSIBLE_REBASING) result |= uint32(1) << 23;
        if (tokenResult.HAS_MINT_CAPABILITY) result |= uint32(1) << 24;
        if (tokenResult.HAS_BURN_CAPABILITY) result |= uint32(1) << 25;
        if (tokenResult.HAS_PERMIT) result |= uint32(1) << 26;
        if (tokenResult.HAS_FLASH_MINT) result |= uint32(1) << 27;
    }

    function _unpackToken(uint32 packed) internal pure returns (TokenGuardResult memory result) {
        result.NOT_A_CONTRACT = (packed >> 0) & 1 == 1;
        result.EMPTY_BYTECODE = (packed >> 1) & 1 == 1;
        result.DECIMALS_REVERT = (packed >> 2) & 1 == 1;
        result.WEIRD_DECIMALS = (packed >> 3) & 1 == 1;
        result.HIGH_DECIMALS = (packed >> 4) & 1 == 1;
        result.TOTAL_SUPPLY_REVERT = (packed >> 5) & 1 == 1;
        result.ZERO_TOTAL_SUPPLY = (packed >> 6) & 1 == 1;
        result.VERY_LOW_TOTAL_SUPPLY = (packed >> 7) & 1 == 1;
        result.SYMBOL_REVERT = (packed >> 8) & 1 == 1;
        result.NAME_REVERT = (packed >> 9) & 1 == 1;
        result.IS_EIP1967_PROXY = (packed >> 10) & 1 == 1;
        result.IS_EIP1822_PROXY = (packed >> 11) & 1 == 1;
        result.IS_MINIMAL_PROXY = (packed >> 12) & 1 == 1;
        result.HAS_OWNER = (packed >> 13) & 1 == 1;
        result.OWNERSHIP_RENOUNCED = (packed >> 14) & 1 == 1;
        result.OWNER_IS_EOA = (packed >> 15) & 1 == 1;
        result.IS_PAUSABLE = (packed >> 16) & 1 == 1;
        result.IS_CURRENTLY_PAUSED = (packed >> 17) & 1 == 1;
        result.HAS_BLACKLIST = (packed >> 18) & 1 == 1;
        result.HAS_BLOCKLIST = (packed >> 19) & 1 == 1;
        result.POSSIBLE_FEE_ON_TRANSFER = (packed >> 20) & 1 == 1;
        result.HAS_TRANSFER_FEE_GETTER = (packed >> 21) & 1 == 1;
        result.HAS_TAX_FUNCTION = (packed >> 22) & 1 == 1;
        result.POSSIBLE_REBASING = (packed >> 23) & 1 == 1;
        result.HAS_MINT_CAPABILITY = (packed >> 24) & 1 == 1;
        result.HAS_BURN_CAPABILITY = (packed >> 25) & 1 == 1;
        result.HAS_PERMIT = (packed >> 26) & 1 == 1;
        result.HAS_FLASH_MINT = (packed >> 27) & 1 == 1;
    }
}
