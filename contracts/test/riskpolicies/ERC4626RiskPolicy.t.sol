// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {BaseRiskPolicy} from "../../src/riskpolicies/BaseRiskPolicy.sol";
import {ERC4626RiskPolicy, ERC4626DecodedRiskReport} from "../../src/riskpolicies/ERC4626RiskPolicy.sol";
import {SwapV2RiskPolicy} from "../../src/riskpolicies/SwapV2RiskPolicy.sol";
import {PolicyKind, PolicyRiskCategory} from "../../src/types/OnChainTypes.sol";
import {VaultGuardResult} from "../../src/types/OnChainTypes.sol";
import {VaultOffChainResult, VaultOpType, SwapOpType} from "../../src/types/OffChainTypes.sol";
import {RiskPolicyStructBuilder} from "../helpers/RiskPolicyStructBuilder.sol";

contract ERC4626RiskPolicyTest is Test, RiskPolicyStructBuilder {
    ERC4626RiskPolicy internal policy;
    SwapV2RiskPolicy internal swapPolicy;

    function setUp() public {
        policy = new ERC4626RiskPolicy();
        swapPolicy = new SwapV2RiskPolicy();
    }

    function test_evaluateAndDecodeWithOnChainFlags() public {
        VaultGuardResult memory onChain = _baseVaultGuardResult();
        onChain.VAULT_NOT_WHITELISTED = true;
        onChain.DONATION_ATTACK = true;

        uint256 packed = policy.evaluate("", onChain, VaultOpType.DEPOSIT);
        ERC4626DecodedRiskReport memory report = policy.decode(packed);

        assertEq(uint8(report.core.kind), uint8(PolicyKind.ERC4626));
        assertEq(report.core.operation, uint8(VaultOpType.DEPOSIT));
        assertEq(uint8(report.core.finalCategory), uint8(PolicyRiskCategory.CRITICAL));
        assertTrue(report.core.anyHardBlock);
        assertFalse(report.core.offChainValid);
        assertTrue(report.onChain.vaultNotWhitelisted);
        assertTrue(report.onChain.donationAttack);
        assertTrue(report.tokenRisk.hasPermit);
    }

    function test_evaluateAndDecodeIncludesOffChainAndEnhancedFields() public {
        VaultGuardResult memory onChain = _baseVaultGuardResult();
        VaultOffChainResult memory offChain = _baseVaultOffChain();
        offChain.trace.hasDangerousDelegateCall = false;
        offChain.trace.hasApprovalDrain = false;
        offChain.trace.hasOwnerSweep = false;
        offChain.trace.hasUpgradeCall = false;
        offChain.economic.outputDiscrepancyBps = 100;
        offChain.economic.sharePriceDriftBps = 100;
        offChain.economic.excessPullBps = 100;
        offChain.economic.assetOracleStale = false;
        offChain.economic.assetOracleAge = 100;
        offChain.vaultVerified = true;
        offChain.assetVerified = true;

        bytes memory offChainData = abi.encode(offChain);
        uint256 packed = policy.evaluate(offChainData, onChain, VaultOpType.MINT);
        ERC4626DecodedRiskReport memory report = policy.decode(packed);

        assertEq(report.core.operation, uint8(VaultOpType.MINT));
        assertTrue(report.core.offChainValid);
        assertFalse(report.offChain.hasDangerousDelegateCall);
        assertFalse(report.offChain.hasApprovalDrain);
        assertFalse(report.offChain.hasOwnerSweep);
        assertFalse(report.offChain.hasUpgradeCall);
        assertFalse(report.offChain.anyOracleStale);
        assertFalse(report.offChain.anyContractUnverified);
        assertTrue(report.enhancedView.enhancedDataPresent);
        assertEq(report.enhancedView.oracleAgeTier, 0);
        assertGt(report.enhancedView.excessPullTier, 0);
        assertGt(report.enhancedView.sharePriceDriftTier, 0);
    }

    function test_packOnChainCountsCriticalWarningAndTokenFlags() public {
        VaultGuardResult memory onChain = _baseVaultGuardResult();
        onChain.VAULT_NOT_WHITELISTED = true;
        onChain.DONATION_ATTACK = true;

        (uint32 packedFlags, uint32 packedTokenFlags, uint8 criticalCount, uint8 warningCount, bool anyHardBlock,,) =
            policy.packOnChain(onChain, VaultOpType.DEPOSIT);

        assertGt(packedFlags, 0);
        assertGt(packedTokenFlags, 0);
        assertEq(criticalCount, 1);
        assertEq(warningCount, 1);
        assertTrue(anyHardBlock);
    }

    function test_decodeWrongKindReverts() public {
        uint256 packed = swapPolicy.evaluate("", _baseSwapGuardResult(), SwapOpType.EXACT_TOKENS_IN);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseRiskPolicy.InvalidPackedKind.selector, uint8(PolicyKind.ERC4626), uint8(PolicyKind.SWAP_V2)
            )
        );
        policy.decode(packed);
    }
}
