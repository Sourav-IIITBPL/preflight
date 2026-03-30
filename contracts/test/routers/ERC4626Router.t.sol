// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {ERC4626Router} from "../../src/preflightRouters/ERC4626Router.sol";
import {VaultOpType} from "../../src/types/OffChainTypes.sol";
import {VaultGuardResult} from "../../src/types/OnChainTypes.sol";
import {
    MockERC20,
    MockERC4626RouterVault,
    MockERC4626Guard,
    MockERC4626RiskPolicy,
    MockRiskReportNFT
} from "../mocks/RouterExecutionMocks.sol";

contract ERC4626RouterTest is Test {
    MockERC20 internal asset;
    MockERC4626RouterVault internal vault;
    MockERC4626Guard internal guard;
    MockERC4626RiskPolicy internal policy;
    MockRiskReportNFT internal riskReportNFT;
    ERC4626Router internal router;

    address internal user = address(0xA11CE);
    address internal receiver = address(0xB0B);

    function setUp() public {
        asset = new MockERC20("Asset", "AST", 18);
        vault = new MockERC4626RouterVault(address(asset));
        guard = new MockERC4626Guard();
        policy = new MockERC4626RiskPolicy();
        riskReportNFT = new MockRiskReportNFT();
        router = new ERC4626Router(address(guard), address(policy), address(riskReportNFT));
    }

    function test_constructorRevertsForZeroGuardOrPolicy() public {
        vm.expectRevert(ERC4626Router.ZeroAddress.selector);
        new ERC4626Router(address(0), address(policy), address(riskReportNFT));

        vm.expectRevert(ERC4626Router.ZeroAddress.selector);
        new ERC4626Router(address(guard), address(0), address(riskReportNFT));
    }

    function test_constructorCurrentlyAllowsZeroRiskReportNft() public {
        ERC4626Router localRouter = new ERC4626Router(address(guard), address(policy), address(0));
        assertEq(address(localRouter.riskReportNFT()), address(0));
    }

    function test_ownerSettersUpdateDependencies() public {
        MockERC4626Guard newGuard = new MockERC4626Guard();
        MockERC4626RiskPolicy newPolicy = new MockERC4626RiskPolicy();
        MockRiskReportNFT newNft = new MockRiskReportNFT();

        router.setVaultGuard(address(newGuard));
        router.setRiskPolicy(address(newPolicy));
        router.setRiskReportNFT(address(newNft));

        assertEq(address(router.vaultGuard()), address(newGuard));
        assertEq(address(router.riskPolicy()), address(newPolicy));
        assertEq(address(router.riskReportNFT()), address(newNft));
    }

    function test_storeDepositCheckCallsGuardPolicyAndNft() public {
        VaultGuardResult memory result;
        result.DONATION_ATTACK = true;
        guard.setConfiguredResult(result, 12e18, 0);
        policy.setEvaluateReturn(777);

        vm.prank(user);
        uint256 packed = router.storeDepositCheck(address(vault), 5e18, hex"1234");

        assertEq(packed, 777);
        assertEq(guard.lastVault(), address(vault));
        assertEq(guard.lastUser(), user);
        assertEq(guard.lastAmount(), 5e18);
        assertEq(uint8(guard.lastOperation()), uint8(VaultOpType.DEPOSIT));
        assertEq(riskReportNFT.lastPackedRiskReport(), 777);
        assertEq(riskReportNFT.lastRecipient(), user);
    }

    function test_guardedDepositRevertsForInvalidReceiver() public {
        vm.prank(user);
        vm.expectRevert(ERC4626Router.InvalidReceiver.selector);
        router.guardedDeposit(address(vault), 1e18, address(0), 0, "");
    }

    function test_guardedDepositExecutesAndMintsShares() public {
        VaultGuardResult memory result;
        guard.setConfiguredResult(result, 10e18, 0);
        asset.mint(user, 100e18);
        vault.setOperationReturns(10e18, 0, 0, 0);

        vm.startPrank(user);
        asset.approve(address(router), type(uint256).max);
        uint256 sharesOut = router.guardedDeposit(address(vault), 10e18, receiver, 9e18, "");
        vm.stopPrank();

        assertEq(sharesOut, 10e18);
        assertEq(asset.balanceOf(address(vault)), 10e18);
        assertEq(vault.balanceOf(receiver), 10e18);
    }

    function test_guardedMintRefundsExcessAssets() public {
        VaultGuardResult memory result;
        guard.setConfiguredResult(result, 0, 20e18);
        asset.mint(user, 25e18);
        vault.setOperationReturns(0, 18e18, 0, 0);

        vm.startPrank(user);
        asset.approve(address(router), type(uint256).max);
        uint256 assetsSpent = router.guardedMint(address(vault), 5e18, receiver, 10e18, "");
        vm.stopPrank();

        assertEq(assetsSpent, 18e18);
        assertEq(asset.balanceOf(user), 7e18);
        assertEq(vault.balanceOf(receiver), 5e18);
    }

    function test_guardedRedeemRevertsOnZeroOutput() public {
        VaultGuardResult memory result;
        guard.setConfiguredResult(result, 0, 5e18);
        vault.setOperationReturns(0, 0, 0, 0);
        vault.mint(user, 3e18);
        asset.mint(address(vault), 100e18);

        vm.startPrank(user);
        vault.approve(address(router), type(uint256).max);
        vm.expectRevert(ERC4626Router.ZeroOutput.selector);
        router.guardedRedeem(address(vault), 3e18, receiver, 1e18, "");
        vm.stopPrank();
    }

    function test_guardedWithdrawRefundsExcessShares() public {
        VaultGuardResult memory result;
        guard.setConfiguredResult(result, 12e18, 0);
        vault.setOperationReturns(0, 0, 0, 9e18);
        vault.mint(user, 15e18);
        asset.mint(address(vault), 100e18);

        vm.startPrank(user);
        vault.approve(address(router), type(uint256).max);
        uint256 sharesBurned = router.guardedWithdraw(address(vault), 7e18, receiver, 8e18, "");
        vm.stopPrank();

        assertEq(sharesBurned, 9e18);
        assertEq(asset.balanceOf(receiver), 7e18);
        assertEq(vault.balanceOf(user), 6e18);
    }

    function test_decodePackedRiskPassesThroughToPolicy() public {
        policy.setDecodeFields(uint8(VaultOpType.REDEEM), 88);
        assertEq(router.decodePackedRisk(123).core.compositeScore, 88);
        assertEq(uint8(router.decodePackedRisk(123).operation), uint8(VaultOpType.REDEEM));
    }

    function test_rescueErc20TransfersTokens() public {
        asset.mint(address(router), 4e18);
        router.rescueERC20(address(asset), receiver, 4e18);
        assertEq(asset.balanceOf(receiver), 4e18);
    }
}
