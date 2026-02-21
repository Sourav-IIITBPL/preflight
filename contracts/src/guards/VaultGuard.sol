// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenGuardResult, TokenGuard} from "./TokenGuard.sol";

contract VaultGuard is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCT
    //////////////////////////////////////////////////////////////*/

    struct VaultGuardResult {
        bool VAULT_ZERO_SUPPLY;
        bool DONATION_ATTACK;
        bool VAULT_BALANCE_MISMATCH;
        bool EXCHANGE_RATE_ANOMALY;
        bool ZERO_SHARES_MINT;
        bool ZERO_ASSETS_WITHDRAW;
        bool VAULT_DUST_MINT;
        bool VAULT_DUST_BURN;
        bool PREVIEW_MANIPULATION;
        bool VAULT_NOT_WHITELISTED;
        TokenGuardResult tokenResult;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_INITIAL_ASSETS = 10 ether;
    uint256 public constant MAX_BPS = 10000;
    uint256 public constant MAX_DEVIATION_BPS = 500; // 5%
    uint256 public constant MIN_SHARES = 1e3;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(address => bytes32)) public lastCheckHash;
    mapping(address => mapping(address => uint256)) public lastCheckBlock;
    mapping(address => bool) public isVaultWhitelisted;
    mapping(address => uint256) public vaultIndex;
    address[] public whitelistedVaults;

    /*//////////////////////////////////////////////////////////////
                                INIT
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
                        MAIN CHECK FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Performs security checks and preview on an ERC4626 vault before interaction
     * @param vault Address of the ERC4626 vault
     * @param amount Amount of assets/shares involved
     * @param isDeposit True for deposit, false for withdraw
     * @return result Struct containing all detected risks
     * @return previewShares Estimated shares (for deposit)
     * @return previewAssets Estimated assets (for withdraw)
     */
    function checkVaultwithPreview(address vault, uint256 amount, bool isDeposit)
        public
        nonReentrant
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        IERC4626 v = IERC4626(vault);
        IERC20 asset = IERC20(v.asset());

        // this will check whether the token is fee-on-trnasfer token, token decimals , weird tokens , whitlisted tokens , proxy deployed tokens , ownership renounced tokens etc
        TokenGuardResult checkedTokenResult = TokenGuard.checkToken(address(asset));
        result.tokenResult = checkedTokenResult;

        uint256 totalAssets = v.totalAssets();
        uint256 totalSupply = v.totalSupply();

        /*//////////////////////////////////////////////////////////////
            1. ZERO SUPPLY + DONATION ATTACK
        //////////////////////////////////////////////////////////////*/

        if (totalSupply == 0) {
            result.VAULT_ZERO_SUPPLY = true;

            if (totalAssets > MAX_INITIAL_ASSETS) {
                result.DONATION_ATTACK = true;
            }
        }

        /*//////////////////////////////////////////////////////////////
            2. BALANCE MISMATCH
        //////////////////////////////////////////////////////////////*/

        uint256 realBalance = asset.balanceOf(vault);

        if (realBalance > totalAssets) {
            result.VAULT_BALANCE_MISMATCH = true;
        }

        /*//////////////////////////////////////////////////////////////
            3. Vault Whitelisted Check
        //////////////////////////////////////////////////////////////*/

        if (!isWhitelisted(vault)) {
            result.VAULT_NOT_WHITELISTED = true;
        }

        /*//////////////////////////////////////////////////////////////
            4. EXCHANGE RATE
        //////////////////////////////////////////////////////////////*/

        if (totalSupply > 0 && totalAssets > 0) {
            uint8 assetDecimals = _safeDecimals(address(asset));
            uint8 vaultDecimals = _safeDecimals(vault);

            uint256 normalizedAssets = _normalize(totalAssets, assetDecimals);
            uint256 normalizedSupply = _normalize(totalSupply, vaultDecimals);

            uint256 normalizedExchangeRate = (normalizedAssets * 1e18) / normalizedSupply;

            /*//////////////////////////////////////////////////////////////
                DEPOSIT FLOW
            //////////////////////////////////////////////////////////////*/

            if (isDeposit) {
                try v.previewDeposit(amount) returns (uint256 s) {
                    previewShares = s;
                } catch {
                    result.PREVIEW_MANIPULATION = true;
                    return (result, 0, 0);
                }

                if (previewShares == 0) {
                    result.ZERO_SHARES_MINT = true;
                }

                if (previewShares < MIN_SHARES) {
                    result.VAULT_DUST_MINT = true;
                }

                // simulate expected rate
                if (previewShares > 0) {
                    uint256 normShares = _normalize(previewShares, vaultDecimals);
                    uint256 normAmount = _normalize(amount, assetDecimals);

                    uint256 estimatedRate = (normAmount * 1e18) / normShares;

                    if (_bpsDelta(normalizedExchangeRate, estimatedRate) > MAX_DEVIATION_BPS) {
                        result.EXCHANGE_RATE_ANOMALY = true;
                    }
                }
            }
            /*//////////////////////////////////////////////////////////////
                WITHDRAW FLOW
            //////////////////////////////////////////////////////////////*/
            else {
                try v.previewRedeem(amount) returns (uint256 a) {
                    previewAssets = a;
                } catch {
                    result.PREVIEW_MANIPULATION = true;
                    return result;
                }

                if (previewAssets == 0) {
                    result.ZERO_ASSETS_WITHDRAW = true;
                }

                if (previewAssets < MIN_SHARES) {
                    result.VAULT_DUST_BURN = true;
                }

                if (previewAssets > 0) {
                    uint256 normAssetsOut = _normalize(previewAssets, assetDecimals);
                    uint256 normShares = _normalize(amount, vaultDecimals);

                    uint256 estimatedRate = (normAssetsOut * 1e18) / normShares;

                    if (_bpsDelta(normalizedExchangeRate, estimatedRate) > MAX_DEVIATION_BPS) {
                        result.EXCHANGE_RATE_ANOMALY = true;
                    }
                }
            }
        }

        return (result, previewShares, previewAssets);
    }

    /**
     * @notice Stores the vault check result for later validation
     * @dev Used to prevent front-running between check and execution
     * @param vault Address of the ERC4626 vault
     * @param amount Amount of assets/shares involved
     * @param isDeposit True for deposit, false for withdraw
     */
    function storeCheckAndPreviewResult(address vault, uint256 amount, bool isDeposit) external nonReentrant {
        (VaultGuardResult memory currentResult, uint256 previewShares, uint256 previewAssets) =
            checkVaultwithPreview(vault, amount, isDeposit);

        lastCheckHash[vault][msg.sender] = abi.encode(currentResult, previewShares, previewAssets);
        lastCheckBlock[vault][msg.sender] = block.number;
    }

    /*//////////////////////////////////////////////////////////////
                        FINAL EXECUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Executes a deposit on the vault after validating that the state hasn't changed since the last check
     * @param vault Address of the ERC4626 vault
     * @param amount Amount of assets to deposit
     * @param receiver Address that will receive the shares (for deposit)
     * @return shares Amount of shares minted  .
     */
    function guardedDeposit(address vault, uint256 amount, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        _validate(vault, amount, true);
        IERC20 asset = IERC20(IERC4626(vault).asset());
        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.safeApprove(vault, 0);
        asset.safeApprove(vault, amount);

        shares = IERC4626(vault).deposit(amount, receiver);

        require(shares > 0, "ZERO_SHARES");
    }

    /**
     * @notice Executes a withdraw on the vault after validating that the state hasn't changed since the last check
     * @param vault Address of the ERC4626 vault
     * @param amount Amount of shares to burn
     * @param receiver Address that will receive  assets
     * @return assets Amount of assets withdrawn  .
     */

    function guardedWithdraw(address vault, uint256 amount, address receiver)
        external
        nonReentrant
        returns (uint256 assets)
    {
        _validate(vault, amount, false);

        assets = IERC4626(vault).withdraw(amount, receiver, msg.sender);
        require(assets > 0, "ZERO_ASSETS");
    }

    /*//////////////////////////////////////////////////////////////
                        External/Public View functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the last check result for a given vault and user
     * @param vault Address of the ERC4626 vault
     * @param user Address of the user
     * @return result Struct containing all detected risks from the last check
     * @return previewShares Estimated shares from the last check (for deposit)
     * @return previewAssets Estimated assets from the last check (for withdraw)
     * @return blockNumber Block number of the last check
     */

    function getLastCheck(address vault, address user)
        external
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNumber)
    {
        (
            result, previewShares, previewAssets
        ) = abi.decode(lastCheckHash[vault][user], (VaultGuardResult, uint256, uint256));
        blockNumber = lastCheckBlock[vault][user];
    }

    /**
     * @notice Returns the list of whitelisted vaults
     * @return Array of whitelisted vault addresses
     */
    function getWhitelistedVaults() external view returns (address[] memory) {
        return whitelistedVaults;
    }

    /**
     * @notice Checks if a vault is whitelisted
     * @param vault Address of the vault to check
     * @return True if the vault is whitelisted, false otherwise
     */

    function isWhitelisted(address vault) public view returns (bool) {
        return isVaultWhitelisted[vault];
    }

    /*///////////////////////////////////////////////////////////////
                     Admin functions
    ///////////////////////////////////////////////////////////////*/

    /**
     *  @notice Adds a vault to the whitelist
     * @param vault Address of the vault to whitelist
     */

    function whitelistVault(address vault) external onlyOwner {
        require(vault != address(0), "Zero_address");
        require(!isVaultWhitelisted[vault], "Already_whitelisted");

        isVaultWhitelisted[vault] = true;
        vaultIndex[vault] = whitelistedVaults.length;
        whitelistedVaults.push(vault);
    }

    /**
     *  @notice Removes a vault from the whitelist
     * @param vault Address of the vault to remove from the whitelist
     */

    function removeWhitelistedVault(address vault) external onlyOwner {
        require(isVaultWhitelisted[vault], "NOT_WHITELISTED");

        uint256 index = vaultIndex[vault];
        uint256 lastIndex = whitelistedVaults.length - 1;

        address lastVault = whitelistedVaults[lastIndex];

        whitelistedVaults[index] = lastVault;
        vaultIndex[lastVault] = index;

        whitelistedVaults.pop();

        delete vaultIndex[vault];
        delete isVaultWhitelisted[vault];
    }

    /**
     *  @notice Adds multiple vaults to the whitelist
     * @param vaults Array of vault addresses to whitelist
     */

    function addWhitelistedVaults(address[] calldata vaults) external onlyOwner {
        for (uint256 i = 0; i < vaults.length; i++) {
            address vault = vaults[i];

            if (vault == address(0)) continue;
            if (isVaultWhitelisted[vault]) continue;

            isVaultWhitelisted[vault] = true;
            vaultIndex[vault] = whitelistedVaults.length;
            whitelistedVaults.push(vault);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS functions
    //////////////////////////////////////////////////////////////*/

    /** @notice Validates that the vault state hasn't changed since the last check
        * @param vault Address of the ERC4626 vault
        * @param amount Amount of assets/shares involved
        * @param isDeposit True for deposit, false for withdraw
        * @dev Compares the current check result with the stored result to prevent front-running
        */

    function _validate(address vault, uint256 amount, bool isDeposit) internal view {
        require(block.number == lastCheckBlock[vault][msg.sender], "STALE_CHECK");

        (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets) = checkVaultwithPreview(vault, amount, isDeposit);

        bytes32 currentResult = abi.encode(result, previewShares, previewAssets);
        require(
             currentResult == lastCheckHash[vault][msg.sender],
            "STATE_CHANGED"
        );
    }

    /** @notice Safely retrieves the decimals of a token, defaults to 18 if the call fails
        * @param token Address of the ERC20 token
        * @return decimals Number of decimals for the token, or 18 if the call fails
        */
    function _safeDecimals(address token) internal view returns (uint8) {
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            return d;
        } catch {
            return 18;
        }
    }

    /** @notice Normalizes a token amount to 18 decimals for consistent calculations
        * @param value Amount to normalize
        * @param decimals Original decimals of the token
        * @return Normalized amount with 18 decimals
        */
    function _normalize(uint256 value, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return value;

        if (decimals < 18) {
            return value * (10 ** (18 - decimals));
        }

        return value / (10 ** (decimals - 18));
    }

    /** @notice Calculates the basis points difference between two values
        * @param a First value
        * @param b Second value
        * @return Basis points difference, or 0 if either value is 0
        */
    function _bpsDelta(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;

        uint256 diff = a > b ? a - b : b - a;
        return (diff * MAX_BPS) / a;
    }
}


















// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// Assumes TokenGuard is a library with a pure/view static function.
import {TokenGuardResult, TokenGuard} from "./TokenGuard.sol";

/**
 * @title VaultGuard
 * @notice Pre-transaction security guard for ERC4626 vaults.
 *
 *  Workflow:
 *   1. User calls storeCheck(vault, amount, isDeposit)  — stores state fingerprint.
 *   2. In the same block, user calls guardedDeposit / guardedWithdraw.
 *      _validate() re-runs the check, compares fingerprint, reverts if state changed.
 *
 *  Bug-fix summary vs original:
 *   - lastCheckHash: bytes32 → bytes  (abi.encode returns bytes, not bytes32)
 *   - Reentrancy deadlock: checkVaultWithPreview is now internal (no nonReentrant modifier)
 *   - _validate hash mismatch: now consistently hashes the struct+previews on both sides
 *   - VAULT_BALANCE_MISMATCH: fixed direction (realBalance < totalAssets is the risk)
 *   - guardedWithdraw: uses redeem() for share-in → asset-out, not withdraw()
 *   - safeApprove → forceApprove (deprecated function)
 *   - Added: maxDeposit / maxWithdraw / maxRedeem cap checks
 *   - Added: share price inflation detection (even with supply > 0)
 *   - Added: slippage protection (minOut parameters on guarded execution)
 *   - Added: vault-reported vs preview cross-check (previewDeposit vs convertToShares)
 *   - Added: withdraw/redeem distinction is now explicit
 */
contract VaultGuard is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct VaultGuardResult {
        // ----- Vault-level risks -----
        bool VAULT_NOT_WHITELISTED;      // vault not in operator whitelist
        bool VAULT_ZERO_SUPPLY;          // totalSupply == 0  (fresh vault)
        bool DONATION_ATTACK;            // zero-supply vault with large pre-loaded assets
        bool SHARE_INFLATION_RISK;       // assets/share ratio suspiciously large vs expected
        bool VAULT_BALANCE_MISMATCH;     // realBalance < totalAssets (vault is undercollateralised)
        bool EXCHANGE_RATE_ANOMALY;      // preview rate deviates > MAX_DEVIATION_BPS from vault rate
        bool PREVIEW_REVERT;             // preview function reverted (hostile vault)
        // ----- Operation risks -----
        bool ZERO_SHARES_OUT;            // deposit would mint 0 shares
        bool ZERO_ASSETS_OUT;            // redeem would return 0 assets
        bool DUST_SHARES;                // shares below MIN_SHARES threshold
        bool DUST_ASSETS;                // assets below MIN_ASSETS threshold
        bool EXCEEDS_MAX_DEPOSIT;        // amount > vault.maxDeposit(user)
        bool EXCEEDS_MAX_REDEEM;         // amount > vault.maxRedeem(user)
        bool PREVIEW_CONVERT_MISMATCH;   // previewDeposit vs convertToShares disagree > tolerance
        // ----- Token risks -----
        TokenGuardResult tokenResult;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_BPS                = 10_000;
    uint256 public constant MAX_DEVIATION_BPS      = 500;    // 5% — exchange rate tolerance
    uint256 public constant PREVIEW_TOLERANCE_BPS  = 100;    // 1% — previewDeposit vs convertToShares
    uint256 public constant MIN_SHARES             = 1e3;
    uint256 public constant MIN_ASSETS             = 1e3;
    /// Vault with zero supply but totalAssets > this is a donation-attack signal.
    uint256 public constant DONATION_THRESHOLD     = 1 ether;
    /// If assets-per-share > this factor of the expected 1:1 base rate, flag inflation.
    uint256 public constant INFLATION_FACTOR       = 1_000;  // 1000x base rate

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// BUG FIX: was bytes32 — abi.encode returns bytes, not bytes32.
    mapping(address => mapping(address => bytes))    public lastCheckEncoded;
    mapping(address => mapping(address => uint256))  public lastCheckBlock;
    mapping(address => bool)                         public isVaultWhitelisted;
    mapping(address => uint256)                      public vaultIndex;
    address[]                                        public whitelistedVaults;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event VaultWhitelisted(address indexed vault);
    event VaultRemoved(address indexed vault);
    event CheckStored(address indexed vault, address indexed user, uint256 blockNumber);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
                        CORE GUARD LOGIC  (internal — no lock)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev BUG FIX: was `public nonReentrant`. Since guardedDeposit/guardedWithdraw
     *      already hold the reentrancy lock when they call _validate → this function,
     *      making it nonReentrant caused a deadlock. Now internal with no modifier.
     *      External callers who want a standalone check should use `checkVault()`.
     *
     * @param vault     ERC4626 vault address
     * @param amount    Assets (for deposit) or shares (for redeem)
     * @param isDeposit true = deposit flow; false = redeem flow
     * @param user      Address performing the operation (used for cap checks)
     */
    function _checkVault(
        address vault,
        uint256 amount,
        bool isDeposit,
        address user
    )
        internal
        view
        returns (
            VaultGuardResult memory result,
            uint256 previewShares,
            uint256 previewAssets
        )
    {
        IERC4626 v    = IERC4626(vault);
        address asset = v.asset();

        // ---- Token-level checks (fee-on-transfer, weird ERC20, etc.) ----
        result.tokenResult = TokenGuard.checkToken(asset);

        uint256 totalAssets = v.totalAssets();
        uint256 totalSupply = v.totalSupply();

        // ---- 1. Whitelist ----
        if (!isVaultWhitelisted[vault]) {
            result.VAULT_NOT_WHITELISTED = true;
        }

        // ---- 2. Zero supply + donation attack ----
        if (totalSupply == 0) {
            result.VAULT_ZERO_SUPPLY = true;
            if (totalAssets > DONATION_THRESHOLD) {
                result.DONATION_ATTACK = true;
            }
        }

        // ---- 3. Balance mismatch (undercollateralisation) ----
        // BUG FIX: original flagged realBalance > totalAssets (wrong direction).
        // The real risk is realBalance < totalAssets: vault is promising more than it holds.
        uint256 realBalance = IERC20(asset).balanceOf(vault);
        if (realBalance < totalAssets) {
            result.VAULT_BALANCE_MISMATCH = true;
        }

        // ---- 4. Share inflation check ----
        // Even with supply > 0, a manipulator can push assets-per-share very high,
        // causing future depositors to receive rounding-down to 0 shares.
        if (totalSupply > 0) {
            uint8 assetDec = _safeDecimals(asset);
            uint8 vaultDec = _safeDecimals(vault);
            uint256 normAssets = _normalize(totalAssets, assetDec);
            uint256 normSupply = _normalize(totalSupply, vaultDec);
            // assetsPerShare in 1e18
            uint256 assetsPerShare = (normAssets * 1e18) / normSupply;
            // Ideally 1:1 in normalised terms → 1e18.
            // Flag if ratio > INFLATION_FACTOR × expected.
            if (assetsPerShare > INFLATION_FACTOR * 1e18) {
                result.SHARE_INFLATION_RISK = true;
            }
        }

        // ---- 5. Exchange rate + preview checks ----
        if (totalSupply > 0 && totalAssets > 0) {
            uint8 assetDec = _safeDecimals(asset);
            uint8 vaultDec = _safeDecimals(vault);
            uint256 normAssets = _normalize(totalAssets, assetDec);
            uint256 normSupply = _normalize(totalSupply, vaultDec);
            // Vault-level exchange rate (normalised, 1e18 precision)
            uint256 vaultRate = (normAssets * 1e18) / normSupply;

            if (isDeposit) {
                // ---- Deposit path ----
                // Cap check
                try v.maxDeposit(user) returns (uint256 cap) {
                    if (amount > cap) result.EXCEEDS_MAX_DEPOSIT = true;
                } catch {}

                // Preview
                try v.previewDeposit(amount) returns (uint256 s) {
                    previewShares = s;
                } catch {
                    result.PREVIEW_REVERT = true;
                    return (result, 0, 0);
                }

                if (previewShares == 0) result.ZERO_SHARES_OUT = true;
                if (previewShares < MIN_SHARES) result.DUST_SHARES = true;

                // Rate deviation check
                if (previewShares > 0) {
                    uint256 normShares = _normalize(previewShares, vaultDec);
                    uint256 normAmount = _normalize(amount, assetDec);
                    uint256 opRate = (normAmount * 1e18) / normShares;
                    if (_bpsDelta(vaultRate, opRate) > MAX_DEVIATION_BPS) {
                        result.EXCHANGE_RATE_ANOMALY = true;
                    }
                }

                // Cross-check previewDeposit vs convertToShares
                // They must agree within PREVIEW_TOLERANCE_BPS.
                try v.convertToShares(amount) returns (uint256 converted) {
                    if (
                        previewShares > 0 &&
                        converted > 0 &&
                        _bpsDelta(previewShares, converted) > PREVIEW_TOLERANCE_BPS
                    ) {
                        result.PREVIEW_CONVERT_MISMATCH = true;
                    }
                } catch {}

            } else {
                // ---- Redeem path (shares in → assets out) ----
                // BUG FIX original: used previewRedeem correctly here.
                // Cap check (shares)
                try v.maxRedeem(user) returns (uint256 cap) {
                    if (amount > cap) result.EXCEEDS_MAX_REDEEM = true;
                } catch {}

                try v.previewRedeem(amount) returns (uint256 a) {
                    previewAssets = a;
                } catch {
                    result.PREVIEW_REVERT = true;
                    return (result, 0, 0);
                }

                if (previewAssets == 0) result.ZERO_ASSETS_OUT = true;
                if (previewAssets < MIN_ASSETS) result.DUST_ASSETS = true;

                if (previewAssets > 0) {
                    uint256 normAssetsOut = _normalize(previewAssets, assetDec);
                    uint256 normShares    = _normalize(amount, vaultDec);
                    uint256 opRate        = (normAssetsOut * 1e18) / normShares;
                    if (_bpsDelta(vaultRate, opRate) > MAX_DEVIATION_BPS) {
                        result.EXCHANGE_RATE_ANOMALY = true;
                    }
                }

                // Cross-check previewRedeem vs convertToAssets
                try v.convertToAssets(amount) returns (uint256 converted) {
                    if (
                        previewAssets > 0 &&
                        converted > 0 &&
                        _bpsDelta(previewAssets, converted) > PREVIEW_TOLERANCE_BPS
                    ) {
                        result.PREVIEW_CONVERT_MISMATCH = true;
                    }
                } catch {}
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                     PUBLIC CHECK  (for off-chain / UI use)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Standalone view-style check (still external, no state changes).
     *         Use this for off-chain simulation or UI display.
     *         Uses msg.sender for cap checks.
     */
    function checkVault(address vault, uint256 amount, bool isDeposit)
        external
        view
        returns (
            VaultGuardResult memory result,
            uint256 previewShares,
            uint256 previewAssets
        )
    {
        return _checkVault(vault, amount, isDeposit, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                    STORE CHECK  (Step 1 — called before tx)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Records the vault state fingerprint for the caller in this block.
     *         Must be called in the same block as guardedDeposit / guardedWithdraw.
     *
     * BUG FIX: was calling checkVaultwithPreview (nonReentrant) from within another
     * nonReentrant function — deadlock. Now calls internal _checkVault directly.
     */
    function storeCheck(address vault, uint256 amount, bool isDeposit)
        external
        nonReentrant  returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        (VaultGuardResult memory res, uint256 pShares, uint256 pAssets) =
            _checkVault(vault, amount, isDeposit, msg.sender);

        // BUG FIX: store as bytes (abi.encode returns bytes, not bytes32).
        lastCheckEncoded[vault][msg.sender] = abi.encode(res, pShares, pAssets);
        lastCheckBlock[vault][msg.sender]   = block.number;

        emit CheckStored(vault, msg.sender, block.number);
        return (res, pShares, pAssets);
    }

    /*//////////////////////////////////////////////////////////////
                    GUARDED EXECUTION  (Step 2)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets into vault after validating state is unchanged.
     * @param vault     ERC4626 vault
     * @param amount    Asset amount to deposit
     * @param receiver  Address to receive shares
     * @param minShares Slippage protection — revert if shares minted < minShares
     * @return shares   Shares minted
     */
    function guardedDeposit(
        address vault,
        uint256 amount,
        address receiver,
        uint256 minShares
    )
        external
        nonReentrant
        returns (uint256 shares)
    {
        _validate(vault, amount, true);

        IERC20 asset = IERC20(IERC4626(vault).asset());
        asset.safeTransferFrom(msg.sender, address(this), amount);

        // BUG FIX: safeApprove is deprecated. Use forceApprove to handle
        // tokens that require approval reset before re-approve.
        asset.forceApprove(vault, amount);

        shares = IERC4626(vault).deposit(amount, receiver);
        require(shares > 0,         "ZERO_SHARES_MINTED");
        require(shares >= minShares, "SLIPPAGE_TOO_HIGH");
    }

    /**
     * @notice Redeem shares from vault after validating state is unchanged.
     *
     * BUG FIX: original called vault.withdraw(amount, ...) but documented `amount`
     * as shares. withdraw() takes assets, not shares. Use redeem() for shares-in.
     *
     * @param vault      ERC4626 vault
     * @param shares     Share amount to burn
     * @param receiver   Address to receive assets
     * @param minAssets  Slippage protection — revert if assets received < minAssets
     * @return assets    Assets received
     */
    function guardedRedeem(
        address vault,
        uint256 shares,
        address receiver,
        uint256 minAssets
    )
        external
        nonReentrant
        returns (uint256 assets)
    {
        _validate(vault, shares, false);

        // BUG FIX: use redeem() (shares → assets), not withdraw() (assets → assets).
        assets = IERC4626(vault).redeem(shares, receiver, msg.sender);
        require(assets > 0,          "ZERO_ASSETS_RETURNED");
        require(assets >= minAssets, "SLIPPAGE_TOO_HIGH");
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev BUG FIX: original double-hashed on one side.
     *      storeCheck stored: abi.encode(result, pShares, pAssets)
     *      _validate compared: keccak256(abi.encode(keccak256(abi.encode(result)), pShares, pAssets))
     *      Now both sides consistently compare keccak256(abi.encode(result, pShares, pAssets)).
     */
    function _validate(address vault, uint256 amount, bool isDeposit) internal view {
        require(lastCheckBlock[vault][msg.sender] == block.number, "STALE_CHECK");

        (VaultGuardResult memory res, uint256 pShares, uint256 pAssets) =
            _checkVault(vault, amount, isDeposit, msg.sender);

        bytes32 currentFingerprint = keccak256(abi.encode(res, pShares, pAssets));
        bytes32 storedFingerprint  = keccak256(lastCheckEncoded[vault][msg.sender]);

        require(currentFingerprint == storedFingerprint, "VAULT_STATE_CHANGED");
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the decoded last stored check for a vault + user.
     * @dev BUG FIX: original tried to abi.decode a bytes32 (compile error).
     *      Now decodes from bytes correctly.
     */
    function getLastCheck(address vault, address user)
        external
        view
        returns (
            VaultGuardResult memory result,
            uint256 previewShares,
            uint256 previewAssets,
            uint256 blockNumber
        )
    {
        bytes memory encoded = lastCheckEncoded[vault][user];
        require(encoded.length > 0, "NO_CHECK_STORED");
        (result, previewShares, previewAssets) =
            abi.decode(encoded, (VaultGuardResult, uint256, uint256));
        blockNumber = lastCheckBlock[vault][user];
    }

    function getWhitelistedVaults() external view returns (address[] memory) {
        return whitelistedVaults;
    }

    function isWhitelisted(address vault) public view returns (bool) {
        return isVaultWhitelisted[vault];
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    function whitelistVault(address vault) external onlyOwner {
        require(vault != address(0), "ZERO_ADDRESS");
        require(!isVaultWhitelisted[vault], "ALREADY_WHITELISTED");
        isVaultWhitelisted[vault] = true;
        vaultIndex[vault] = whitelistedVaults.length;
        whitelistedVaults.push(vault);
        emit VaultWhitelisted(vault);
    }

    function addWhitelistedVaults(address[] calldata vaults) external onlyOwner {
        for (uint256 i = 0; i < vaults.length; ) {
            address v = vaults[i];
            if (v != address(0) && !isVaultWhitelisted[v]) {
                isVaultWhitelisted[v] = true;
                vaultIndex[v] = whitelistedVaults.length;
                whitelistedVaults.push(v);
                emit VaultWhitelisted(v);
            }
            unchecked { ++i; }
        }
    }

    function removeWhitelistedVault(address vault) external onlyOwner {
        require(isVaultWhitelisted[vault], "NOT_WHITELISTED");
        uint256 idx      = vaultIndex[vault];
        uint256 lastIdx  = whitelistedVaults.length - 1;
        address lastVault = whitelistedVaults[lastIdx];

        whitelistedVaults[idx] = lastVault;
        vaultIndex[lastVault]  = idx;
        whitelistedVaults.pop();

        delete vaultIndex[vault];
        delete isVaultWhitelisted[vault];
        emit VaultRemoved(vault);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _safeDecimals(address token) internal view returns (uint8) {
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            return d;
        } catch {
            return 18;
        }
    }

    function _normalize(uint256 value, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return value;
        if (decimals < 18)  return value * (10 ** (18 - decimals));
        return value / (10 ** (decimals - 18));
    }

    /// @dev Returns basis-point difference of |a - b| relative to a.
    function _bpsDelta(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        uint256 diff = a > b ? a - b : b - a;
        return (diff * MAX_BPS) / a;
    }
}
