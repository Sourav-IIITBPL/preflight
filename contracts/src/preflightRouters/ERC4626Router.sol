// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {IERC4626RiskPolicy, IRiskReportNFT} from "./interfaces/IRiskPolicy.sol";
import {VaultGuardResult} from "../types/OnChainTypes.sol";
import {IERC4626VaultGuard} from "./interfaces/IGuards.sol";
import {VaultOpType} from "../types/OffChainTypes.sol";
import {ERC4626DecodedRiskReport} from "../riskpolicies/ERC4626RiskPolicy.sol";

/**
 * @author Sourav-IITBPL
 * @notice Router for guarded ERC-4626 deposit and redeem flows with risk report minting.
 */
contract ERC4626Router is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidReceiver();
    error StaleStoredCheck();
    error VaultStateChanged();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error ZeroOutput();

    IERC4626VaultGuard public vaultGuard;
    IERC4626RiskPolicy public riskPolicy;
    IRiskReportNFT public riskReportNFT;

    event VaultGuardUpdated(address indexed newGuard);
    event RiskPolicyUpdated(address indexed newRiskPolicy);
    event VaultCheckStored(
        address indexed user, address indexed vault, VaultOpType operation, uint256 amount, uint256 packedRiskReport
    );
    event GuardedDepositExecuted(
        address indexed user, address indexed vault, address indexed receiver, uint256 assetsIn, uint256 sharesOut
    );
    event GuardedRedeemExecuted(
        address indexed user, address indexed vault, address indexed receiver, uint256 sharesIn, uint256 assetsOut
    );
    event GuardedMintExecuted(
        address indexed user, address indexed vault, address indexed receiver, uint256 sharesOut, uint256 assetsIn
    );
    event GuardedWithdrawExecuted(
        address indexed user, address indexed vault, address indexed receiver, uint256 assetsOut, uint256 sharesIn
    );

    /**
     * @notice Deploys the router with the guard, risk policy, and report NFT addresses.
     * @param vaultGuard_ Address of the ERC-4626 vault guard.
     * @param riskPolicy_ Address of the ERC-4626 risk policy contract.
     * @param riskReportNFT_ Address of the risk report NFT contract.
     */
    constructor(address vaultGuard_, address riskPolicy_, address riskReportNFT_) {
        if (vaultGuard_ == address(0) || riskPolicy_ == address(0)) {
            revert ZeroAddress();
        }

        vaultGuard = IERC4626VaultGuard(vaultGuard_);
        riskPolicy = IERC4626RiskPolicy(riskPolicy_);
        riskReportNFT = IRiskReportNFT(riskReportNFT_);
    }

    /**
     * @notice Updates the vault guard used by the router.
     * @param newGuard Address of the new vault guard.
     */
    function setVaultGuard(address newGuard) external onlyOwner {
        if (newGuard == address(0)) {
            revert ZeroAddress();
        }
        vaultGuard = IERC4626VaultGuard(newGuard);
        emit VaultGuardUpdated(newGuard);
    }

    /**
     * @notice Updates the risk policy used to evaluate stored checks.
     * @param newRiskPolicy Address of the new risk policy contract.
     */
    function setRiskPolicy(address newRiskPolicy) external onlyOwner {
        if (newRiskPolicy == address(0)) {
            revert ZeroAddress();
        }
        riskPolicy = IERC4626RiskPolicy(newRiskPolicy);
        emit RiskPolicyUpdated(newRiskPolicy);
    }

    /**
     * @notice Updates the NFT contract used to mint packed risk reports.
     * @param newRiskReportNFT Address of the new risk report NFT contract.
     */
    function setRiskReportNFT(address newRiskReportNFT) external onlyOwner {
        if (newRiskReportNFT == address(0)) {
            revert ZeroAddress();
        }
        riskReportNFT = IRiskReportNFT(newRiskReportNFT);
    }

    /**
     * @notice Runs a guarded preview for an ERC-4626 deposit/withdraw/redeem/mint flow.
     * @param vault Address of the target vault.
     * @param amount Amount of assets/shares to deposit/redeem.
     * @return result Guard result for the previewed operation.
     * @return previewShares Previewed share amount returned by the guard.
     * @return previewAssets Previewed assets out from the guard.
     */
    function guardedPreview(address vault, uint256 amount, VaultOpType opType)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        return vaultGuard.checkVault(vault, amount, opType);
    }

    /**
     * @notice Stores a deposit check, evaluates risk, and mints the packed report NFT.
     * @param vault Address of the target vault.
     * @param assetAmount Amount of assets to validate for deposit.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return The packed risk report.
     */
    function storeDepositCheck(address vault, uint256 assetAmount, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256)
    {
        VaultGuardResult memory result;
        uint256 previewShares;
        uint256 previewAssets;
        (result, previewShares, previewAssets) =
            vaultGuard.storeCheck(vault, msg.sender, assetAmount, VaultOpType.DEPOSIT);
        uint256 encodedOnAndOffChain = riskPolicy.evaluate(offChainData, result, VaultOpType.DEPOSIT);
        riskReportNFT.mint(encodedOnAndOffChain);
        return encodedOnAndOffChain;
    }

    /**
     * @notice Stores a mint check, evaluates risk, and mints the packed report NFT.
     * @param vault Address of the target vault.
     * @param shareAmount Amount of shares to validate for mint.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return value The packed risk report.
     */
    function storeMintCheck(address vault, uint256 shareAmount, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256 value)
    {
        VaultGuardResult memory result;
        uint256 previewShares;
        uint256 previewAssets;
        (result, previewShares, previewAssets) = vaultGuard.storeCheck(vault, msg.sender, shareAmount, VaultOpType.MINT);
        uint256 encodedOnAndOffChain = riskPolicy.evaluate(offChainData, result, VaultOpType.MINT);
        riskReportNFT.mint(encodedOnAndOffChain);
        return encodedOnAndOffChain;
    }

    /**
     * @notice Stores a redeem check, evaluates risk, and mints the packed report NFT.
     * @param vault Address of the target vault.
     * @param shareAmount Amount of shares to validate for redeem.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return value The packed risk report.
     */
    function storeRedeemCheck(address vault, uint256 shareAmount, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256 value)
    {
        VaultGuardResult memory result;
        uint256 previewShares;
        uint256 previewAssets;
        (result, previewShares, previewAssets) =
            vaultGuard.storeCheck(vault, msg.sender, shareAmount, VaultOpType.REDEEM);
        uint256 encodedOnAndOffChain = riskPolicy.evaluate(offChainData, result, VaultOpType.REDEEM);
        riskReportNFT.mint(encodedOnAndOffChain);
        return encodedOnAndOffChain;
    }

    /**
     * @notice Stores a withdraw check, evaluates risk, and mints the packed report NFT.
     * @param vault Address of the target vault.
     * @param assetAmount Amount of assets to validate for withdraw.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return value The packed risk report.
     */
    function storeWithdrawCheck(address vault, uint256 assetAmount, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256 value)
    {
        VaultGuardResult memory result;
        uint256 previewShares;
        uint256 previewAssets;
        (result, previewShares, previewAssets) =
            vaultGuard.storeCheck(vault, msg.sender, assetAmount, VaultOpType.WITHDRAW);
        uint256 encodedOnAndOffChain = riskPolicy.evaluate(offChainData, result, VaultOpType.WITHDRAW);
        riskReportNFT.mint(encodedOnAndOffChain);
        return encodedOnAndOffChain;
    }

    /**
     * @notice Executes a guarded ERC-4626 deposit after validation.
     * @param vault Address of the target vault.
     * @param assetAmount Amount of assets to deposit.
     * @param receiver Address receiving minted shares.
     * @param minSharesOut Minimum acceptable shares out.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return sharesOut Amount of shares received and minted.
     */
    function guardedDeposit(
        address vault,
        uint256 assetAmount,
        address receiver,
        uint256 minSharesOut,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 sharesOut) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        vaultGuard.validate(vault, msg.sender, assetAmount, VaultOpType.DEPOSIT);
        (, uint256 previewShares,,) = vaultGuard.getLastCheck(vault, msg.sender);

        if (previewShares < minSharesOut) {
            revert SlippageExceeded(previewShares, minSharesOut);
        }

        address asset = IERC4626(vault).asset();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), assetAmount);
        IERC20(asset).forceApprove(vault, assetAmount);

        sharesOut = IERC4626(vault).deposit(assetAmount, receiver);

        IERC20(asset).forceApprove(vault, 0);

        if (sharesOut == 0) {
            revert ZeroOutput();
        }
        if (sharesOut < minSharesOut) {
            revert SlippageExceeded(sharesOut, minSharesOut);
        }

        emit GuardedDepositExecuted(msg.sender, vault, receiver, assetAmount, sharesOut);
    }

    /**
     * @notice Executes a guarded ERC-4626 mint after validation.
     * @param vault Address of the target vault.
     * @param shareAmount Amount of shares to mint.
     * @param receiver Address receiving minted shares.
     * @param minAssetsOut Minimum acceptable assets out.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return assetsOut Amount of assets invested.
     */
    function guardedMint(
        address vault,
        uint256 shareAmount,
        address receiver,
        uint256 minAssetsOut,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 assetsOut) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        vaultGuard.validate(vault, msg.sender, shareAmount, VaultOpType.MINT);
        (,, uint256 previewAssets,) = vaultGuard.getLastCheck(vault, msg.sender);

        if (previewAssets < minAssetsOut) {
            revert SlippageExceeded(previewAssets, minAssetsOut);
        }

        address asset = IERC4626(vault).asset();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), previewAssets);
        IERC20(asset).forceApprove(vault, previewAssets);

        assetsOut = IERC4626(vault).mint(shareAmount, receiver);

        IERC20(asset).forceApprove(vault, 0);

        if (assetsOut == 0) {
            revert ZeroOutput();
        }
        if (assetsOut < minAssetsOut) {
            revert SlippageExceeded(assetsOut, minAssetsOut);
        }
        // refund any excess assets sent by the user
        if (previewAssets > assetsOut) {
            uint256 excessAssets = previewAssets - assetsOut;
            IERC20(asset).safeTransfer(msg.sender, excessAssets);
        }

        emit GuardedMintExecuted(msg.sender, vault, receiver, shareAmount, assetsOut);
    }

    /**
     * @notice Executes a guarded ERC-4626 redeem after validation.
     * @param vault Address of the target vault.
     * @param shareAmount Amount of shares to redeem and burn.
     * @param receiver Address receiving redeemed assets.
     * @param minAssetsOut Minimum acceptable assets out.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return assetsOut Amount of assets received.
     */
    function guardedRedeem(
        address vault,
        uint256 shareAmount,
        address receiver,
        uint256 minAssetsOut,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 assetsOut) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        vaultGuard.validate(vault, msg.sender, shareAmount, VaultOpType.REDEEM);
        (,, uint256 previewAssets,) = vaultGuard.getLastCheck(vault, msg.sender);

        if (previewAssets < minAssetsOut) {
            revert SlippageExceeded(previewAssets, minAssetsOut);
        }

        IERC20(vault).safeTransferFrom(msg.sender, address(this), shareAmount);
        assetsOut = IERC4626(vault).redeem(shareAmount, receiver, address(this));

        if (assetsOut == 0) {
            revert ZeroOutput();
        }
        if (assetsOut < minAssetsOut) {
            revert SlippageExceeded(assetsOut, minAssetsOut);
        }

        emit GuardedRedeemExecuted(msg.sender, vault, receiver, shareAmount, assetsOut);
    }

    /**
     * @notice Executes a guarded ERC-4626 withdraw after validation.
     * @param vault Address of the target vault.
     * @param assetAmount Amount of assets to withdraw.
     * @param receiver Address receiving withdrawn assets.
     * @param minSharesOut Minimum acceptable shares out.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return sharesOut Amount of shares burned.
     */
    function guardedWithdraw(
        address vault,
        uint256 assetAmount,
        address receiver,
        uint256 minSharesOut,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 sharesOut) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        vaultGuard.validate(vault, msg.sender, assetAmount, VaultOpType.WITHDRAW);
        (, uint256 previewShares,,) = vaultGuard.getLastCheck(vault, msg.sender);

        if (previewShares < minSharesOut) {
            revert SlippageExceeded(previewShares, minSharesOut);
        }

        IERC20(vault).safeTransferFrom(msg.sender, address(this), previewShares);
        sharesOut = IERC4626(vault).withdraw(assetAmount, receiver, address(this));

        if (sharesOut == 0) {
            revert ZeroOutput();
        }
        if (sharesOut < minSharesOut) {
            revert SlippageExceeded(sharesOut, minSharesOut);
        }

        // refund any excess shares sent by the user
        if (previewShares > sharesOut) {
            uint256 excessShares = previewShares - sharesOut;
            IERC20(vault).safeTransfer(msg.sender, excessShares);
        }

        emit GuardedWithdrawExecuted(msg.sender, vault, receiver, assetAmount, sharesOut);
    }

    /**
     * @notice Decodes a packed ERC-4626 risk report.
     * @param packedRiskReport Packed risk report value.
     * @return report Decoded risk report.
     */
    function decodePackedRisk(uint256 packedRiskReport) external view returns (ERC4626DecodedRiskReport memory report) {
        return riskPolicy.decode(packedRiskReport);
    }

    /**
     * @notice Rescues ERC-20 tokens held by the router.
     * @param token Address of the token to rescue.
     * @param to Recipient of the rescued tokens.
     * @param amount Amount of tokens to transfer.
     */
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        IERC20(token).safeTransfer(to, amount);
    }
}
