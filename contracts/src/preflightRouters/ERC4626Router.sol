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

//  @author Sourav-IITBPL

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

    constructor(address vaultGuard_, address riskPolicy_, address riskReportNFT_) {
        if (vaultGuard_ == address(0) || riskPolicy_ == address(0)) {
            revert ZeroAddress();
        }

        vaultGuard = IERC4626VaultGuard(vaultGuard_);
        riskPolicy = IERC4626RiskPolicy(riskPolicy_);
        riskReportNFT = IRiskReportNFT(riskReportNFT_);
    }

    function setVaultGuard(address newGuard) external onlyOwner {
        if (newGuard == address(0)) {
            revert ZeroAddress();
        }
        vaultGuard = IERC4626VaultGuard(newGuard);
        emit VaultGuardUpdated(newGuard);
    }

    function setRiskPolicy(address newRiskPolicy) external onlyOwner {
        if (newRiskPolicy == address(0)) {
            revert ZeroAddress();
        }
        riskPolicy = IERC4626RiskPolicy(newRiskPolicy);
        emit RiskPolicyUpdated(newRiskPolicy);
    }

    function setRiskReportNFT(address newRiskReportNFT) external onlyOwner {
        if (newRiskReportNFT == address(0)) {
            revert ZeroAddress();
        }
        riskReportNFT = IRiskReportNFT(newRiskReportNFT);
    }

    function previewGuardedDeposit(address vault, uint256 assetAmount)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        return vaultGuard.checkVault(vault, assetAmount, true);
    }

    function previewGuardedRedeem(address vault, uint256 shareAmount)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        return vaultGuard.checkVault(vault, shareAmount, false);
    }

    function storeAndMintDepositCheck(address vault, uint256 assetAmount, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256)
    {
        (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets) =
            vaultGuard.storeCheck(vault, msg.sender, assetAmount, true);
        uint256 encodedOnAndOffChain = riskPolicy.evaluate(offChainData, result, VaultOpType.DEPOSIT);
        riskReportNFT.mint(encodedOnAndOffChain);
        return encodedOnAndOffChain;
    }

    function storeAndMintRedeemCheck(address vault, uint256 shareAmount, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256 value)
    {
        (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets) =
            vaultGuard.storeCheck(vault, msg.sender, shareAmount, false);
        uint256 encodedOnAndOffChain = riskPolicy.evaluate(offChainData, result, VaultOpType.REDEEM);
        riskReportNFT.mint(encodedOnAndOffChain);
        return encodedOnAndOffChain;
    }

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

        vaultGuard.validate(vault, msg.sender, assetAmount, true);
        (VaultGuardResult memory result,,,) = vaultGuard.getLastCheck(vault, msg.sender);

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

        vaultGuard.validate(vault, msg.sender, shareAmount, false);
        (VaultGuardResult memory result,,,) = vaultGuard.getLastCheck(vault, msg.sender);

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

    function decodePackedRisk(uint256 packedRiskReport) external view returns (ERC4626DecodedRiskReport memory report) {
        return riskPolicy.decode(packedRiskReport);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        IERC20(token).safeTransfer(to, amount);
    }
}
