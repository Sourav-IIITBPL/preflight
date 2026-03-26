// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ITokenGuard, TokenGuardResult} from "./interfaces/ITokenGuard.sol";

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
contract ERC4626VaultGuard is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

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
    mapping(address => mapping(address => bytes)) public lastCheckEncoded;
    mapping(address => mapping(address => uint256)) public lastCheckBlock;
    mapping(address => bool) public isVaultWhitelisted;
    mapping(address => uint256) public vaultIndex;
    mapping(address => bool) public authorizedRouters;
    address[] public whitelistedVaults;

    event VaultCheckPerformed(address indexed vault, address indexed user);
    event VaultWhitelisted(address indexed vault);
    event VaultRemoved(address indexed vault);
    event CheckStored(address indexed vault, address indexed user, uint256 blockNumber);
    event RouterAuthorized(address indexed router, bool authorized);

    modifier onlyAuthorizedRouter() {
        require(authorizedRouters[msg.sender], "NOT_AUTHORIZED_ROUTER");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _tokenGuard) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        tokenGuard = ITokenGuard(_tokenGuard);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // OWNER-ONLY FUNCTIONS

    function whitelistVault(address vault) external onlyOwner {
        require(vault != address(0), "ZERO_ADDRESS");
        require(!isVaultWhitelisted[vault], "ALREADY_WHITELISTED");
        isVaultWhitelisted[vault] = true;
        vaultIndex[vault] = whitelistedVaults.length;
        whitelistedVaults.push(vault);
        emit VaultWhitelisted(vault);
    }

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

    function setAuthorizedRouter(address router, bool authorized) external onlyOwner {
        require(router != address(0), "ZERO_ADDRESS");
        authorizedRouters[router] = authorized;
        emit RouterAuthorized(router, authorized);
    }

    //  EXTERNAL VIEW FUNCTIONS  //

    /**
     * @notice Returns the decoded last stored check for a vault + user.
     */
    function getLastCheck(address vault, address user)
        external
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNumber)
    {
        bytes memory encoded = lastCheckEncoded[vault][user];
        require(encoded.length > 0, "NO_CHECK_STORED");
        (uint48 packedResult, uint256 shares, uint256 assets) = abi.decode(encoded, (uint48, uint256, uint256));
        result = _unpacked(packedResult);
        previewShares = shares;
        previewAssets = assets;
        blockNumber = lastCheckBlock[vault][user];
    }

    function getWhitelistedVaults() external view returns (address[] memory) {
        return whitelistedVaults;
    }

    function isWhitelisted(address vault) public view returns (bool) {
        return isVaultWhitelisted[vault];
    }

    /**
     * @notice Standalone view-style check . Uses msg.sender for cap checks.
     */
    function checkVault(address vault, uint256 amount, bool isDeposit)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        emit VaultCheckPerformed(vault, msg.sender);
        return _checkVault(vault, amount, isDeposit, msg.sender);
    }

    // EXTERNAL FUNCTIONS (STATE-CHANGING) //
    /**
     * @notice Records the vault state fingerprint for the caller in this block.
     *         Must be called in the same block as guardedDeposit / guardedWithdraw.
     *
     */
    function storeCheck(address vault, address user, uint256 amount, bool isDeposit)
        external
        nonReentrant
        onlyAuthorizedRouter
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        (VaultGuardResult memory guardResult, uint256 pShares, uint256 pAssets) =
            _checkVault(vault, amount, isDeposit, user);

        lastCheckEncoded[vault][user] = abi.encode(_packed(guardResult), pShares, pAssets);
        lastCheckBlock[vault][user] = block.number;

        emit CheckStored(vault, user, block.number);
        return (result, pShares, pAssets);
    }

    function validate(address vault, address user, uint256 amount, bool isDeposit) external view {
        _validate(vault, user, amount, isDeposit);
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Core check function that performs all validations and returns a comprehensive result struct.
     * @dev This is called by both the external checkVault (for off-chain use) and the internal storeCheck (before encoding).
     * @param ERC4626vault     ERC4626 vault address
     * @param amount    Assets (for deposit) or shares (for redeem)
     * @param isDeposit true = deposit flow; false = redeem flow
     * @param user      Address performing the operation (used for cap checks)
     */
    function _checkVault(address ERC4626vault, uint256 amount, bool isDeposit, address user)
        internal
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
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

        if (totalSupply > 0 && totalAssets > 0) {
            uint8 assetDec = _safeDecimals(asset);
            uint8 vaultDec = _safeDecimals(ERC4626vault);
            uint256 normAssets = _normalize(totalAssets, assetDec);
            uint256 normSupply = _normalize(totalSupply, vaultDec);
            // Vault-level exchange rate (normalised, 1e18 precision)
            uint256 vaultRate = (normAssets * 1e18) / normSupply;

            if (isDeposit) {
                try vault.maxDeposit(user) returns (uint256 cap) {
                    if (amount > cap) result.EXCEEDS_MAX_DEPOSIT = true;
                } catch {}

                try vault.previewDeposit(amount) returns (uint256 s) {
                    previewShares = s;
                } catch {
                    result.PREVIEW_REVERT = true;
                    return (result, 0, 0);
                }

                if (previewShares == 0) result.ZERO_SHARES_OUT = true;
                if (previewShares < MIN_SHARES) result.DUST_SHARES = true;

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
                try vault.convertToShares(amount) returns (uint256 converted) {
                    if (
                        previewShares > 0 && converted > 0
                            && _bpsDelta(previewShares, converted) > PREVIEW_TOLERANCE_BPS
                    ) {
                        result.PREVIEW_CONVERT_MISMATCH = true;
                    }
                } catch {}
            } else {
                try vault.maxRedeem(user) returns (uint256 cap) {
                    if (amount > cap) result.EXCEEDS_MAX_REDEEM = true;
                } catch {}

                try vault.previewRedeem(amount) returns (uint256 a) {
                    previewAssets = a;
                } catch {
                    result.PREVIEW_REVERT = true;
                    return (result, 0, 0);
                }

                if (previewAssets == 0) result.ZERO_ASSETS_OUT = true;
                if (previewAssets < MIN_ASSETS) result.DUST_ASSETS = true;

                if (previewAssets > 0) {
                    uint256 normAssetsOut = _normalize(previewAssets, assetDec);
                    uint256 normShares = _normalize(amount, vaultDec);
                    uint256 opRate = (normAssetsOut * 1e18) / normShares;
                    if (_bpsDelta(vaultRate, opRate) > MAX_DEVIATION_BPS) {
                        result.EXCHANGE_RATE_ANOMALY = true;
                    }
                }

                // Cross-check previewRedeem vs convertToAssets
                try vault.convertToAssets(amount) returns (uint256 converted) {
                    if (
                        previewAssets > 0 && converted > 0
                            && _bpsDelta(previewAssets, converted) > PREVIEW_TOLERANCE_BPS
                    ) {
                        result.PREVIEW_CONVERT_MISMATCH = true;
                    }
                } catch {}
            }
        }
    }

    function _validate(address vault, address user, uint256 amount, bool isDeposit) internal view {
        require(lastCheckBlock[vault][user] == block.number, "STALE_CHECK");

        (VaultGuardResult memory result, uint256 pShares, uint256 pAssets) = _checkVault(vault, amount, isDeposit, user);

        bytes32 currentFingerprint = keccak256(abi.encode(_packed(result), pShares, pAssets));
        bytes32 storedFingerprint = keccak256(lastCheckEncoded[vault][user]);

        require(currentFingerprint == storedFingerprint, "VAULT_STATE_CHANGED");
    }

    // INTERNAL HELPER FUNCTIONS

    function _packed(VaultGuardResult memory vaultReport) internal pure returns (uint48 result) {
        if (vaultReport.VAULT_NOT_WHITELISTED) result |= uint48(1) << 0;
        if (vaultReport.VAULT_ZERO_SUPPLY) result |= uint48(1) << 1;
        if (vaultReport.DONATION_ATTACK) result |= uint48(1) << 2;
        if (vaultReport.SHARE_INFLATION_RISK) result |= uint48(1) << 3;
        if (vaultReport.VAULT_BALANCE_MISMATCH) result |= uint48(1) << 4;
        if (vaultReport.EXCHANGE_RATE_ANOMALY) result |= uint48(1) << 5;
        if (vaultReport.PREVIEW_REVERT) result |= uint48(1) << 6;
        if (vaultReport.ZERO_SHARES_OUT) result |= uint48(1) << 7;
        if (vaultReport.ZERO_ASSETS_OUT) result |= uint48(1) << 8;
        if (vaultReport.DUST_SHARES) result |= uint48(1) << 9;
        if (vaultReport.DUST_ASSETS) result |= uint48(1) << 10;
        if (vaultReport.EXCEEDS_MAX_DEPOSIT) result |= uint48(1) << 11;
        if (vaultReport.EXCEEDS_MAX_REDEEM) result |= uint48(1) << 12;
        if (vaultReport.PREVIEW_CONVERT_MISMATCH) result |= uint48(1) << 13;

        TokenGuardResult memory tokenReport = vaultReport.tokenResult;

        if (tokenReport.NOT_A_CONTRACT) result |= uint48(1) << 14;
        if (tokenReport.EMPTY_BYTECODE) result |= uint48(1) << 15;
        if (tokenReport.DECIMALS_REVERT) result |= uint48(1) << 16;
        if (tokenReport.WEIRD_DECIMALS) result |= uint48(1) << 17;
        if (tokenReport.HIGH_DECIMALS) result |= uint48(1) << 18;
        if (tokenReport.TOTAL_SUPPLY_REVERT) result |= uint48(1) << 19;
        if (tokenReport.ZERO_TOTAL_SUPPLY) result |= uint48(1) << 20;
        if (tokenReport.VERY_LOW_TOTAL_SUPPLY) result |= uint48(1) << 21;
        if (tokenReport.SYMBOL_REVERT) result |= uint48(1) << 22;
        if (tokenReport.NAME_REVERT) result |= uint48(1) << 23;
        if (tokenReport.IS_EIP1967_PROXY) result |= uint48(1) << 24;
        if (tokenReport.IS_EIP1822_PROXY) result |= uint48(1) << 25;
        if (tokenReport.IS_MINIMAL_PROXY) result |= uint48(1) << 26;
        if (tokenReport.HAS_OWNER) result |= uint48(1) << 27;
        if (tokenReport.OWNERSHIP_RENOUNCED) result |= uint48(1) << 28;
        if (tokenReport.OWNER_IS_EOA) result |= uint48(1) << 29;
        if (tokenReport.IS_PAUSABLE) result |= uint48(1) << 30;
        if (tokenReport.IS_CURRENTLY_PAUSED) result |= uint48(1) << 31;
        if (tokenReport.HAS_BLACKLIST) result |= uint48(1) << 32;
        if (tokenReport.HAS_BLOCKLIST) result |= uint48(1) << 33;
        if (tokenReport.POSSIBLE_FEE_ON_TRANSFER) result |= uint48(1) << 34;
        if (tokenReport.HAS_TRANSFER_FEE_GETTER) result |= uint48(1) << 35;
        if (tokenReport.HAS_TAX_FUNCTION) result |= uint48(1) << 36;
        if (tokenReport.POSSIBLE_REBASING) result |= uint48(1) << 37;
        if (tokenReport.HAS_MINT_CAPABILITY) result |= uint48(1) << 38;
        if (tokenReport.HAS_BURN_CAPABILITY) result |= uint48(1) << 39;
        if (tokenReport.HAS_PERMIT) result |= uint48(1) << 40;
        if (tokenReport.HAS_FLASH_MINT) result |= uint48(1) << 41;

        return result;
    }

    function _unpacked(uint48 packed) internal pure returns (VaultGuardResult memory result) {
        result.VAULT_NOT_WHITELISTED = (packed >> 0) & 1 == 1;
        result.VAULT_ZERO_SUPPLY = (packed >> 1) & 1 == 1;
        result.DONATION_ATTACK = (packed >> 2) & 1 == 1;
        result.SHARE_INFLATION_RISK = (packed >> 3) & 1 == 1;
        result.VAULT_BALANCE_MISMATCH = (packed >> 4) & 1 == 1;
        result.EXCHANGE_RATE_ANOMALY = (packed >> 5) & 1 == 1;
        result.PREVIEW_REVERT = (packed >> 6) & 1 == 1;
        result.ZERO_SHARES_OUT = (packed >> 7) & 1 == 1;
        result.ZERO_ASSETS_OUT = (packed >> 8) & 1 == 1;
        result.DUST_SHARES = (packed >> 9) & 1 == 1;
        result.DUST_ASSETS = (packed >> 10) & 1 == 1;
        result.EXCEEDS_MAX_DEPOSIT = (packed >> 11) & 1 == 1;
        result.EXCEEDS_MAX_REDEEM = (packed >> 12) & 1 == 1;
        result.PREVIEW_CONVERT_MISMATCH = (packed >> 13) & 1 == 1;

        TokenGuardResult memory _tokenReport;

        _tokenReport.NOT_A_CONTRACT = (packed >> 14) & 1 == 1;
        _tokenReport.EMPTY_BYTECODE = (packed >> 15) & 1 == 1;
        _tokenReport.DECIMALS_REVERT = (packed >> 16) & 1 == 1;
        _tokenReport.WEIRD_DECIMALS = (packed >> 17) & 1 == 1;
        _tokenReport.HIGH_DECIMALS = (packed >> 18) & 1 == 1;
        _tokenReport.TOTAL_SUPPLY_REVERT = (packed >> 19) & 1 == 1;
        _tokenReport.ZERO_TOTAL_SUPPLY = (packed >> 20) & 1 == 1;
        _tokenReport.VERY_LOW_TOTAL_SUPPLY = (packed >> 21) & 1 == 1;
        _tokenReport.SYMBOL_REVERT = (packed >> 22) & 1 == 1;
        _tokenReport.NAME_REVERT = (packed >> 23) & 1 == 1;
        _tokenReport.IS_EIP1967_PROXY = (packed >> 24) & 1 == 1;
        _tokenReport.IS_EIP1822_PROXY = (packed >> 25) & 1 == 1;
        _tokenReport.IS_MINIMAL_PROXY = (packed >> 26) & 1 == 1;
        _tokenReport.HAS_OWNER = (packed >> 27) & 1 == 1;
        _tokenReport.OWNERSHIP_RENOUNCED = (packed >> 28) & 1 == 1;
        _tokenReport.OWNER_IS_EOA = (packed >> 29) & 1 == 1;
        _tokenReport.IS_PAUSABLE = (packed >> 30) & 1 == 1;
        _tokenReport.IS_CURRENTLY_PAUSED = (packed >> 31) & 1 == 1;
        _tokenReport.HAS_BLACKLIST = (packed >> 32) & 1 == 1;
        _tokenReport.HAS_BLOCKLIST = (packed >> 33) & 1 == 1;
        _tokenReport.POSSIBLE_FEE_ON_TRANSFER = (packed >> 34) & 1 == 1;
        _tokenReport.HAS_TRANSFER_FEE_GETTER = (packed >> 35) & 1 == 1;
        _tokenReport.HAS_TAX_FUNCTION = (packed >> 36) & 1 == 1;
        _tokenReport.POSSIBLE_REBASING = (packed >> 37) & 1 == 1;
        _tokenReport.HAS_MINT_CAPABILITY = (packed >> 38) & 1 == 1;
        _tokenReport.HAS_BURN_CAPABILITY = (packed >> 39) & 1 == 1;
        _tokenReport.HAS_PERMIT = (packed >> 40) & 1 == 1;
        _tokenReport.HAS_FLASH_MINT = (packed >> 41) & 1 == 1;

        result.tokenResult = _tokenReport;

        return result;
    }

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
