// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {BaseRiskPolicy} from "../../src/riskpolicies/BaseRiskPolicy.sol";
import {LiquidityV2RiskPolicy, LiquidityV2DecodedRiskReport} from "../../src/riskpolicies/LiquidityV2RiskPolicy.sol";
import {SwapV2RiskPolicy} from "../../src/riskpolicies/SwapV2RiskPolicy.sol";
import {PolicyKind, PolicyRiskCategory} from "../../src/types/OnChainTypes.sol";
import {LiquidityV2GuardResult} from "../../src/types/OnChainTypes.sol";
import {LiquidityOffChainResult, LiquidityOpType, SwapOpType} from "../../src/types/OffChainTypes.sol";
import {RiskPolicyStructBuilder} from "../helpers/RiskPolicyStructBuilder.sol";

contract LiquidityV2RiskPolicyTest is Test, RiskPolicyStructBuilder {
    LiquidityV2RiskPolicy internal policy;
    SwapV2RiskPolicy internal swapPolicy;

    function setUp() public {
        policy = new LiquidityV2RiskPolicy();
        swapPolicy = new SwapV2RiskPolicy();
    }

    function test_evaluateAndDecodeWithOnChainFlags() public {
        LiquidityV2GuardResult memory onChain = _baseLiquidityGuardResult();
        onChain.ROUTER_NOT_TRUSTED = true;
        onChain.PAIR_NOT_EXISTS = true;

        uint256 packed = policy.evaluate("", onChain, LiquidityOpType.REMOVE);
        LiquidityV2DecodedRiskReport memory report = policy.decode(packed);

        assertEq(uint8(report.core.kind), uint8(PolicyKind.LIQUIDITY_V2));
        assertEq(report.core.operation, uint8(LiquidityOpType.REMOVE));
        assertEq(uint8(report.core.finalCategory), uint8(PolicyRiskCategory.CRITICAL));
        assertTrue(report.core.anyHardBlock);
        assertTrue(report.onChain.routerNotTrusted);
        assertTrue(report.onChain.pairNotExists);
        assertTrue(report.tokenRisk.notAContract);
        assertTrue(report.tokenRisk.hasPermit);
    }

    function test_evaluateAndDecodeIncludesOffChainAndEnhancedFields() public {
        LiquidityV2GuardResult memory onChain = _baseLiquidityGuardResult();
        LiquidityOffChainResult memory offChain = _baseLiquidityOffChain();
        offChain.trace.hasDangerousDelegateCall = false;
        offChain.trace.hasApprovalDrain = false;
        offChain.trace.hasOwnerSweep = false;
        offChain.trace.hasUnexpectedCreate = false;
        offChain.economic.isFirstDeposit = false;
        offChain.economic.lpMintDiscrepancyBps = 100;
        offChain.economic.ratioDeviationBps = 100;
        offChain.economic.isRemovalFrozen = false;
        offChain.economic.removalSimAmountA = 1;
        offChain.economic.removalSimAmountB = 0;
        offChain.economic.tokenAOracleStale = false;
        offChain.economic.tokenBOracleStale = false;
        offChain.economic.tokenAOracleAge = 100;
        offChain.economic.tokenBOracleAge = 100;
        offChain.routerVerified = true;
        offChain.pairVerified = true;
        offChain.tokenAVerified = true;
        offChain.tokenBVerified = true;

        bytes memory offChainData = abi.encode(offChain);
        uint256 packed = policy.evaluate(offChainData, onChain, LiquidityOpType.ADD);
        LiquidityV2DecodedRiskReport memory report = policy.decode(packed);

        assertTrue(report.core.offChainValid);
        assertFalse(report.offChain.hasDangerousDelegateCall);
        assertFalse(report.offChain.hasApprovalDrain);
        assertFalse(report.offChain.hasOwnerSweep);
        assertFalse(report.offChain.hasUnexpectedCreate);
        assertFalse(report.offChain.isRemovalFrozen);
        assertFalse(report.offChain.isFirstDeposit);
        assertFalse(report.offChain.anyOracleStale);
        assertFalse(report.offChain.anyContractUnverified);
        assertFalse(report.enhancedView.enhancedDataPresent);
        assertEq(report.enhancedView.sweepSeverityTier, 0);
    }

    function test_packOnChainCountsCriticalWarningAndTokenFlags() public {
        LiquidityV2GuardResult memory onChain = _baseLiquidityGuardResult();
        onChain.ROUTER_NOT_TRUSTED = true;
        onChain.FIRST_DEPOSITOR_RISK = true;

        (uint32 packedFlags, uint32 packedTokenFlags, uint8 criticalCount, uint8 warningCount, bool anyHardBlock,,) =
            policy.packOnChain(onChain);

        assertGt(packedFlags, 0);
        assertGt(packedTokenFlags, 0);
        assertEq(criticalCount, 3);
        assertEq(warningCount, 1);
        assertTrue(anyHardBlock);
    }

    function test_decodeWrongKindReverts() public {
        uint256 packed = swapPolicy.evaluate("", _baseSwapGuardResult(), SwapOpType.EXACT_TOKENS_IN);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseRiskPolicy.InvalidPackedKind.selector,
                uint8(PolicyKind.LIQUIDITY_V2),
                uint8(PolicyKind.SWAP_V2)
            )
        );
        policy.decode(packed);
    }
}
