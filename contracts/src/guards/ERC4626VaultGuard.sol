// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ITokenGuard, TokenGuardResult} from "./interfaces/ITokenGuard.sol";
import {VaultOpType} from "../types/OffChainTypes.sol";
import {VaultGuardLib} from "./lib/VaultGuardLib.sol";

/// @notice Vault-specific on-chain findings emitted by the guard.
struct VaultGuardResult {
    // ----- Vault-level risks -----
    bool VAULT_NOT_WHITELISTED; // vault not in operator whitelist
    bool VAULT_ZERO_SUPPLY; // totalSupply == 0  (fresh vault)
    bool DONATION_ATTACK; // zero-supply vault with large pre-loaded assets
    bool SHARE_INFLATION_RISK; // assets/share ratio suspiciously large vs expected
    bool VAULT_BALANCE_MISMATCH; // realBalance < totalAssets (vault is undercollateralised)
    bool EXCHANGE_RATE_ANOMALY; // preview rate deviates > MAX_DEVIATION_BPS from vault rate
    bool PREVIEW_REVERT; // preview function reverted (hostile vault)
    // ----- Operation risks -----
    bool ZERO_SHARES_OUT; // deposit would mint 0 shares
    bool ZERO_ASSETS_OUT; // redeem would return 0 assets
    bool DUST_SHARES; // shares below MIN_SHARES threshold
    bool DUST_ASSETS; // assets below MIN_ASSETS threshold
    bool EXCEEDS_MAX_DEPOSIT; // amount > vault.maxDeposit(user)
    bool EXCEEDS_MAX_REDEEM; // amount > vault.maxRedeem(user)
    bool PREVIEW_CONVERT_MISMATCH; // previewDeposit vs convertToShares disagree > tolerance
    // ----- Token risks -----
    TokenGuardResult tokenResult;
}

/// @notice Fingerprint and preview data stored for same-block validation.
struct StoredUserCheck {
    uint48 packedResult;
    uint256 previewShares;
    uint256 previewAssets;
}

/**
 * @title  ERC4626VaultGuard
 * @author Sourav-IITBPL
 * @notice Pre-transaction security guard for ERC-4626 vaults.
 *         Supports all four ERC-4626 operations: deposit, mint, withdraw, redeem.
 *  Checks performed:
 *   - Vault-level: whitelist, zero supply, donation attack, balance mismatch, share inflation
 *   - Operation-level: zero shares/assets out, dust shares/assets, cap checks, exchange rate anomaly, preview vs convert mismatch
 *   - Token-level: all TokenGuard checks on the vault's asset
 *
 */

contract ERC4626VaultGuard is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // CONSTANTS //

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_DEVIATION_BPS = 500; // 5% — exchange rate tolerance
    uint256 public constant PREVIEW_TOLERANCE_BPS = 100; // 1% — previewDeposit vs convertToShares
    uint256 public constant MIN_SHARES = 1e3;
    uint256 public constant MIN_ASSETS = 1e3;
    /// Vault with zero supply but totalAssets > this is a donation-attack signal.
    uint256 public constant DONATION_THRESHOLD = 1 ether;
    /// If assets-per-share > this factor of the expected 1:1 base rate, flag inflation.
    uint256 public constant INFLATION_FACTOR = 100; // 100x base rate

    // STORAGE VARIABLES //

    ITokenGuard public tokenGuard;
    mapping(address => mapping(address => StoredUserCheck)) public lastCheckPacked;
    mapping(address => mapping(address => uint256)) public lastCheckBlock;
    mapping(address => bool) public isVaultWhitelisted;
    mapping(address => uint256) public vaultIndex;
    mapping(address => bool) public authorizedRouters;
    address[] public whitelistedVaults;

    /// @notice Emitted when a vault check is requested for a user.
    event VaultCheckPerformed(address indexed vault, address indexed user);
    /// @notice Emitted when a vault is added to the whitelist.
    event VaultWhitelisted(address indexed vault);
    /// @notice Emitted when a vault is removed from the whitelist.
    event VaultRemoved(address indexed vault);
    /// @notice Emitted when a user's vault check is stored for same-block validation.
    event CheckStored(address indexed vault, address indexed user, uint256 blockNumber);
    /// @notice Emitted when router authorization is updated.
    event RouterAuthorized(address indexed router, bool authorized);

    /// @dev Restricts stateful validation flow to authorized router contracts.
    modifier onlyAuthorizedRouter() {
        require(authorizedRouters[msg.sender], "NOT_AUTHORIZED_ROUTER");
        _;
    }

    /**
     * @notice Initializes the  vault guard.
     * @param _tokenGuard Address of the TokenGuard contract used for asset checks.
     */
    constructor(address _tokenGuard) {
        tokenGuard = ITokenGuard(_tokenGuard);
    }

    // OWNER-ONLY FUNCTIONS

    /**
     * @notice Adds a vault to the trusted whitelist.
     * @param vault Vault address to whitelist.
     */
    function whitelistVault(address vault) external onlyOwner {
        require(vault != address(0), "ZERO_ADDRESS");
        require(!isVaultWhitelisted[vault], "ALREADY_WHITELISTED");
        isVaultWhitelisted[vault] = true;
        vaultIndex[vault] = whitelistedVaults.length;
        whitelistedVaults.push(vault);
        emit VaultWhitelisted(vault);
    }

    /**
     * @notice Adds multiple vaults to the whitelist in a single transaction.
     * @param vaults Vault addresses to whitelist.
     */
    function addWhitelistedVaults(address[] calldata vaults) external onlyOwner {
        for (uint256 i = 0; i < vaults.length;) {
            address v = vaults[i];
            if (v != address(0) && !isVaultWhitelisted[v]) {
                isVaultWhitelisted[v] = true;
                vaultIndex[v] = whitelistedVaults.length;
                whitelistedVaults.push(v);
                emit VaultWhitelisted(v);
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Removes a vault from the whitelist.
     * @param vault Vault address to remove.
     */
    function removeWhitelistedVault(address vault) external onlyOwner {
        require(isVaultWhitelisted[vault], "NOT_WHITELISTED");
        uint256 idx = vaultIndex[vault];
        uint256 lastIdx = whitelistedVaults.length - 1;
        address lastVault = whitelistedVaults[lastIdx];

        whitelistedVaults[idx] = lastVault;
        vaultIndex[lastVault] = idx;
        whitelistedVaults.pop();

        delete vaultIndex[vault];
        delete isVaultWhitelisted[vault];
        emit VaultRemoved(vault);
    }

    /**
     * @notice Grants or revokes router permission for stateful check storage and validation.
     * @param router Router address to configure.
     * @param authorized Whether the router should be authorized.
     */
    function setAuthorizedRouter(address router, bool authorized) external onlyOwner {
        require(router != address(0), "ZERO_ADDRESS");
        authorizedRouters[router] = authorized;
        emit RouterAuthorized(router, authorized);
    }

    //  EXTERNAL VIEW FUNCTIONS  //

    /**
     * @notice Returns the decoded last stored check for a vault + user.
     * @param vault Vault address whose stored check is requested.
     * @param user User address whose stored check is requested.
     * @return result Decoded stored guard result.
     * @return previewShares Stored previewed share amount.
     * @return previewAssets Stored previewed asset amount.
     * @return blockNumber Block in which the check was stored.
     */
    function getLastCheck(address vault, address user)
        external
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNumber)
    {
        StoredUserCheck memory userCheck = lastCheckPacked[vault][user];
        result = VaultGuardLib.unpacked(userCheck.packedResult);
        previewShares = userCheck.previewShares;
        previewAssets = userCheck.previewAssets;
        blockNumber = lastCheckBlock[vault][user];
    }

    /**
     * @notice Returns the full whitelist of trusted vaults.
     * @return Whitelisted vault addresses.
     */
    function getWhitelistedVaults() external view returns (address[] memory) {
        return whitelistedVaults;
    }

    /**
     * @notice Returns whether a vault is currently whitelisted.
     * @param vault Vault address to inspect.
     * @return True when the vault is whitelisted.
     */
    function isWhitelisted(address vault) public view returns (bool) {
        return isVaultWhitelisted[vault];
    }

    /**
     * @notice Runs a vault guard check using `msg.sender` for ERC-4626 cap lookups.
     * @param vault Vault address to inspect.
     * @param amount Asset or share amount to evaluate.
     * @param opType ERC-4626 operation being checked.
     * @return result Computed vault guard result.
     * @return previewShares Previewed share amount from the guard.
     * @return previewAssets Previewed asset amount from the guard.
     */
    function checkVault(address vault, uint256 amount, VaultOpType opType)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        emit VaultCheckPerformed(vault, msg.sender);
        return _checkVault(vault, amount, opType, msg.sender);
    }

    // EXTERNAL FUNCTIONS (STATE-CHANGING) //
    /**
     * @notice Records the vault state fingerprint for the caller in this block.
     *         Must be called in the same block as guardedDeposit / guardedWithdraw.
     * @param vault Vault address being checked.
     * @param user User whose check is stored.
     * @param amount Asset or share amount to evaluate.
     * @param opType ERC-4626 operation being stored.
     * @return result Guard result captured at storage time.
     * @return previewShares Previewed share amount captured at storage time.
     * @return previewAssets Previewed asset amount captured at storage time.
     */
    function storeCheck(address vault, address user, uint256 amount, VaultOpType opType)
        external
        nonReentrant
        onlyAuthorizedRouter
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        (VaultGuardResult memory guardResult, uint256 pShares, uint256 pAssets) =
            _checkVault(vault, amount, opType, user);

        lastCheckPacked[vault][user] = StoredUserCheck({
            packedResult: VaultGuardLib.packed(guardResult), previewShares: pShares, previewAssets: pAssets
        });

        lastCheckBlock[vault][user] = block.number;

        emit CheckStored(vault, user, block.number);
        return (result, pShares, pAssets);
    }

    /**
     * @notice Revalidates the latest stored check for a user and vault in the current block.
     * @param vault Vault address being validated.
     * @param user User whose check is being validated.
     * @param amount Operation amount to validate.
     * @param opType Vault operation being validated.
     */
    function validate(address vault, address user, uint256 amount, VaultOpType opType) external view {
        _validate(vault, user, amount, opType);
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Core check function that performs all validations and returns a comprehensive result struct.
     * @dev This is called by both the external checkVault (for off-chain use) and the internal storeCheck (before encoding).
     * @param ERC4626vault     ERC4626 vault address
     * @param amount    Assets (for deposit) or shares (for redeem)
     * @param opType    Type of operation (deposit, mint, redeem, withdraw)
     * @param user      Address performing the operation (used for cap checks)
     */
    function _checkVault(address ERC4626vault, uint256 amount, VaultOpType opType, address user)
        internal
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        {
            IERC4626 vault = IERC4626(ERC4626vault);
            address asset = vault.asset();

            result.tokenResult = tokenGuard.checkToken(asset);

            uint256 totalAssets = vault.totalAssets();
            uint256 totalSupply = vault.totalSupply();

            if (!isVaultWhitelisted[ERC4626vault]) {
                result.VAULT_NOT_WHITELISTED = true;
            }

            if (totalSupply == 0) {
                result.VAULT_ZERO_SUPPLY = true;
                if (totalAssets > DONATION_THRESHOLD) {
                    result.DONATION_ATTACK = true;
                }
            }

            // Balance mismatch (undercollateralisation
            // The risk is realBalance < totalAssets: vault is promising more than it holds.
            uint256 realBalance = IERC20(asset).balanceOf(ERC4626vault);
            if (realBalance < totalAssets) {
                result.VAULT_BALANCE_MISMATCH = true;
            }

            // Even with supply > 0, a manipulator can push assets-per-share very high,
            // causing future depositors to receive rounding-down to 0 shares.
            if (totalSupply > 0) {
                uint8 assetDec = _safeDecimals(asset);
                uint8 vaultDec = _safeDecimals(ERC4626vault);
                uint256 normAssets = _normalize(totalAssets, assetDec);
                uint256 normSupply = _normalize(totalSupply, vaultDec);
                // assetsPerShare in 1e18
                uint256 assetsPerShare = (normAssets * 1e18) / normSupply;
                // Ideally 1:1 in normalised terms.
                // Flag if ratio > INFLATION_FACTOR × expected.
                if (assetsPerShare > INFLATION_FACTOR * 1e18) {
                    result.SHARE_INFLATION_RISK = true;
                }
            }
        }

        {
            if (IERC4626(ERC4626vault).totalSupply() > 0 && IERC4626(ERC4626vault).totalAssets() > 0) {
                if (opType == VaultOpType.DEPOSIT) {
                    try IERC4626(ERC4626vault).maxDeposit(user) returns (uint256 cap) {
                        if (amount > cap) result.EXCEEDS_MAX_DEPOSIT = true;
                    } catch {}
                    try IERC4626(ERC4626vault).previewDeposit(amount) returns (uint256 s) {
                        previewShares = s;
                    } catch {
                        result.PREVIEW_REVERT = true;
                        return (result, 0, 0);
                    }
                    if (previewShares == 0) result.ZERO_SHARES_OUT = true;
                    if (previewShares < MIN_SHARES) result.DUST_SHARES = true;

                    if (previewShares > 0) {
                        address asset = IERC4626(ERC4626vault).asset();
                        uint8 assetDec = _safeDecimals(asset);
                        uint8 vaultDec = _safeDecimals(ERC4626vault);
                        uint256 vaultRate = (_normalize(IERC4626(ERC4626vault).totalAssets(), assetDec) * 1e18)
                            / _normalize(IERC4626(ERC4626vault).totalSupply(), vaultDec);
                        uint256 normShares = _normalize(previewShares, vaultDec);
                        uint256 opRate = (_normalize(amount, assetDec) * 1e18) / normShares;
                        if (_bpsDelta(vaultRate, opRate) > MAX_DEVIATION_BPS) {
                            result.EXCHANGE_RATE_ANOMALY = true;
                        }
                    }

                    // Cross-check previewDeposit vs convertToShares
                    // They must agree within PREVIEW_TOLERANCE_BPS.
                    try IERC4626(ERC4626vault).convertToShares(amount) returns (uint256 converted) {
                        if (
                            previewShares > 0 && converted > 0
                                && _bpsDelta(previewShares, converted) > PREVIEW_TOLERANCE_BPS
                        ) {
                            result.PREVIEW_CONVERT_MISMATCH = true;
                        }
                    } catch {}
                } else if (opType == VaultOpType.MINT) {
                    try IERC4626(ERC4626vault).maxMint(user) returns (uint256 cap) {
                        if (amount > cap) result.EXCEEDS_MAX_DEPOSIT = true;
                    } catch {}
                    try IERC4626(ERC4626vault).previewMint(amount) returns (uint256 s) {
                        previewAssets = s;
                    } catch {
                        result.PREVIEW_REVERT = true;
                        return (result, 0, 0);
                    }
                    if (previewAssets == 0) result.ZERO_ASSETS_OUT = true;
                    if (previewAssets < MIN_ASSETS) result.DUST_ASSETS = true;

                    if (previewAssets > 0) {
                        address asset = IERC4626(ERC4626vault).asset();
                        uint8 assetDec = _safeDecimals(asset);
                        uint8 vaultDec = _safeDecimals(ERC4626vault);
                        uint256 vaultRate = (_normalize(IERC4626(ERC4626vault).totalAssets(), assetDec) * 1e18)
                            / _normalize(IERC4626(ERC4626vault).totalSupply(), vaultDec);
                        uint256 normAssetOuts = _normalize(previewAssets, assetDec);
                        uint256 normShares = _normalize(amount, vaultDec);
                        uint256 opRate = (normAssetOuts * 1e18) / normShares;
                        if (_bpsDelta(vaultRate, opRate) > MAX_DEVIATION_BPS) {
                            result.EXCHANGE_RATE_ANOMALY = true;
                        }
                    }

                    // Cross-check previewMint vs convertToAssets
                    // They must agree within PREVIEW_TOLERANCE_BPS.
                    try IERC4626(ERC4626vault).convertToAssets(amount) returns (uint256 converted) {
                        if (
                            previewAssets > 0 && converted > 0
                                && _bpsDelta(previewAssets, converted) > PREVIEW_TOLERANCE_BPS
                        ) {
                            result.PREVIEW_CONVERT_MISMATCH = true;
                        }
                    } catch {}
                } else if (opType == VaultOpType.REDEEM) {
                    try IERC4626(ERC4626vault).maxRedeem(user) returns (uint256 cap) {
                        if (amount > cap) result.EXCEEDS_MAX_REDEEM = true;
                    } catch {}
                    try IERC4626(ERC4626vault).previewRedeem(amount) returns (uint256 a) {
                        previewAssets = a;
                    } catch {
                        result.PREVIEW_REVERT = true;
                        return (result, 0, 0);
                    }
                    if (previewAssets == 0) result.ZERO_ASSETS_OUT = true;
                    if (previewAssets < MIN_ASSETS) result.DUST_ASSETS = true;

                    if (previewAssets > 0) {
                        address asset = IERC4626(ERC4626vault).asset();
                        uint8 assetDec = _safeDecimals(asset);
                        uint8 vaultDec = _safeDecimals(ERC4626vault);
                        uint256 vaultRate = (_normalize(IERC4626(ERC4626vault).totalAssets(), assetDec) * 1e18)
                            / _normalize(IERC4626(ERC4626vault).totalSupply(), vaultDec);
                        uint256 normAssetsOut = _normalize(previewAssets, assetDec);
                        uint256 normShares = _normalize(amount, vaultDec);
                        uint256 opRate = (normAssetsOut * 1e18) / normShares;
                        if (_bpsDelta(vaultRate, opRate) > MAX_DEVIATION_BPS) {
                            result.EXCHANGE_RATE_ANOMALY = true;
                        }
                    }

                    // Cross-check previewRedeem vs convertToAssets
                    try IERC4626(ERC4626vault).convertToAssets(amount) returns (uint256 converted) {
                        if (
                            previewAssets > 0 && converted > 0
                                && _bpsDelta(previewAssets, converted) > PREVIEW_TOLERANCE_BPS
                        ) {
                            result.PREVIEW_CONVERT_MISMATCH = true;
                        }
                    } catch {}
                } else if (opType == VaultOpType.WITHDRAW) {
                    try IERC4626(ERC4626vault).maxWithdraw(user) returns (uint256 cap) {
                        if (amount > cap) result.EXCEEDS_MAX_REDEEM = true;
                    } catch {}
                    try IERC4626(ERC4626vault).previewWithdraw(amount) returns (uint256 a) {
                        previewShares = a;
                    } catch {
                        result.PREVIEW_REVERT = true;
                        return (result, 0, 0);
                    }
                    if (previewShares == 0) result.ZERO_SHARES_OUT = true;
                    if (previewShares < MIN_SHARES) result.DUST_SHARES = true;

                    if (previewShares > 0) {
                        address asset = IERC4626(ERC4626vault).asset();
                        uint8 assetDec = _safeDecimals(asset);
                        uint8 vaultDec = _safeDecimals(ERC4626vault);
                        uint256 vaultRate = (_normalize(IERC4626(ERC4626vault).totalAssets(), assetDec) * 1e18)
                            / _normalize(IERC4626(ERC4626vault).totalSupply(), vaultDec);
                        uint256 normShares = _normalize(previewShares, vaultDec);
                        uint256 opRate = (_normalize(amount, assetDec) * 1e18) / normShares;
                        if (_bpsDelta(vaultRate, opRate) > MAX_DEVIATION_BPS) {
                            result.EXCHANGE_RATE_ANOMALY = true;
                        }
                    }

                    // Cross-check previewWithdraw vs convertToShares
                    try IERC4626(ERC4626vault).convertToShares(amount) returns (uint256 converted) {
                        if (
                            previewShares > 0 && converted > 0
                                && _bpsDelta(previewShares, converted) > PREVIEW_TOLERANCE_BPS
                        ) {
                            result.PREVIEW_CONVERT_MISMATCH = true;
                        }
                    } catch {}
                }
            }
        }
    }

    function _validate(address vault, address user, uint256 amount, VaultOpType opType) internal view {
        require(lastCheckBlock[vault][user] == block.number, "STALE_CHECK");

        (VaultGuardResult memory result, uint256 pShares, uint256 pAssets) = _checkVault(vault, amount, opType, user);

        StoredUserCheck memory currentCheck = StoredUserCheck({
            packedResult: VaultGuardLib.packed(result), previewShares: pShares, previewAssets: pAssets
        });
        StoredUserCheck memory storedCheck = lastCheckPacked[vault][user];

        bytes32 currentFingerprint = keccak256(abi.encode(currentCheck));
        bytes32 storedFingerprint = keccak256(abi.encode(storedCheck));

        require(currentFingerprint == storedFingerprint, "VAULT_STATE_CHANGED");
    }

    // INTERNAL HELPER FUNCTIONS

    function _safeDecimals(address token) internal view returns (uint8) {
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            return d;
        } catch {
            return 18;
        }
    }

    function _normalize(uint256 value, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return value;
        if (decimals < 18) return value * (10 ** (18 - decimals));
        return value / (10 ** (decimals - 18));
    }

    /// @dev Returns basis-point difference of |a - b| relative to a.
    function _bpsDelta(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        uint256 diff = a > b ? a - b : b - a;
        return (diff * MAX_BPS) / a;
    }
}
