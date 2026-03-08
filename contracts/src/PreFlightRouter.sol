// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  PreFlightRouter  (v2 — with RiskReportNFT integration)
 * @notice Single atomic entry point for the PreFlight browser extension.
 *
 * ─── User flow ───────────────────────────────────────────────────────────
 *
 *  1. [OFF-CHAIN — eth_call]
 *     simulateVault() or simulateSwap()
 *     → full flag struct + criticalBlock bool, zero gas
 *
 *  2. [STORE CHECK — on-chain tx]
 *     storeVaultCheck() or storeSwapCheck()
 *     → calls guard.storeCheckFor(user) to record fingerprint in guard storage
 *     → mints a RiskReportNFT to the user representing the check state
 *     → returns tokenId
 *
 *  3. [EXECUTE — on-chain tx, SAME BLOCK as step 2]
 *     executeVaultDeposit() / executeVaultRedeem() / executeSwap()
 *     → calls guard.validateFor(user) — reverts if state changed since step 2
 *     → enforces policy on result flags
 *     → performs the underlying action atomically
 *     → calls nft.consume(tokenId) to mark the report as CONSUMED
 *
 * ─── Separation of concerns ──────────────────────────────────────────────
 *   • VaultGuard / SwapV2Guard  — all check logic lives here
 *   • RiskReportNFT             — all NFT logic lives here
 *   • PreFlightRouter           — coordination, policy enforcement, token flows
 *
 * ─────────────────────────────────────────────────────────────────────────
 */

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {RiskReportNFT} from "./RiskReportNFT.sol";

/*//////////////////////////////////////////////////////////////
             GUARD INTERFACES  (kept in sync with guard contracts)
//////////////////////////////////////////////////////////////*/

struct VaultGuardResult {
    bool VAULT_NOT_WHITELISTED;
    bool VAULT_ZERO_SUPPLY;
    bool DONATION_ATTACK;
    bool SHARE_INFLATION_RISK;
    bool VAULT_BALANCE_MISMATCH;
    bool EXCHANGE_RATE_ANOMALY;
    bool PREVIEW_REVERT;
    bool ZERO_SHARES_OUT;
    bool ZERO_ASSETS_OUT;
    bool DUST_SHARES;
    bool DUST_ASSETS;
    bool EXCEEDS_MAX_DEPOSIT;
    bool EXCEEDS_MAX_REDEEM;
    bool PREVIEW_CONVERT_MISMATCH;
}

struct SwapGuardResult {
    bool DEEP_MULTIHOP;
    bool DUPLICATE_TOKEN_IN_PATH;
    bool POOL_NOT_EXISTS;
    bool FACTORY_MISMATCH;
    bool ZERO_LIQUIDITY;
    bool LOW_LIQUIDITY;
    bool LOW_LP_SUPPLY;
    bool POOL_TOO_NEW;
    bool SEVERE_IMBALANCE;
    bool K_INVARIANT_BROKEN;
    bool HIGH_SWAP_IMPACT;
    bool FLASHLOAN_RISK;
    bool PRICE_MANIPULATED;
}

interface IVaultGuard {
    /// Pure view — no state changes. Used by simulateVault and storeVaultCheck.
    function checkVault(address vault, uint256 amount, bool isDeposit)
        external
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets);

    /// Stores the check fingerprint for `user`. Only callable by authorizedRouter.
    /// Returns the keccak256 hash of the stored check (used to build the NFT checkHash).
    function storeCheckFor(address vault, uint256 amount, bool isDeposit, address user)
        external
        returns (bytes32 checkHash);

    /// Validates that the current state matches the fingerprint stored for `user`.
    /// Reverts with a descriptive message on mismatch or staleness.
    function validateFor(address vault, uint256 amount, bool isDeposit, address user) external view;
}

interface ISwapV2Guard {
    /// Pure view — no state changes. Used by simulateSwap and storeSwapCheck.
    function swapCheckV2(address router, address[] calldata path, uint256 amountIn)
        external
        view
        returns (SwapGuardResult memory result);

    /// Stores the swap check fingerprint for `user`. Only callable by authorizedRouter.
    function storeSwapCheckFor(address router, address[] calldata path, uint256 amountIn, address user)
        external
        returns (bytes32 checkHash);

    /// Validates that the current state matches the stored swap fingerprint for `user`.
    function validateSwapFor(address router, address[] calldata path, uint256 amountIn, address user) external view;
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/*//////////////////////////////////////////////////////////////
                        POLICY  STRUCT
//////////////////////////////////////////////////////////////*/

/**
 * @notice Per-call execution policy. Extension builds this struct from user settings.
 *
 * hardBlock[i] = true  → tx reverts if flag i is set, regardless of allowSoftRisk.
 * softWarn[i]  = true  → tx reverts if flag i is set AND allowSoftRisk == false.
 *
 * Pass a zero-initialised struct to use only the built-in absolute hard blocks.
 * Use defaultVaultHardBlocks() / defaultSwapHardBlocks() to get the floor set.
 *
 * Flag indices match the struct field declaration order in VaultGuardResult (14 fields)
 * and SwapGuardResult (13 fields).
 */
struct ExecutionPolicy {
    bool[14] hardBlockVault;
    bool[14] softWarnVault;
    bool[13] hardBlockSwap;
    bool[13] softWarnSwap;
}

/*//////////////////////////////////////////////////////////////
                        MAIN  CONTRACT
//////////////////////////////////////////////////////////////*/

contract PreFlightRouter is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    IVaultGuard public vaultGuard;
    ISwapV2Guard public swapGuard;
    RiskReportNFT public riskNFT;

    mapping(address => bool) public trustedRouters;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event GuardsUpdated(address vaultGuard, address swapGuard);
    event NFTUpdated(address nft);
    event RouterTrusted(address indexed router, bool trusted);

    event VaultCheckStored(
        address indexed user, address indexed vault, bool isDeposit, uint256 tokenId, RiskReportNFT.RiskLevel riskLevel
    );
    event SwapCheckStored(
        address indexed user, address indexed router, uint256 tokenId, RiskReportNFT.RiskLevel riskLevel
    );

    event VaultDepositExecuted(
        address indexed user,
        address indexed vault,
        uint256 assetsIn,
        uint256 sharesOut,
        address receiver,
        uint256 nftTokenId
    );
    event VaultRedeemExecuted(
        address indexed user,
        address indexed vault,
        uint256 sharesIn,
        uint256 assetsOut,
        address receiver,
        uint256 nftTokenId
    );
    event SwapExecuted(
        address indexed user,
        address indexed router,
        address[] path,
        uint256 amountIn,
        uint256 amountOut,
        uint256 nftTokenId
    );

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _vaultGuard, address _swapGuard, address _riskNFT) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        require(_vaultGuard != address(0) && _swapGuard != address(0) && _riskNFT != address(0), "ZERO_ADDRESS");
        vaultGuard = IVaultGuard(_vaultGuard);
        swapGuard = ISwapV2Guard(_swapGuard);
        riskNFT = RiskReportNFT(_riskNFT);
        emit GuardsUpdated(_vaultGuard, _swapGuard);
        emit NFTUpdated(_riskNFT);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
        STEP 1 — SIMULATION  (eth_call, zero gas, zero state)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Simulate a vault deposit or redeem. Call via eth_call before any tx.
     * @return result        Full VaultGuardResult flag struct.
     * @return previewShares Estimated shares minted (deposit) or 0.
     * @return previewAssets Estimated assets returned (redeem) or 0.
     * @return criticalBlock true if execution would be hard-blocked by default policy.
     * @return riskLevel     SAFE / WARNING / CRITICAL — for immediate UI display.
     */
    function simulateVault(address vault, uint256 amount, bool isDeposit)
        external
        view
        returns (
            VaultGuardResult memory result,
            uint256 previewShares,
            uint256 previewAssets,
            bool criticalBlock,
            RiskReportNFT.RiskLevel riskLevel
        )
    {
        (result, previewShares, previewAssets) = vaultGuard.checkVault(vault, amount, isDeposit);
        criticalBlock = _vaultHasCritical(result, isDeposit);
        riskLevel = _computeVaultRisk(result);
    }

    /**
     * @notice Simulate a V2 swap. Call via eth_call before any tx.
     * @return result        Full SwapGuardResult flag struct.
     * @return criticalBlock true if execution would be hard-blocked by default policy.
     * @return riskLevel     SAFE / WARNING / CRITICAL.
     */
    function simulateSwap(address router, address[] calldata path, uint256 amountIn)
        external
        view
        returns (SwapGuardResult memory result, bool criticalBlock, RiskReportNFT.RiskLevel riskLevel)
    {
        require(trustedRouters[router], "UNTRUSTED_ROUTER");
        result = swapGuard.swapCheckV2(router, path, amountIn);
        criticalBlock = _swapHasCritical(result);
        riskLevel = _computeSwapRisk(result);
    }

    /*//////////////////////////////////////////////////////////////
        STEP 2 — STORE CHECK + MINT NFT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Record the current vault state for `msg.sender` and mint a RiskReportNFT.
     *         Must be called in the same block as executeVaultDeposit / executeVaultRedeem.
     *
     * @param vault     ERC-4626 vault.
     * @param amount    Assets (deposit) or shares (redeem).
     * @param isDeposit true = deposit, false = redeem.
     * @return tokenId  The minted NFT token ID. Pass to the execute function.
     */
    function storeVaultCheck(address vault, uint256 amount, bool isDeposit)
        external
        nonReentrant
        returns (uint256 tokenId)
    {
        require(amount > 0, "ZERO_AMOUNT");

        // Run check to build NFT metadata (same data guard will store).
        (VaultGuardResult memory result, uint256 pShares, uint256 pAssets) =
            vaultGuard.checkVault(vault, amount, isDeposit);

        // Store fingerprint in VaultGuard (indexed by user, not router).
        bytes32 checkHash = vaultGuard.storeCheckFor(vault, amount, isDeposit, msg.sender);

        // Compute risk level and pack flags.
        RiskReportNFT.RiskLevel riskLevel = _computeVaultRisk(result);
        uint32 flagsPacked = _packVaultFlags(result);
        (uint8 crit, uint8 soft) = _countVaultFlags(result, isDeposit);
        uint256 previewValue = isDeposit ? pShares : pAssets;

        // Mint NFT.
        RiskReportNFT.RiskReport memory report = RiskReportNFT.RiskReport({
            reportType: isDeposit ? RiskReportNFT.ReportType.VAULT_DEPOSIT : RiskReportNFT.ReportType.VAULT_REDEEM,
            riskLevel: riskLevel,
            status: RiskReportNFT.Status.PENDING,
            user: msg.sender,
            target: vault,
            router: address(0),
            amount: amount,
            previewValue: previewValue,
            blockNumber: block.number,
            timestamp: block.timestamp,
            checkHash: checkHash,
            flagsPacked: flagsPacked,
            totalFlags: 14,
            criticalCount: crit,
            softCount: soft
        });

        tokenId = riskNFT.mint(msg.sender, report);

        emit VaultCheckStored(msg.sender, vault, isDeposit, tokenId, riskLevel);
    }

    /**
     * @notice Record the current swap state for `msg.sender` and mint a RiskReportNFT.
     *         Must be called in the same block as executeSwap.
     *
     * @param router    Trusted V2 router.
     * @param path      Token path.
     * @param amountIn  Exact input amount.
     * @return tokenId  The minted NFT token ID.
     */
    function storeSwapCheck(address router, address[] calldata path, uint256 amountIn)
        external
        nonReentrant
        returns (uint256 tokenId)
    {
        require(amountIn > 0, "ZERO_AMOUNT");
        require(path.length >= 2, "PATH_TOO_SHORT");
        require(trustedRouters[router], "UNTRUSTED_ROUTER");

        // Run check to build NFT metadata.
        SwapGuardResult memory result = swapGuard.swapCheckV2(router, path, amountIn);

        // Store fingerprint in SwapV2Guard.
        bytes32 checkHash = swapGuard.storeSwapCheckFor(router, path, amountIn, msg.sender);

        // Build NFT.
        RiskReportNFT.RiskLevel riskLevel = _computeSwapRisk(result);
        uint32 flagsPacked = _packSwapFlags(result);
        (uint8 crit, uint8 soft) = _countSwapFlags(result);

        RiskReportNFT.RiskReport memory report = RiskReportNFT.RiskReport({
            reportType: RiskReportNFT.ReportType.SWAP,
            riskLevel: riskLevel,
            status: RiskReportNFT.Status.PENDING,
            user: msg.sender,
            target: path[0],
            router: router,
            amount: amountIn,
            previewValue: 0,
            blockNumber: block.number,
            timestamp: block.timestamp,
            checkHash: checkHash,
            flagsPacked: flagsPacked,
            totalFlags: 13,
            criticalCount: crit,
            softCount: soft
        });

        tokenId = riskNFT.mint(msg.sender, report);

        emit SwapCheckStored(msg.sender, router, tokenId, riskLevel);
    }

    /*//////////////////////////////////////////////////////////////
        STEP 3 — EXECUTE  (validates then acts atomically)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets into an ERC-4626 vault.
     *
     * @param vault        ERC-4626 vault.
     * @param amount       Asset amount. Must match what was passed to storeVaultCheck.
     * @param receiver     Shares recipient.
     * @param minSharesOut Slippage floor.
     * @param nftTokenId   Token ID returned by storeVaultCheck. Will be consumed on success.
     * @param allowSoftRisk Proceed past soft-warn flags if true.
     * @param policy       Per-call policy. Zero-initialised = default floor only.
     */
    function executeVaultDeposit(
        address vault,
        uint256 amount,
        address receiver,
        uint256 minSharesOut,
        uint256 nftTokenId,
        bool allowSoftRisk,
        ExecutionPolicy calldata policy
    ) external nonReentrant returns (uint256 sharesOut) {
        require(amount > 0, "ZERO_AMOUNT");
        require(receiver != address(0), "ZERO_RECEIVER");
        _requireNFTPending(nftTokenId, msg.sender);

        // Re-run guard + validate state hasn't changed since storeVaultCheck.
        vaultGuard.guardedDeposit(vault, amount, true, msg.sender);


        // Consume NFT — marks as CONSUMED (permanent audit record).
        riskNFT.consume(nftTokenId);

        emit VaultDepositExecuted(msg.sender, vault, amount, sharesOut, receiver, nftTokenId);
    }

    /**
     * @notice Redeem shares from an ERC-4626 vault (shares → assets).
     *
     * @param vault        ERC-4626 vault.
     * @param shares       Share amount. Must match what was passed to storeVaultCheck.
     * @param receiver     Assets recipient.
     * @param minAssetsOut Slippage floor.
     * @param nftTokenId   Token ID returned by storeVaultCheck.
     * @param allowSoftRisk Proceed past soft-warn flags if true.
     * @param policy       Per-call policy.
     */
    function executeVaultRedeem(
        address vault,
        uint256 shares,
        address receiver,
        uint256 minAssetsOut,
        uint256 nftTokenId,
        bool allowSoftRisk,
        ExecutionPolicy calldata policy
    ) external nonReentrant returns (uint256 assetsOut) {
        require(shares > 0, "ZERO_SHARES");
        require(receiver != address(0), "ZERO_RECEIVER");
        _requireNFTPending(nftTokenId, msg.sender);

        vaultGuard.guardedRedeem(vault, shares, false, msg.sender);

        riskNFT.consume(nftTokenId);

        emit VaultRedeemExecuted(msg.sender, vault, shares, assetsOut, receiver, nftTokenId);
    }

    /**
     * @notice Execute a guarded V2 swap.
     *
     * @param router         Trusted V2 router.
     * @param amountIn       Exact input. Must match what was passed to storeSwapCheck.
     * @param amountOutMin   Slippage floor — enforced by router.
     * @param path           Token path.
     * @param receiver       Output token recipient.
     * @param deadline       Router deadline.
     * @param feeOnTransfer  Use fee-on-transfer variant. Set if TokenGuard flagged POSSIBLE_FEE_ON_TRANSFER.
     * @param nftTokenId     Token ID returned by storeSwapCheck.
     * @param allowSoftRisk  Proceed past soft-warn flags if true.
     * @param policy         Per-call policy.
     */
    function executeSwap(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address receiver,
        uint256 deadline,
        bool feeOnTransfer,
        uint256 nftTokenId,
        bool allowSoftRisk,
        ExecutionPolicy calldata policy
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "ZERO_AMOUNT");
        require(path.length >= 2, "PATH_TOO_SHORT");
        require(receiver != address(0), "ZERO_RECEIVER");
        _requireNFTPending(nftTokenId, msg.sender);


        // Fetch current result for policy.
        SwapGuardResult memory result = swapGuard.guardedexactTokentotoken(router, path, amountIn);
      

        riskNFT.consume(nftTokenId);

        emit SwapExecuted(msg.sender, router, path, amountIn, amountOut, nftTokenId);
    }

    /*//////////////////////////////////////////////////////////////
                        NFT  VALIDATION  HELPER
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Ensures the NFT exists, belongs to the caller, and is still PENDING.
     *      Reverts with clear messages to guide extension UX.
     */
    function _requireNFTPending(uint256 tokenId, address user) internal view {
        RiskReportNFT.RiskReport memory report = riskNFT.getReport(tokenId);
        require(report.user == user, "NFT: not your token");
        require(report.status == RiskReportNFT.Status.PENDING, "NFT: already consumed or expired");
        require(report.blockNumber == block.number, "NFT: stale (different block)");
    }

    /*//////////////////////////////////////////////////////////////
                    POLICY  ENFORCEMENT  (pure)
    //////////////////////////////////////////////////////////////*/

    function _enforceVaultPolicy(
        VaultGuardResult memory result,
        ExecutionPolicy calldata policy,
        bool allowSoftRisk,
        bool isDeposit
    ) internal pure {
        // ── Absolute hard blocks (no policy can override) ─────────────────
        require(!result.PREVIEW_REVERT, "GUARD: preview reverted");
        require(!result.DONATION_ATTACK, "GUARD: donation attack");
        require(!result.VAULT_BALANCE_MISMATCH, "GUARD: vault undercollateralised");
        if (isDeposit) {
            require(!result.ZERO_SHARES_OUT, "GUARD: deposit yields 0 shares");
            require(!result.EXCEEDS_MAX_DEPOSIT, "GUARD: exceeds deposit cap");
        } else {
            require(!result.ZERO_ASSETS_OUT, "GUARD: redeem yields 0 assets");
            require(!result.EXCEEDS_MAX_REDEEM, "GUARD: exceeds redeem cap");
        }

        // ── Policy-governed flags ─────────────────────────────────────────
        bool[14] memory flags = _vaultFlagsToArray(result);
        for (uint256 i = 0; i < 14;) {
            if (flags[i]) {
                if (policy.hardBlockVault[i]) revert("GUARD: vault hard block (policy)");
                if (!allowSoftRisk && policy.softWarnVault[i]) revert("GUARD: vault soft warn (policy)");
            }
            unchecked {
                ++i;
            }
        }
    }

    function _enforceSwapPolicy(
        SwapGuardResult memory result,
        ExecutionPolicy calldata policy,
        bool allowSoftRisk
    ) internal pure {
        // ── Absolute hard blocks ──────────────────────────────────────────
        require(!result.POOL_NOT_EXISTS, "GUARD: pool not exist");
        require(!result.ZERO_LIQUIDITY, "GUARD: zero liquidity");
        require(!result.DUPLICATE_TOKEN_IN_PATH, "GUARD: duplicate path");
        require(!result.K_INVARIANT_BROKEN, "GUARD: k-invariant broken");
        require(!result.PRICE_MANIPULATED, "GUARD: price manipulated");

        // ── Policy-governed flags ─────────────────────────────────────────
        bool[13] memory flags = _swapFlagsToArray(result);
        for (uint256 i = 0; i < 13;) {
            if (flags[i]) {
                if (policy.hardBlockSwap[i]) revert("GUARD: swap hard block (policy)");
                if (!allowSoftRisk && policy.softWarnSwap[i]) revert("GUARD: swap soft warn (policy)");
            }
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                RISK  LEVEL  COMPUTATION  (pure)
    //////////////////////////////////////////////////////////////*/

    function _computeVaultRisk(VaultGuardResult memory r) internal pure returns (RiskReportNFT.RiskLevel) {
        // Critical: any absolute hard-block flag
        if (
            r.PREVIEW_REVERT || r.DONATION_ATTACK || r.VAULT_BALANCE_MISMATCH || r.ZERO_SHARES_OUT || r.ZERO_ASSETS_OUT
                || r.EXCEEDS_MAX_DEPOSIT || r.EXCEEDS_MAX_REDEEM
        ) {
            return RiskReportNFT.RiskLevel.CRITICAL;
        }

        // Warning: any notable soft flag
        if (
            r.VAULT_NOT_WHITELISTED || r.SHARE_INFLATION_RISK || r.EXCHANGE_RATE_ANOMALY || r.PREVIEW_CONVERT_MISMATCH
                || r.VAULT_ZERO_SUPPLY || r.DUST_SHARES || r.DUST_ASSETS
        ) {
            return RiskReportNFT.RiskLevel.WARNING;
        }

        return RiskReportNFT.RiskLevel.SAFE;
    }

    function _computeSwapRisk(SwapGuardResult memory r) internal pure returns (RiskReportNFT.RiskLevel) {
        // Critical
        if (
            r.POOL_NOT_EXISTS || r.ZERO_LIQUIDITY || r.DUPLICATE_TOKEN_IN_PATH || r.K_INVARIANT_BROKEN
                || r.PRICE_MANIPULATED
        ) {
            return RiskReportNFT.RiskLevel.CRITICAL;
        }

        // Warning
        if (
            r.DEEP_MULTIHOP || r.FACTORY_MISMATCH || r.LOW_LIQUIDITY || r.LOW_LP_SUPPLY || r.POOL_TOO_NEW
                || r.SEVERE_IMBALANCE || r.HIGH_SWAP_IMPACT || r.FLASHLOAN_RISK
        ) {
            return RiskReportNFT.RiskLevel.WARNING;
        }

        return RiskReportNFT.RiskLevel.SAFE;
    }

    /*//////////////////////////////////////////////////////////////
            DEFAULT  POLICY  VIEWS  (for extension config)
    //////////////////////////////////////////////////////////////*/

    function defaultVaultHardBlocks() external pure returns (bool[14] memory h) {
        // Indices: 2=DONATION_ATTACK, 4=BALANCE_MISMATCH, 6=PREVIEW_REVERT,
        //          7=ZERO_SHARES, 8=ZERO_ASSETS, 11=EXCEEDS_DEPOSIT, 12=EXCEEDS_REDEEM
        h[2] = true;
        h[4] = true;
        h[6] = true;
        h[7] = true;
        h[8] = true;
        h[11] = true;
        h[12] = true;
    }

    function defaultSwapHardBlocks() external pure returns (bool[13] memory h) {
        // 1=DUPLICATE, 2=NO_POOL, 4=ZERO_LIQ, 9=K_BROKEN, 12=PRICE_MANIP
        h[1] = true;
        h[2] = true;
        h[4] = true;
        h[9] = true;
        h[12] = true;
    }

    /*//////////////////////////////////////////////////////////////
                FLAG  PACKING  &  COUNTING  (pure)
    //////////////////////////////////////////////////////////////*/

    function _packVaultFlags(VaultGuardResult memory r) internal pure returns (uint32 packed) {
        bool[14] memory f = _vaultFlagsToArray(r);
        for (uint8 i = 0; i < 14;) {
            if (f[i]) packed |= uint32(1) << i;
            unchecked {
                ++i;
            }
        }
    }

    function _packSwapFlags(SwapGuardResult memory r) internal pure returns (uint32 packed) {
        bool[13] memory f = _swapFlagsToArray(r);
        for (uint8 i = 0; i < 13;) {
            if (f[i]) packed |= uint32(1) << i;
            unchecked {
                ++i;
            }
        }
    }

    function _countVaultFlags(VaultGuardResult memory r, bool isDeposit)
        internal
        pure
        returns (uint8 crit, uint8 soft)
    {
        // Critical indices: 2,4,6,7(deposit),8(redeem),11(deposit),12(redeem)
        if (r.DONATION_ATTACK) crit++;
        if (r.VAULT_BALANCE_MISMATCH) crit++;
        if (r.PREVIEW_REVERT) crit++;
        if (isDeposit) {
            if (r.ZERO_SHARES_OUT) crit++;
            if (r.EXCEEDS_MAX_DEPOSIT) crit++;
        } else {
            if (r.ZERO_ASSETS_OUT) crit++;
            if (r.EXCEEDS_MAX_REDEEM) crit++;
        }
        // Soft
        if (r.VAULT_NOT_WHITELISTED) soft++;
        if (r.VAULT_ZERO_SUPPLY) soft++;
        if (r.SHARE_INFLATION_RISK) soft++;
        if (r.EXCHANGE_RATE_ANOMALY) soft++;
        if (r.DUST_SHARES) soft++;
        if (r.DUST_ASSETS) soft++;
        if (r.PREVIEW_CONVERT_MISMATCH) soft++;
    }

    function _countSwapFlags(SwapGuardResult memory r) internal pure returns (uint8 crit, uint8 soft) {
        if (r.POOL_NOT_EXISTS) crit++;
        if (r.ZERO_LIQUIDITY) crit++;
        if (r.DUPLICATE_TOKEN_IN_PATH) crit++;
        if (r.K_INVARIANT_BROKEN) crit++;
        if (r.PRICE_MANIPULATED) crit++;

        if (r.DEEP_MULTIHOP) soft++;
        if (r.FACTORY_MISMATCH) soft++;
        if (r.LOW_LIQUIDITY) soft++;
        if (r.LOW_LP_SUPPLY) soft++;
        if (r.POOL_TOO_NEW) soft++;
        if (r.SEVERE_IMBALANCE) soft++;
        if (r.HIGH_SWAP_IMPACT) soft++;
        if (r.FLASHLOAN_RISK) soft++;
    }

    /*//////////////////////////////////////////////////////////////
                DEFAULT  CRITICAL  HELPERS  (pure)
    //////////////////////////////////////////////////////////////*/

    function _vaultHasCritical(VaultGuardResult memory r, bool isDeposit) internal pure returns (bool) {
        if (r.PREVIEW_REVERT || r.DONATION_ATTACK || r.VAULT_BALANCE_MISMATCH) return true;
        if (isDeposit) return r.ZERO_SHARES_OUT || r.EXCEEDS_MAX_DEPOSIT;
        return r.ZERO_ASSETS_OUT || r.EXCEEDS_MAX_REDEEM;
    }

    function _swapHasCritical(SwapGuardResult memory r) internal pure returns (bool) {
        return r.POOL_NOT_EXISTS || r.ZERO_LIQUIDITY || r.DUPLICATE_TOKEN_IN_PATH || r.K_INVARIANT_BROKEN
            || r.PRICE_MANIPULATED;
    }

    /*//////////////////////////////////////////////////////////////
            FLAG → ARRAY  (ordering must match policy indices)
    //////////////////////////////////////////////////////////////*/

    function _vaultFlagsToArray(VaultGuardResult memory r) internal pure returns (bool[14] memory f) {
        f[0] = r.VAULT_NOT_WHITELISTED;
        f[1] = r.VAULT_ZERO_SUPPLY;
        f[2] = r.DONATION_ATTACK;
        f[3] = r.SHARE_INFLATION_RISK;
        f[4] = r.VAULT_BALANCE_MISMATCH;
        f[5] = r.EXCHANGE_RATE_ANOMALY;
        f[6] = r.PREVIEW_REVERT;
        f[7] = r.ZERO_SHARES_OUT;
        f[8] = r.ZERO_ASSETS_OUT;
        f[9] = r.DUST_SHARES;
        f[10] = r.DUST_ASSETS;
        f[11] = r.EXCEEDS_MAX_DEPOSIT;
        f[12] = r.EXCEEDS_MAX_REDEEM;
        f[13] = r.PREVIEW_CONVERT_MISMATCH;
    }

    function _swapFlagsToArray(SwapGuardResult memory r) internal pure returns (bool[13] memory f) {
        f[0] = r.DEEP_MULTIHOP;
        f[1] = r.DUPLICATE_TOKEN_IN_PATH;
        f[2] = r.POOL_NOT_EXISTS;
        f[3] = r.FACTORY_MISMATCH;
        f[4] = r.ZERO_LIQUIDITY;
        f[5] = r.LOW_LIQUIDITY;
        f[6] = r.LOW_LP_SUPPLY;
        f[7] = r.POOL_TOO_NEW;
        f[8] = r.SEVERE_IMBALANCE;
        f[9] = r.K_INVARIANT_BROKEN;
        f[10] = r.HIGH_SWAP_IMPACT;
        f[11] = r.FLASHLOAN_RISK;
        f[12] = r.PRICE_MANIPULATED;
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    function setVaultGuard(address addr) external onlyOwner {
        require(addr != address(0), "ZERO_ADDRESS");
        vaultGuard = IVaultGuard(addr);
        emit GuardsUpdated(addr, address(swapGuard));
    }

    function setSwapGuard(address addr) external onlyOwner {
        require(addr != address(0), "ZERO_ADDRESS");
        swapGuard = ISwapV2Guard(addr);
        emit GuardsUpdated(address(vaultGuard), addr);
    }

    function setRiskNFT(address addr) external onlyOwner {
        require(addr != address(0), "ZERO_ADDRESS");
        riskNFT = RiskReportNFT(addr);
        emit NFTUpdated(addr);
    }

    function setTrustedRouter(address router, bool trusted) external onlyOwner {
        require(router != address(0), "ZERO_ADDRESS");
        trustedRouters[router] = trusted;
        emit RouterTrusted(router, trusted);
    }

    function setTrustedRouters(address[] calldata routers, bool trusted) external onlyOwner {
        for (uint256 i = 0; i < routers.length;) {
            if (routers[i] != address(0)) {
                trustedRouters[routers[i]] = trusted;
                emit RouterTrusted(routers[i], trusted);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Emergency token recovery for funds accidentally stuck in this contract.
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "ZERO_ADDRESS");
        IERC20(token).safeTransfer(to, amount);
    }
}
