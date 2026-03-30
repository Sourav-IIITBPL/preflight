// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    VaultGuardResult,
    LiquidityV2GuardResult,
    SwapV2GuardResult,
    TokenGuardResult
} from "../../src/types/OnChainTypes.sol";
import {
    VaultOffChainResult,
    VaultTraceFindings,
    VaultEconomicFindings,
    SwapOffChainResult,
    SwapTraceFindings,
    SwapEconomicFindings,
    LiquidityOffChainResult,
    LiquidityTraceFindings,
    LiquidityEconomicFindings,
    RiskLevel,
    VaultOpType,
    SwapOpType,
    LiquidityOpType
} from "../../src/types/OffChainTypes.sol";

abstract contract RiskPolicyStructBuilder {
    function _tokenWithPermit() internal pure returns (TokenGuardResult memory token) {
        token.HAS_PERMIT = true;
    }

    function _tokenWithCriticals() internal pure returns (TokenGuardResult memory token) {
        token.NOT_A_CONTRACT = true;
        token.HIGH_DECIMALS = true;
    }

    function _baseVaultGuardResult() internal pure returns (VaultGuardResult memory result) {
        result.tokenResult = _tokenWithPermit();
    }

    function _baseSwapGuardResult() internal pure returns (SwapV2GuardResult memory result) {
        result.tokenResult = new TokenGuardResult[](2);
        result.tokenResult[0] = _tokenWithPermit();
        result.tokenResult[1] = _tokenWithCriticals();
    }

    function _baseLiquidityGuardResult() internal pure returns (LiquidityV2GuardResult memory result) {
        result.tokenAResult = _tokenWithPermit();
        result.tokenBResult = _tokenWithCriticals();
    }

    function _baseVaultOffChain() internal pure returns (VaultOffChainResult memory result) {
        result.isSafe = false;
        result.riskLevel = RiskLevel.WARNING;
        result.riskScore = 44;
        result.operation = VaultOpType.DEPOSIT;
        result.trace = VaultTraceFindings({
            hasDangerousDelegateCall: true,
            delegateCallTarget: address(0),
            hasSelfDestruct: false,
            hasUnexpectedCreate: false,
            createAddresses: new address[](0),
            hasApprovalDrain: true,
            approvalDrainSpender: address(0),
            hasReentrancy: false,
            reentrancyAddress: address(0),
            hasOwnerSweep: true,
            sweepAmount: 20e18,
            sweepToken: address(0),
            hasUpgradeCall: true,
            upgradeTarget: address(0)
        });
        result.economic = VaultEconomicFindings({
            simulationReverted: false,
            revertReason: "",
            primaryOutput: 0,
            primaryExpected: 0,
            outputDiscrepancyBps: 620,
            sharePriceBefore: 0,
            sharePriceAfter: 0,
            sharePriceDriftBps: 700,
            isExitFrozen: false,
            exitRevertReason: "",
            exitSimulatedOut: 0,
            actualAssetPull: 0,
            excessPullBps: 900,
            assetPriceUSD: 2e18,
            assetOracleStale: true,
            assetOracleAge: 90_000
        });
        result.vaultVerified = false;
        result.assetVerified = true;
        result.simulatedAt = 1;
        result.network = "test";
    }

    function _baseSwapOffChain() internal pure returns (SwapOffChainResult memory result) {
        result.isSafe = false;
        result.riskLevel = RiskLevel.WARNING;
        result.riskScore = 37;
        result.operation = SwapOpType.EXACT_TOKENS_IN;
        result.trace = SwapTraceFindings({
            hasDangerousDelegateCall: false,
            delegateCallTarget: address(0),
            hasSelfDestruct: true,
            hasUnexpectedCreate: true,
            createAddresses: new address[](0),
            hasApprovalDrain: false,
            approvalDrainSpender: address(0),
            hasReentrancy: true,
            reentrancyAddress: address(0)
        });
        result.economic = SwapEconomicFindings({
            simulationReverted: false,
            revertReason: "",
            actualAmountIn: 0,
            actualAmountOut: 800e18,
            inputHeadroomBps: 0,
            ethRefunded: 0,
            oracleFairAmountOut: 1000e18,
            priceImpactBps: 250,
            oracleDeviation: true,
            isFeeOnTransfer: true,
            measuredFeePercent: 700,
            tokenInPriceUSD: 0,
            tokenOutPriceUSD: 0,
            tokenInOracleStale: true,
            tokenOutOracleStale: false,
            tokenInOracleAge: 100_000,
            tokenOutOracleAge: 100
        });
        result.routerVerified = false;
        result.tokenInVerified = true;
        result.tokenOutVerified = false;
        result.simulatedAt = 1;
        result.network = "test";
    }

    function _baseLiquidityOffChain() internal pure returns (LiquidityOffChainResult memory result) {
        result.isSafe = false;
        result.riskLevel = RiskLevel.WARNING;
        result.riskScore = 39;
        result.operation = LiquidityOpType.ADD;
        result.trace = LiquidityTraceFindings({
            hasDangerousDelegateCall: true,
            delegateCallTarget: address(0),
            hasSelfDestruct: false,
            hasUnexpectedCreate: true,
            createAddresses: new address[](0),
            hasApprovalDrain: true,
            approvalDrainSpender: address(0),
            hasReentrancy: false,
            reentrancyAddress: address(0),
            hasOwnerSweep: true,
            sweepAmount: 100e18,
            sweepToken: address(0)
        });
        result.economic = LiquidityEconomicFindings({
            simulationReverted: false,
            revertReason: "",
            actualAmountA: 0,
            actualAmountB: 0,
            actualLPMinted: 0,
            expectedLPMinted: 0,
            lpMintDiscrepancyBps: 800,
            excessTokenALost: 5e18,
            excessTokenBLost: 3e18,
            excessValueLostUSD: 0,
            actualReceivedA: 0,
            actualReceivedB: 0,
            pairAddress: address(0),
            lpTotalSupply: 0,
            reserveA: 0,
            reserveB: 0,
            isFirstDeposit: true,
            poolRatio: 0,
            oracleRatio: 0,
            ratioDeviationBps: 900,
            isRemovalFrozen: false,
            removalRevertReason: "",
            removalSimAmountA: 0,
            removalSimAmountB: 0,
            tokenAPriceUSD: 2e18,
            tokenBPriceUSD: 3e18,
            tokenAOracleStale: false,
            tokenBOracleStale: true,
            tokenAOracleAge: 100,
            tokenBOracleAge: 100_000
        });
        result.routerVerified = false;
        result.pairVerified = false;
        result.tokenAVerified = true;
        result.tokenBVerified = false;
        result.simulatedAt = 1;
        result.network = "test";
    }
}
