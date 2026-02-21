// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  PreFlightRouter
 * @notice Single atomic entry point for the PreFlight browser extension.
 *
 * Architecture
 * ────────────
 * Extension flow (per intercepted tx):
 *
 *   1. [OFF-CHAIN — eth_call]
 *      extension calls simulateVault() or simulateSwap()
 *      → returns full result struct, preview amounts, no gas spent
 *
 *   2. [EXTENSION UI]
 *      flags are mapped to user-facing warnings / hard blocks via Policy.
 *      User confirms or cancels.
 *
 *   3. [ON-CHAIN — real tx]
 *      extension submits executeVaultDeposit / executeVaultRedeem / executeSwap
 *      → re-runs guard (NO repeated check logic — delegates 100% to guard contracts)
 *      → applies Policy (which flags are hard-block vs soft-warn)
 *      → executes the underlying action atomically
 *      → reverts the entire tx if state changed between simulation and execution
 *
 * This contract is ONLY a coordinator:
 *   • It contains ZERO check logic — that lives in VaultGuard / SwapV2Guard
 *   • It contains ZERO ERC20 logic — that lives in TokenGuard (via VaultGuard)
 *   • It enforces Policy and orchestrates token flows
 *
 * Interfaces are kept in sync with the updated guard contracts
 * (VaultGuard v2 and SwapV2Guard v2).
 */

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/*//////////////////////////////////////////////////////////////
                   GUARD INTERFACES (kept in sync)
//////////////////////////////////////////////////////////////*/

/**
 * @dev Must mirror VaultGuard.VaultGuardResult exactly.
 *      If VaultGuard is upgraded and fields change, update this.
 */
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
    // TokenGuardResult is intentionally NOT mirrored here.
    // The router only reads vault-level flags for policy enforcement.
    // Token-level details are consumed by the UI layer via simulateVault().
}

/**
 * @dev Must mirror SwapV2Guard.GuardResultV2 exactly.
 */
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
    function checkVault(
        address vault,
        uint256 amount,
        bool    isDeposit
    ) external view returns (
        VaultGuardResult memory result,
        uint256          previewShares,
        uint256          previewAssets
    );
}

interface ISwapV2Guard {
    function swapCheckV2(
        address          router,
        address[] calldata path,
        uint256          amountIn
    ) external view returns (SwapGuardResult memory result);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256          amountIn,
        uint256          amountOutMin,
        address[] calldata path,
        address          to,
        uint256          deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256          amountIn,
        uint256          amountOutMin,
        address[] calldata path,
        address          to,
        uint256          deadline
    ) external;
}

/*//////////////////////////////////////////////////////////////
                   POLICY STRUCT
//////////////////////////////////////////////////////////////*/

/**
 * @notice Defines which guard flags cause a hard revert vs which are allowed
 *         if the caller explicitly opts in.
 *
 * The browser extension sets this per-transaction based on user preferences
 * and risk settings. Conservative mode sets both arrays to all-true.
 *
 * hardBlockVault[i] / hardBlockSwap[i] correspond to the i-th bool field of
 * VaultGuardResult / SwapGuardResult in declaration order.
 *
 * Soft-warn flags are passed as softBlockVault / softBlockSwap.
 * If any soft flag is triggered AND allowRisk == false, the tx reverts.
 *
 * NOTE: PREVIEW_REVERT, ZERO_SHARES_OUT, ZERO_ASSETS_OUT are ALWAYS hard-blocked
 *       regardless of policy — they represent states where execution is nonsensical.
 */
struct ExecutionPolicy {
    // vault hard blocks (index matches VaultGuardResult field order, skipping tokenResult)
    bool[14] hardBlockVault;
    // vault soft warns
    bool[14] softWarnVault;
    // swap hard blocks (index matches SwapGuardResult field order)
    bool[13] hardBlockSwap;
    // swap soft warns
    bool[13] softWarnSwap;
}

/*//////////////////////////////////////////////////////////////
                   MAIN CONTRACT
//////////////////////////////////////////////////////////////*/

contract PreFlightRouter is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    IVaultGuard  public vaultGuard;
    ISwapV2Guard public swapGuard;

    /// Only routers set here can be used via executeSwap.
    mapping(address => bool) public trustedRouters;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event GuardsUpdated(address vaultGuard, address swapGuard);
    event RouterTrusted(address indexed router, bool trusted);

    event VaultDepositExecuted(
        address indexed user,
        address indexed vault,
        uint256         assetsIn,
        uint256         sharesOut,
        address         receiver
    );

    event VaultRedeemExecuted(
        address indexed user,
        address indexed vault,
        uint256         sharesIn,
        uint256         assetsOut,
        address         receiver
    );

    event SwapExecuted(
        address indexed user,
        address indexed router,
        address[]       path,
        uint256         amountIn,
        uint256         amountOut   // actual output from router return value
    );

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _vaultGuard, address _swapGuard) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        require(_vaultGuard != address(0) && _swapGuard != address(0), "ZERO_GUARD");
        vaultGuard = IVaultGuard(_vaultGuard);
        swapGuard  = ISwapV2Guard(_swapGuard);
        emit GuardsUpdated(_vaultGuard, _swapGuard);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
        STEP 1 — OFF-CHAIN SIMULATION (eth_call, no gas, no state)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pure view simulation for vault deposit/redeem.
     *         Call via eth_call from the extension to show warnings before tx.
     *
     * @param vault     ERC-4626 vault
     * @param amount    Assets (deposit) or shares (redeem)
     * @param isDeposit true = deposit, false = redeem
     * @return result       Full flag struct
     * @return previewShares Estimated shares minted (deposit) or 0
     * @return previewAssets Estimated assets returned (redeem) or 0
     * @return criticalBlock true if any flag would cause a hard block with the default policy
     */
    function simulateVault(
        address vault,
        uint256 amount,
        bool    isDeposit
    )
        external
        view
        returns (
            VaultGuardResult memory result,
            uint256          previewShares,
            uint256          previewAssets,
            bool             criticalBlock
        )
    {
        (result, previewShares, previewAssets) =
            vaultGuard.checkVault(vault, amount, isDeposit);

        criticalBlock = _vaultHasCritical(result, isDeposit);
    }

    /**
     * @notice Pure view simulation for a V2 swap.
     *         Call via eth_call from the extension to show warnings before tx.
     *
     * @param router    Uniswap V2-compatible router
     * @param path      Token path
     * @param amountIn  Exact input amount (used for impact check inside guard)
     * @return result        Full flag struct
     * @return criticalBlock true if any flag would cause a hard block with the default policy
     */
    function simulateSwap(
        address          router,
        address[] calldata path,
        uint256          amountIn
    )
        external
        view
        returns (
            SwapGuardResult memory result,
            bool            criticalBlock
        )
    {
        require(trustedRouters[router], "UNTRUSTED_ROUTER");
        result = swapGuard.swapCheckV2(router, path, amountIn);
        criticalBlock = _swapHasCritical(result);
    }

    /*//////////////////////////////////////////////////////////////
        STEP 2 — ON-CHAIN EXECUTION (re-checks then executes atomically)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets into an ERC-4626 vault.
     *
     * Flow:
     *   1. Re-runs VaultGuard.checkVault (source of truth — no repeated logic here)
     *   2. Applies policy — reverts on critical or (if !allowSoftRisk) soft flags
     *   3. Pulls assets from caller
     *   4. Approves vault
     *   5. Calls vault.deposit(amount, receiver)
     *   6. Enforces slippage via minSharesOut
     *
     * The caller must have approved this router for `amount` of the vault's asset.
     *
     * @param vault        ERC-4626 vault
     * @param amount       Asset amount to deposit
     * @param receiver     Address to receive shares
     * @param minSharesOut Minimum shares to receive (slippage protection)
     * @param allowSoftRisk If true, proceed despite soft-warn flags. User must explicitly set.
     * @param policy       Per-call policy override. Pass a zero-initialised struct to use defaults.
     */
    function executeVaultDeposit(
        address         vault,
        uint256         amount,
        address         receiver,
        uint256         minSharesOut,
        bool            allowSoftRisk,
        ExecutionPolicy calldata policy
    )
        external
        nonReentrant
        returns (uint256 sharesOut)
    {
        require(amount > 0,           "ZERO_AMOUNT");
        require(receiver != address(0), "ZERO_RECEIVER");

        // ── Re-run guard (delegates entirely to VaultGuard) ──────────────
        (VaultGuardResult memory result,,) =
            vaultGuard.checkVault(vault, amount, true);

        // ── Apply policy ──────────────────────────────────────────────────
        _enforceVaultPolicy(result, policy, allowSoftRisk, true);

        // ── Execute ───────────────────────────────────────────────────────
        IERC20 asset = IERC20(IERC4626(vault).asset());

        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.forceApprove(vault, amount);

        sharesOut = IERC4626(vault).deposit(amount, receiver);

        // ── Slippage check ────────────────────────────────────────────────
        require(sharesOut >= minSharesOut, "SLIPPAGE: insufficient shares");

        // Clear any residual approval (safety — some tokens require it)
        asset.forceApprove(vault, 0);

        emit VaultDepositExecuted(msg.sender, vault, amount, sharesOut, receiver);
    }

    /**
     * @notice Redeem shares from an ERC-4626 vault (shares in → assets out).
     *
     * Flow:
     *   1. Re-runs VaultGuard.checkVault
     *   2. Applies policy
     *   3. Pulls shares from caller (caller must approve this router for shares)
     *   4. Calls vault.redeem(shares, receiver, address(this))
     *   5. Enforces slippage via minAssetsOut
     *
     * WHY address(this) as owner:
     *   The router holds the shares after pulling them from the user.
     *   vault.redeem(shares, receiver, owner) burns shares from `owner`.
     *   Since the router now owns the shares (after safeTransferFrom), it is the owner.
     *   The assets go directly to `receiver`.
     *
     * @param vault        ERC-4626 vault
     * @param shares       Share amount to burn
     * @param receiver     Address to receive assets
     * @param minAssetsOut Minimum assets to receive (slippage protection)
     * @param allowSoftRisk If true, proceed despite soft-warn flags.
     * @param policy       Per-call policy override.
     */
    function executeVaultRedeem(
        address         vault,
        uint256         shares,
        address         receiver,
        uint256         minAssetsOut,
        bool            allowSoftRisk,
        ExecutionPolicy calldata policy
    )
        external
        nonReentrant
        returns (uint256 assetsOut)
    {
        require(shares > 0,            "ZERO_SHARES");
        require(receiver != address(0), "ZERO_RECEIVER");

        // ── Re-run guard ──────────────────────────────────────────────────
        (VaultGuardResult memory result,,) =
            vaultGuard.checkVault(vault, shares, false);

        // ── Apply policy ──────────────────────────────────────────────────
        _enforceVaultPolicy(result, policy, allowSoftRisk, false);

        // ── Pull shares from caller → this router ─────────────────────────
        // User must have approved the router for `shares` of the vault token.
        IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);

        // ── Approve vault to burn shares from this router (required by some vaults) ──
        // Most ERC-4626 implementations burn from `owner` directly via internal call,
        // but some override redeem to use transferFrom. Approve to handle both.
        IERC20(vault).forceApprove(vault, shares);

        // ── Execute redeem: shares owned by this contract → assets to receiver ──
        assetsOut = IERC4626(vault).redeem(shares, receiver, address(this));

        // ── Slippage check ────────────────────────────────────────────────
        require(assetsOut >= minAssetsOut, "SLIPPAGE: insufficient assets");

        IERC20(vault).forceApprove(vault, 0);

        emit VaultRedeemExecuted(msg.sender, vault, shares, assetsOut, receiver);
    }

    /**
     * @notice Execute a guarded UniswapV2-style token swap.
     *
     * Flow:
     *   1. Re-runs SwapV2Guard.swapCheckV2 (amountIn-aware, includes impact check)
     *   2. Applies policy
     *   3. Pulls tokenIn from caller
     *   4. Executes swap via router (standard or fee-on-transfer variant)
     *   5. Actual amountOut is logged from router return value
     *
     * @param router          Trusted UniswapV2-style router
     * @param amountIn        Exact input amount
     * @param amountOutMin    Minimum output (slippage protection — enforced by router)
     * @param path            Token path
     * @param receiver        Address to receive output tokens
     * @param deadline        Unix timestamp — router will revert if exceeded
     * @param feeOnTransfer   True = use swapExactTokensForTokensSupportingFeeOnTransferTokens
     *                        The extension should set this if POSSIBLE_FEE_ON_TRANSFER is flagged
     * @param allowSoftRisk   If true, proceed past soft-warn flags.
     * @param policy          Per-call policy override.
     */
    function executeSwap(
        address          router,
        uint256          amountIn,
        uint256          amountOutMin,
        address[] calldata path,
        address          receiver,
        uint256          deadline,
        bool             feeOnTransfer,
        bool             allowSoftRisk,
        ExecutionPolicy calldata policy
    )
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        require(amountIn > 0,          "ZERO_AMOUNT");
        require(path.length >= 2,      "PATH_TOO_SHORT");
        require(receiver != address(0), "ZERO_RECEIVER");
        require(trustedRouters[router], "UNTRUSTED_ROUTER");

        // ── Re-run guard (amountIn passed so guard can compute real impact) ──
        SwapGuardResult memory result =
            swapGuard.swapCheckV2(router, path, amountIn);

        // ── Apply policy ──────────────────────────────────────────────────
        _enforceSwapPolicy(result, policy, allowSoftRisk);

        // ── Pull tokenIn from caller ──────────────────────────────────────
        IERC20 tokenIn = IERC20(path[0]);
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        tokenIn.forceApprove(router, amountIn);

        // ── Execute swap ──────────────────────────────────────────────────
        if (feeOnTransfer) {
            // Fee-on-transfer variant doesn't return amounts array.
            // Capture output by reading receiver's balance delta.
            IERC20 tokenOut = IERC20(path[path.length - 1]);
            uint256 balBefore = tokenOut.balanceOf(receiver);

            IUniswapV2Router(router)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    amountIn, amountOutMin, path, receiver, deadline
                );

            uint256 balAfter = tokenOut.balanceOf(receiver);
            amountOut = balAfter - balBefore;
        } else {
            uint256[] memory amounts = IUniswapV2Router(router)
                .swapExactTokensForTokens(
                    amountIn, amountOutMin, path, receiver, deadline
                );
            amountOut = amounts[amounts.length - 1];
        }

        // Clear residual approval
        tokenIn.forceApprove(router, 0);

        emit SwapExecuted(msg.sender, router, path, amountIn, amountOut);
    }

    /*//////////////////////////////////////////////////////////////
                        POLICY ENFORCEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Enforces vault execution policy.
     *
     * Hardcoded critical blocks (always revert regardless of policy):
     *   PREVIEW_REVERT         — guard itself failed, state is unknown
     *   ZERO_SHARES_OUT        — deposit would mint nothing
     *   ZERO_ASSETS_OUT        — redeem would return nothing
     *   DONATION_ATTACK        — vault is in known attack state
     *   VAULT_BALANCE_MISMATCH — vault is undercollateralised right now
     *
     * Everything else is governed by the caller-supplied ExecutionPolicy.
     * If policy is zero-initialised (all false), only the hardcoded blocks apply.
     *
     * The `isDeposit` flag gates which zero-output check fires.
     */
    function _enforceVaultPolicy(
        VaultGuardResult memory result,
        ExecutionPolicy  calldata policy,
        bool             allowSoftRisk,
        bool             isDeposit
    ) internal pure {
        // ── Absolute hard blocks — no policy can override these ───────────
        require(!result.PREVIEW_REVERT,       "GUARD: preview reverted");
        require(!result.DONATION_ATTACK,      "GUARD: donation attack detected");
        require(!result.VAULT_BALANCE_MISMATCH,"GUARD: vault undercollateralised");
        if (isDeposit) {
            require(!result.ZERO_SHARES_OUT,  "GUARD: deposit yields zero shares");
            require(!result.EXCEEDS_MAX_DEPOSIT, "GUARD: exceeds vault deposit cap");
        } else {
            require(!result.ZERO_ASSETS_OUT,  "GUARD: redeem yields zero assets");
            require(!result.EXCEEDS_MAX_REDEEM, "GUARD: exceeds vault redeem cap");
        }

        // ── Policy-governed hard blocks ───────────────────────────────────
        // Fields in order of VaultGuardResult declaration (skipping tokenResult):
        // [0]  VAULT_NOT_WHITELISTED
        // [1]  VAULT_ZERO_SUPPLY
        // [2]  DONATION_ATTACK          — already handled above
        // [3]  SHARE_INFLATION_RISK
        // [4]  VAULT_BALANCE_MISMATCH   — already handled above
        // [5]  EXCHANGE_RATE_ANOMALY
        // [6]  PREVIEW_REVERT           — already handled above
        // [7]  ZERO_SHARES_OUT          — already handled above
        // [8]  ZERO_ASSETS_OUT          — already handled above
        // [9]  DUST_SHARES
        // [10] DUST_ASSETS
        // [11] EXCEEDS_MAX_DEPOSIT      — already handled above
        // [12] EXCEEDS_MAX_REDEEM       — already handled above
        // [13] PREVIEW_CONVERT_MISMATCH

        bool[14] memory flags = _vaultFlagsToArray(result);

        for (uint256 i = 0; i < 14; ) {
            if (!flags[i]) { unchecked { ++i; } continue; }
            if (policy.hardBlockVault[i]) {
                revert("GUARD: vault hard block by policy");
            }
            if (!allowSoftRisk && policy.softWarnVault[i]) {
                revert("GUARD: vault soft risk (set allowSoftRisk)");
            }
            unchecked { ++i; }
        }
    }

    /**
     * @dev Enforces swap execution policy.
     *
     * Hardcoded critical blocks:
     *   POOL_NOT_EXISTS       — nothing to swap against
     *   ZERO_LIQUIDITY        — pool is empty
     *   DUPLICATE_TOKEN_IN_PATH — circular / malformed path
     *   K_INVARIANT_BROKEN    — pool was drained abnormally
     *   PRICE_MANIPULATED     — TWAP deviation detected
     */
    function _enforceSwapPolicy(
        SwapGuardResult memory result,
        ExecutionPolicy calldata policy,
        bool            allowSoftRisk
    ) internal pure {
        // ── Absolute hard blocks ──────────────────────────────────────────
        require(!result.POOL_NOT_EXISTS,          "GUARD: pool does not exist");
        require(!result.ZERO_LIQUIDITY,           "GUARD: pool has zero liquidity");
        require(!result.DUPLICATE_TOKEN_IN_PATH,  "GUARD: circular/duplicate path");
        require(!result.K_INVARIANT_BROKEN,       "GUARD: pool k-invariant broken");
        require(!result.PRICE_MANIPULATED,        "GUARD: price manipulation detected");

        // ── Policy-governed blocks ────────────────────────────────────────
        // Fields in order of SwapGuardResult declaration:
        // [0]  DEEP_MULTIHOP
        // [1]  DUPLICATE_TOKEN_IN_PATH  — handled above
        // [2]  POOL_NOT_EXISTS          — handled above
        // [3]  FACTORY_MISMATCH
        // [4]  ZERO_LIQUIDITY           — handled above
        // [5]  LOW_LIQUIDITY
        // [6]  LOW_LP_SUPPLY
        // [7]  POOL_TOO_NEW
        // [8]  SEVERE_IMBALANCE
        // [9]  K_INVARIANT_BROKEN       — handled above
        // [10] HIGH_SWAP_IMPACT
        // [11] FLASHLOAN_RISK
        // [12] PRICE_MANIPULATED        — handled above

        bool[13] memory flags = _swapFlagsToArray(result);

        for (uint256 i = 0; i < 13; ) {
            if (!flags[i]) { unchecked { ++i; } continue; }
            if (policy.hardBlockSwap[i]) {
                revert("GUARD: swap hard block by policy");
            }
            if (!allowSoftRisk && policy.softWarnSwap[i]) {
                revert("GUARD: swap soft risk (set allowSoftRisk)");
            }
            unchecked { ++i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
            DEFAULT CRITICAL FLAG CHECKS (used by simulate*)
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns true if the vault result has any flag that the default policy blocks.
    function _vaultHasCritical(VaultGuardResult memory r, bool isDeposit)
        internal
        pure
        returns (bool)
    {
        if (r.PREVIEW_REVERT)        return true;
        if (r.DONATION_ATTACK)       return true;
        if (r.VAULT_BALANCE_MISMATCH) return true;
        if (isDeposit) {
            if (r.ZERO_SHARES_OUT)     return true;
            if (r.EXCEEDS_MAX_DEPOSIT) return true;
        } else {
            if (r.ZERO_ASSETS_OUT)     return true;
            if (r.EXCEEDS_MAX_REDEEM)  return true;
        }
        return false;
    }

    /// @dev Returns true if the swap result has any flag that the default policy blocks.
    function _swapHasCritical(SwapGuardResult memory r)
        internal
        pure
        returns (bool)
    {
        return (
            r.POOL_NOT_EXISTS         ||
            r.ZERO_LIQUIDITY          ||
            r.DUPLICATE_TOKEN_IN_PATH ||
            r.K_INVARIANT_BROKEN      ||
            r.PRICE_MANIPULATED
        );
    }

    /*//////////////////////////////////////////////////////////////
                   FLAG → ARRAY HELPERS (for policy loops)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Converts VaultGuardResult to a bool[14] for policy iteration.
     *      Order MUST match ExecutionPolicy.hardBlockVault / softWarnVault indices.
     */
    function _vaultFlagsToArray(VaultGuardResult memory r)
        internal
        pure
        returns (bool[14] memory f)
    {
        f[0]  = r.VAULT_NOT_WHITELISTED;
        f[1]  = r.VAULT_ZERO_SUPPLY;
        f[2]  = r.DONATION_ATTACK;
        f[3]  = r.SHARE_INFLATION_RISK;
        f[4]  = r.VAULT_BALANCE_MISMATCH;
        f[5]  = r.EXCHANGE_RATE_ANOMALY;
        f[6]  = r.PREVIEW_REVERT;
        f[7]  = r.ZERO_SHARES_OUT;
        f[8]  = r.ZERO_ASSETS_OUT;
        f[9]  = r.DUST_SHARES;
        f[10] = r.DUST_ASSETS;
        f[11] = r.EXCEEDS_MAX_DEPOSIT;
        f[12] = r.EXCEEDS_MAX_REDEEM;
        f[13] = r.PREVIEW_CONVERT_MISMATCH;
    }

    /**
     * @dev Converts SwapGuardResult to a bool[13] for policy iteration.
     *      Order MUST match ExecutionPolicy.hardBlockSwap / softWarnSwap indices.
     */
    function _swapFlagsToArray(SwapGuardResult memory r)
        internal
        pure
        returns (bool[13] memory f)
    {
        f[0]  = r.DEEP_MULTIHOP;
        f[1]  = r.DUPLICATE_TOKEN_IN_PATH;
        f[2]  = r.POOL_NOT_EXISTS;
        f[3]  = r.FACTORY_MISMATCH;
        f[4]  = r.ZERO_LIQUIDITY;
        f[5]  = r.LOW_LIQUIDITY;
        f[6]  = r.LOW_LP_SUPPLY;
        f[7]  = r.POOL_TOO_NEW;
        f[8]  = r.SEVERE_IMBALANCE;
        f[9]  = r.K_INVARIANT_BROKEN;
        f[10] = r.HIGH_SWAP_IMPACT;
        f[11] = r.FLASHLOAN_RISK;
        f[12] = r.PRICE_MANIPULATED;
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the default critical policy for a vault op.
     *         Useful for the extension to know what will hard-block without deploying a call.
     * @return hardBlock bool[14] where true = this flag index always reverts
     */
    function defaultVaultHardBlocks()
        external
        pure
        returns (bool[14] memory hardBlock)
    {
        // Indices that are always blocked (see _enforceVaultPolicy):
        // 2 = DONATION_ATTACK, 4 = VAULT_BALANCE_MISMATCH, 6 = PREVIEW_REVERT,
        // 7 = ZERO_SHARES_OUT, 8 = ZERO_ASSETS_OUT, 11 = EXCEEDS_MAX_DEPOSIT, 12 = EXCEEDS_MAX_REDEEM
        hardBlock[2]  = true;
        hardBlock[4]  = true;
        hardBlock[6]  = true;
        hardBlock[7]  = true;
        hardBlock[8]  = true;
        hardBlock[11] = true;
        hardBlock[12] = true;
    }

    /**
     * @notice Returns the default critical policy for a swap op.
     * @return hardBlock bool[13] where true = this flag index always reverts
     */
    function defaultSwapHardBlocks()
        external
        pure
        returns (bool[13] memory hardBlock)
    {
        // 1 = DUPLICATE_TOKEN, 2 = POOL_NOT_EXISTS, 4 = ZERO_LIQUIDITY,
        // 9 = K_INVARIANT_BROKEN, 12 = PRICE_MANIPULATED
        hardBlock[1]  = true;
        hardBlock[2]  = true;
        hardBlock[4]  = true;
        hardBlock[9]  = true;
        hardBlock[12] = true;
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

    function setTrustedRouter(address router, bool trusted) external onlyOwner {
        require(router != address(0), "ZERO_ADDRESS");
        trustedRouters[router] = trusted;
        emit RouterTrusted(router, trusted);
    }

    function setTrustedRouters(address[] calldata routers, bool trusted) external onlyOwner {
        for (uint256 i = 0; i < routers.length; ) {
            if (routers[i] != address(0)) {
                trustedRouters[routers[i]] = trusted;
                emit RouterTrusted(routers[i], trusted);
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Emergency token recovery for any tokens accidentally stuck in this contract.
     * @dev This contract should never hold user funds at rest — any residual balance
     *      is either a failed mid-tx state or a direct mistaken transfer.
     */
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "ZERO_ADDRESS");
        IERC20(token).safeTransfer(to, amount);
    }
}
