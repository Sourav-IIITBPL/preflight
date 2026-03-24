// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {IVaultGuardRouter, VaultGuardCheckResult} from "./RouterDependencies.sol";
import {
    ERC4626RiskPolicy,
    ERC4626GuardRiskInput,
    ERC4626DecodedRiskReport
} from "../riskpolicies/ERC4626RiskPolicy.sol";
import {VaultOpType} from "../types/OffChainTypes.sol";

contract ERC4626Router is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidReceiver();
    error StaleStoredCheck();
    error VaultStateChanged();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error ZeroOutput();

    struct VaultPreview {
        VaultGuardCheckResult guardResult;
        uint256 previewShares;
        uint256 previewAssets;
        uint256 packedRiskReport;
        ERC4626DecodedRiskReport decodedRiskReport;
    }

    IVaultGuardRouter public vaultGuard;
    ERC4626RiskPolicy public riskPolicy;

    event VaultGuardUpdated(address indexed newGuard);
    event RiskPolicyUpdated(address indexed newRiskPolicy);
    event VaultCheckStored(
        address indexed user,
        address indexed vault,
        VaultOpType operation,
        uint256 amount,
        uint256 packedRiskReport
    );
    event GuardedDepositExecuted(
        address indexed user,
        address indexed vault,
        address indexed receiver,
        uint256 assetsIn,
        uint256 sharesOut,
        uint256 packedRiskReport
    );
    event GuardedRedeemExecuted(
        address indexed user,
        address indexed vault,
        address indexed receiver,
        uint256 sharesIn,
        uint256 assetsOut,
        uint256 packedRiskReport
    );

    constructor(address vaultGuard_, address riskPolicy_) {
        if (vaultGuard_ == address(0) || riskPolicy_ == address(0)) {
            revert ZeroAddress();
        }

        vaultGuard = IVaultGuardRouter(vaultGuard_);
        riskPolicy = ERC4626RiskPolicy(riskPolicy_);
    }

    function setVaultGuard(address newGuard) external onlyOwner {
        if (newGuard == address(0)) {
            revert ZeroAddress();
        }
        vaultGuard = IVaultGuardRouter(newGuard);
        emit VaultGuardUpdated(newGuard);
    }

    function setRiskPolicy(address newRiskPolicy) external onlyOwner {
        if (newRiskPolicy == address(0)) {
            revert ZeroAddress();
        }
        riskPolicy = ERC4626RiskPolicy(newRiskPolicy);
        emit RiskPolicyUpdated(newRiskPolicy);
    }

    function previewDepositRisk(address vault, uint256 assetAmount, bytes calldata offChainData)
        external
        returns (VaultPreview memory preview)
    {
        return _storeAndPreview(vault, msg.sender, assetAmount, true, VaultOpType.DEPOSIT, offChainData);
    }

    function previewRedeemRisk(address vault, uint256 shareAmount, bytes calldata offChainData)
        external
        returns (VaultPreview memory preview)
    {
        return _storeAndPreview(vault, msg.sender, shareAmount, false, VaultOpType.REDEEM, offChainData);
    }

    function storeDepositCheck(address vault, uint256 assetAmount, bytes calldata offChainData)
        external
        returns (VaultPreview memory preview)
    {
        return _storeAndPreview(vault, msg.sender, assetAmount, true, VaultOpType.DEPOSIT, offChainData);
    }

    function storeRedeemCheck(address vault, uint256 shareAmount, bytes calldata offChainData)
        external
        returns (VaultPreview memory preview)
    {
        return _storeAndPreview(vault, msg.sender, shareAmount, false, VaultOpType.REDEEM, offChainData);
    }

    function guardedDeposit(
        address vault,
        uint256 assetAmount,
        address receiver,
        uint256 minSharesOut,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 sharesOut, uint256 packedRiskReport) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        (VaultGuardCheckResult memory guardResult,,) = _revalidateStoredCheck(vault, msg.sender, assetAmount, true);
        packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), VaultOpType.DEPOSIT);

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

        emit GuardedDepositExecuted(msg.sender, vault, receiver, assetAmount, sharesOut, packedRiskReport);
    }

    function guardedRedeem(
        address vault,
        uint256 shareAmount,
        address receiver,
        uint256 minAssetsOut,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 assetsOut, uint256 packedRiskReport) {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }

        (VaultGuardCheckResult memory guardResult,,) = _revalidateStoredCheck(vault, msg.sender, shareAmount, false);
        packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), VaultOpType.REDEEM);

        IERC20(vault).safeTransferFrom(msg.sender, address(this), shareAmount);
        assetsOut = IERC4626(vault).redeem(shareAmount, receiver, address(this));

        if (assetsOut == 0) {
            revert ZeroOutput();
        }
        if (assetsOut < minAssetsOut) {
            revert SlippageExceeded(assetsOut, minAssetsOut);
        }

        emit GuardedRedeemExecuted(msg.sender, vault, receiver, shareAmount, assetsOut, packedRiskReport);
    }

    function decodePackedRisk(uint256 packedRiskReport)
        external
        view
        returns (ERC4626DecodedRiskReport memory report)
    {
        return riskPolicy.decode(packedRiskReport);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        IERC20(token).safeTransfer(to, amount);
    }

    function _storeAndPreview(
        address vault,
        address user,
        uint256 amount,
        bool isDeposit,
        VaultOpType operation,
        bytes calldata offChainData
    ) internal returns (VaultPreview memory preview) {
        (VaultGuardCheckResult memory guardResult, uint256 previewShares, uint256 previewAssets) =
            vaultGuard.storeCheck(vault, user, amount, isDeposit);

        uint256 packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), operation);

        preview.guardResult = guardResult;
        preview.previewShares = previewShares;
        preview.previewAssets = previewAssets;
        preview.packedRiskReport = packedRiskReport;
        preview.decodedRiskReport = riskPolicy.decode(packedRiskReport);

        emit VaultCheckStored(user, vault, operation, amount, packedRiskReport);
    }

    function _revalidateStoredCheck(address vault, address user, uint256 amount, bool isDeposit)
        internal
        returns (VaultGuardCheckResult memory currentResult, uint256 previewShares, uint256 previewAssets)
    {
        (
            VaultGuardCheckResult memory storedResult,
            uint256 storedPreviewShares,
            uint256 storedPreviewAssets,
            uint256 storedBlockNumber
        ) = vaultGuard.getLastCheck(vault, user);

        if (storedBlockNumber != block.number) {
            revert StaleStoredCheck();
        }

        (currentResult, previewShares, previewAssets) = vaultGuard.storeCheck(vault, user, amount, isDeposit);

        bytes32 storedFingerprint = keccak256(abi.encode(storedResult, storedPreviewShares, storedPreviewAssets));
        bytes32 currentFingerprint = keccak256(abi.encode(currentResult, previewShares, previewAssets));
        if (storedFingerprint != currentFingerprint) {
            revert VaultStateChanged();
        }
    }

    function _toRiskInput(VaultGuardCheckResult memory guardResult)
        internal
        pure
        returns (ERC4626GuardRiskInput memory riskInput)
    {
        riskInput = ERC4626GuardRiskInput({
            VAULT_NOT_WHITELISTED: guardResult.VAULT_NOT_WHITELISTED,
            VAULT_ZERO_SUPPLY: guardResult.VAULT_ZERO_SUPPLY,
            DONATION_ATTACK: guardResult.DONATION_ATTACK,
            SHARE_INFLATION_RISK: guardResult.SHARE_INFLATION_RISK,
            VAULT_BALANCE_MISMATCH: guardResult.VAULT_BALANCE_MISMATCH,
            EXCHANGE_RATE_ANOMALY: guardResult.EXCHANGE_RATE_ANOMALY,
            PREVIEW_REVERT: guardResult.PREVIEW_REVERT,
            ZERO_SHARES_OUT: guardResult.ZERO_SHARES_OUT,
            ZERO_ASSETS_OUT: guardResult.ZERO_ASSETS_OUT,
            DUST_SHARES: guardResult.DUST_SHARES,
            DUST_ASSETS: guardResult.DUST_ASSETS,
            EXCEEDS_MAX_DEPOSIT: guardResult.EXCEEDS_MAX_DEPOSIT,
            EXCEEDS_MAX_REDEEM: guardResult.EXCEEDS_MAX_REDEEM,
            PREVIEW_CONVERT_MISMATCH: guardResult.PREVIEW_CONVERT_MISMATCH
        });
    }
}
