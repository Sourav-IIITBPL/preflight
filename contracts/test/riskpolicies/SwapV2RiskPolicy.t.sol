// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {BaseRiskPolicy} from "../../src/riskpolicies/BaseRiskPolicy.sol";
import {ERC4626RiskPolicy} from "../../src/riskpolicies/ERC4626RiskPolicy.sol";
import {SwapV2RiskPolicy, SwapV2DecodedRiskReport} from "../../src/riskpolicies/SwapV2RiskPolicy.sol";
import {PolicyKind, PolicyRiskCategory} from "../../src/types/OnChainTypes.sol";
import {SwapV2GuardResult} from "../../src/types/OnChainTypes.sol";
import {SwapOffChainResult, SwapOpType, VaultOpType} from "../../src/types/OffChainTypes.sol";
import {RiskPolicyStructBuilder} from "../helpers/RiskPolicyStructBuilder.sol";

contract SwapV2RiskPolicyTest is Test, RiskPolicyStructBuilder {
    SwapV2RiskPolicy internal policy;
    ERC4626RiskPolicy internal ercPolicy;

    function setUp() public {
        policy = new SwapV2RiskPolicy();
        ercPolicy = new ERC4626RiskPolicy();
    }

    function test_evaluateAndDecodeWithOnChainFlags() public {
        SwapV2GuardResult memory onChain = _baseSwapGuardResult();
        onChain.ROUTER_NOT_TRUSTED = true;
        onChain.POOL_NOT_EXISTS = true;

        uint256 packed = policy.evaluate("", onChain, SwapOpType.EXACT_TOKENS_OUT);
        SwapV2DecodedRiskReport memory report = policy.decode(packed);

        assertEq(uint8(report.core.kind), uint8(PolicyKind.SWAP_V2));
        assertEq(report.core.operation, uint8(SwapOpType.EXACT_TOKENS_OUT));
        assertEq(uint8(report.core.finalCategory), uint8(PolicyRiskCategory.CRITICAL));
        assertTrue(report.core.anyHardBlock);
        assertTrue(report.onChain.routerNotTrusted);
        assertTrue(report.onChain.poolNotExists);
        assertTrue(report.tokenRisk.notAContract);
        assertTrue(report.tokenRisk.hasPermit);
    }

    function test_evaluateWithAllOnChainFlags() public {
        SwapV2GuardResult memory onChain = _baseSwapGuardResult();
        onChain.ROUTER_NOT_TRUSTED = true;
        onChain.FACTORY_NOT_TRUSTED = true;
        onChain.DEEP_MULTIHOP = true;
        onChain.DUPLICATE_TOKEN_IN_PATH = true;
        onChain.POOL_NOT_EXISTS = true;
        onChain.FACTORY_MISMATCH = true;
        onChain.ZERO_LIQUIDITY = true;
        onChain.LOW_LIQUIDITY = true;
        onChain.LOW_LP_SUPPLY = true;
        onChain.POOL_TOO_NEW = true;
        onChain.SEVERE_IMBALANCE = true;
        onChain.K_INVARIANT_BROKEN = true;
        onChain.HIGH_SWAP_IMPACT = true;
        onChain.FLASHLOAN_RISK = true;
        onChain.PRICE_MANIPULATED = true;

        uint256 packed = policy.evaluate("", onChain, SwapOpType.EXACT_TOKENS_IN);
        SwapV2DecodedRiskReport memory report = policy.decode(packed);

        assertTrue(report.onChain.routerNotTrusted);
        assertTrue(report.onChain.factoryNotTrusted);
        assertTrue(report.onChain.deepMultihop);
        assertTrue(report.onChain.duplicateTokenInPath);
        assertTrue(report.onChain.poolNotExists);
        assertTrue(report.onChain.factoryMismatch);
        assertTrue(report.onChain.zeroLiquidity);
        assertTrue(report.onChain.lowLiquidity);
        assertTrue(report.onChain.lowLpSupply);
        assertTrue(report.onChain.poolTooNew);
        assertTrue(report.onChain.severeImbalance);
        assertTrue(report.onChain.kInvariantBroken);
        assertTrue(report.onChain.highSwapImpact);
        assertTrue(report.onChain.flashloanRisk);
        assertTrue(report.onChain.priceManipulated);
    }

    function test_evaluateAndDecodeIncludesOffChainAndEnhancedFields() public {
        SwapV2GuardResult memory onChain = _baseSwapGuardResult();
        SwapOffChainResult memory offChain = _baseSwapOffChain();
        offChain.trace.hasSelfDestruct = false;
        offChain.trace.hasUnexpectedCreate = false;
        offChain.trace.hasReentrancy = false;
        offChain.economic.isFeeOnTransfer = false;
        offChain.economic.tokenInOracleStale = false;
        offChain.economic.tokenOutOracleStale = false;
        offChain.economic.oracleDeviation = false;
        offChain.economic.priceImpactBps = 100;
        offChain.economic.inputHeadroomBps = 1;
        offChain.economic.measuredFeePercent = 0;
        offChain.economic.tokenInOracleAge = 100;
        offChain.economic.tokenOutOracleAge = 100;
        offChain.routerVerified = true;
        offChain.tokenInVerified = true;
        offChain.tokenOutVerified = true;

        bytes memory offChainData = abi.encode(offChain);
        uint256 packed = policy.evaluate(offChainData, onChain, SwapOpType.EXACT_TOKENS_IN);
        SwapV2DecodedRiskReport memory report = policy.decode(packed);

        assertTrue(report.core.offChainValid);
        assertFalse(report.offChain.hasSelfDestruct);
        assertFalse(report.offChain.hasUnexpectedCreate);
        assertFalse(report.offChain.hasReentrancy);
        assertFalse(report.offChain.isFeeOnTransfer);
        assertFalse(report.offChain.anyOracleStale);
        assertFalse(report.offChain.anyContractUnverified);
        assertFalse(report.offChain.oracleDeviation);
        assertFalse(report.enhancedView.enhancedDataPresent);
        assertFalse(report.enhancedView.simulationRevertBlock);
    }

    function test_packOnChainCountsCriticalWarningAndTokenFlags() public {
        SwapV2GuardResult memory onChain = _baseSwapGuardResult();
        onChain.FACTORY_NOT_TRUSTED = true;
        onChain.DUPLICATE_TOKEN_IN_PATH = true;

        (uint32 packedFlags, uint32 packedTokenFlags, uint8 criticalCount, uint8 warningCount, bool anyHardBlock,,) =
            policy.packOnChain(onChain);

        assertGt(packedFlags, 0);
        assertGt(packedTokenFlags, 0);
        assertEq(criticalCount, 3);
        assertEq(warningCount, 1);
        assertTrue(anyHardBlock);
    }

    function test_decodeWrongKindReverts() public {
        uint256 packed = ercPolicy.evaluate("", _baseVaultGuardResult(), VaultOpType.DEPOSIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseRiskPolicy.InvalidPackedKind.selector, uint8(PolicyKind.SWAP_V2), uint8(PolicyKind.ERC4626)
            )
        );
        policy.decode(packed);
    }
}
