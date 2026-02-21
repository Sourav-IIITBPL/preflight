// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
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
    function checkVaultwithPreview(
        address vault,
        uint256 amount,
        bool isDeposit
    ) public nonReentrant returns (VaultGuardResult memory result,uint256 previewShares,uint256 previewAssets) {

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
   function storeCheckAndPreviewResult(
     address vault,
        uint256 amount,
        bool isDeposit
    ) external nonReentrant {

        (VaultGuardResult memory currentResult,uint256 previewShares,uint256 previewAssets) = checkVaultwithPreview(vault, amount, isDeposit);
       
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
function guardedDeposit(
    address vault,
    uint256 amount,
    address receiver
) external nonReentrant returns (uint256 shares) {

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

function guardedWithdraw(
    address vault,
    uint256 amount,
    address receiver
) external nonReentrant returns (uint256 assets) {

    _validate(vault, amount, false);

    assets = IERC4626(vault).withdraw(amount,receiver,msg.sender);
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

    function getLastCheck(
        address vault,
        address user
    ) external view returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNumber) {
        (result, previewShares, previewAssets) = abi.decode(lastCheckHash[vault][user], (VaultGuardResult, uint256, uint256));
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

/** @notice Adds a vault to the whitelist
    * @param vault Address of the vault to whitelist
    */

function whitelistVault(address vault) external onlyOwner {
    require(vault != address(0), "Zero_address");
    require(!isVaultWhitelisted[vault], "Already_whitelisted");

    isVaultWhitelisted[vault] = true;
    vaultIndex[vault] = whitelistedVaults.length;
    whitelistedVaults.push(vault);
}


/** @notice Removes a vault from the whitelist
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

/** @notice Adds multiple vaults to the whitelist
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

/* @notice Validates that the vault state hasn't changed since the last check
    * @param vault Address of the ERC4626 vault
    * @param amount Amount of assets/shares involved
    * @param isDeposit True for deposit, false for withdraw
    * @dev Compares the current check result with the stored result to prevent front-running
    */

    function _validate(
        address vault,
        uint256 amount,
        bool isDeposit
    ) internal view {

        require(block.number == lastCheckBlock[vault][msg.sender], "STALE_CHECK");

        (VaultGuardResult memory result,uint256 previewShares,uint256 previewAssets) = checkVaultwithPreview(vault, amount, isDeposit);
        
        bytes32 currentResult = keccak256(abi.encode(result));
        require(
            keccak256(abi.encode(currentResult, previewShares, previewAssets)) == lastCheckHash[vault][msg.sender],
            "STATE_CHANGED"
        );
    }

/* @notice Safely retrieves the decimals of a token, defaults to 18 if the call fails
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

/* @notice Normalizes a token amount to 18 decimals for consistent calculations
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

/* @notice Calculates the basis points difference between two values
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
