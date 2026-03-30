// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {LiquidityV2Router} from "../../src/preflightRouters/V2Routers/LiquidityV2Router.sol";
import {LiquidityOperationType} from "../../src/types/OnChainTypes.sol";
import {LiquidityOpType} from "../../src/types/OffChainTypes.sol";
import {
    MockERC20,
    MockLiquidityV2Guard,
    MockLiquidityV2RiskPolicy,
    MockRiskReportNFT,
    MockV2PairToken,
    MockExecutableV2Router
} from "../mocks/RouterExecutionMocks.sol";
import {MockV2Factory} from "../mocks/MockV2Factory.sol";

contract LiquidityV2RouterTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal weth;
    MockLiquidityV2Guard internal guard;
    MockLiquidityV2RiskPolicy internal policy;
    MockRiskReportNFT internal riskReportNFT;
    MockV2Factory internal factory;
    MockExecutableV2Router internal ammRouter;
    MockV2PairToken internal pair;
    MockV2PairToken internal ethPair;
    LiquidityV2Router internal router;

    address internal user = address(0xA11CE);
    address internal lpRecipient = address(0xB0B);
    address internal refundRecipient = address(0xCAFE);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        guard = new MockLiquidityV2Guard();
        policy = new MockLiquidityV2RiskPolicy();
        riskReportNFT = new MockRiskReportNFT();
        factory = new MockV2Factory();
        ammRouter = new MockExecutableV2Router(address(factory), address(weth));
        pair = new MockV2PairToken(address(tokenA), address(tokenB), address(factory));
        ethPair = new MockV2PairToken(address(tokenA), address(weth), address(factory));
        factory.setPair(address(tokenA), address(tokenB), address(pair));
        factory.setPair(address(tokenA), address(weth), address(ethPair));
        router = new LiquidityV2Router(address(guard), address(policy), address(riskReportNFT));
    }

    function test_constructorRevertsForZeroAddressInputs() public {
        vm.expectRevert(LiquidityV2Router.ZeroAddress.selector);
        new LiquidityV2Router(address(0), address(policy), address(riskReportNFT));

        vm.expectRevert(LiquidityV2Router.ZeroAddress.selector);
        new LiquidityV2Router(address(guard), address(0), address(riskReportNFT));

        vm.expectRevert(LiquidityV2Router.ZeroAddress.selector);
        new LiquidityV2Router(address(guard), address(policy), address(0));
    }

    function test_previewAndSetterFlowsWork() public {
        router.previewGuardedAddLiquidity(address(ammRouter), address(tokenA), address(tokenB), 1e18, 2e18);
        assertEq(guard.lastRouter(), address(ammRouter));
        assertEq(guard.lastTokenA(), address(tokenA));
        assertEq(guard.lastTokenB(), address(tokenB));
        assertEq(uint8(guard.lastOperationType()), uint8(LiquidityOperationType.ADD));

        MockLiquidityV2Guard newGuard = new MockLiquidityV2Guard();
        MockLiquidityV2RiskPolicy newPolicy = new MockLiquidityV2RiskPolicy();
        MockRiskReportNFT newNft = new MockRiskReportNFT();
        router.setLiquidityGuard(address(newGuard));
        router.setRiskPolicy(address(newPolicy));
        router.setRiskReportNFT(address(newNft));

        assertEq(address(router.liquidityGuard()), address(newGuard));
        assertEq(address(router.riskPolicy()), address(newPolicy));
        assertEq(address(router.riskReportNFT()), address(newNft));
    }

    function test_storeAndMintAddLiquidityCheckCallsPolicyAndNft() public {
        policy.setEvaluateReturn(3333);

        vm.prank(user);
        uint256 packed = router.storeAndMintAddLiquidityCheck(
            address(ammRouter), address(tokenA), address(tokenB), 4e18, 5e18, hex"0102"
        );

        assertEq(packed, 3333);
        assertEq(guard.lastRouter(), address(ammRouter));
        assertEq(guard.lastTokenA(), address(tokenA));
        assertEq(guard.lastTokenB(), address(tokenB));
        assertEq(uint8(guard.lastOperationType()), uint8(LiquidityOperationType.ADD));
        assertEq(riskReportNFT.lastPackedRiskReport(), 3333);
    }

    function test_guardedAddLiquidityRevertsForInvalidRecipients() public {
        LiquidityV2Router.AddLiquidityParams memory params = LiquidityV2Router.AddLiquidityParams({
            ammRouter: address(ammRouter),
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            amountADesired: 1e18,
            amountBDesired: 1e18,
            amountAMin: 0,
            amountBMin: 0,
            lpRecipient: address(0),
            refundRecipient: refundRecipient,
            deadline: block.timestamp
        });

        vm.prank(user);
        vm.expectRevert(LiquidityV2Router.InvalidRecipient.selector);
        router.guardedAddLiquidity(params);
    }

    function test_guardedAddLiquidityRefundsUnusedTokens() public {
        ammRouter.setAddLiquidityResult(7e18, 4e18, 9e18);
        tokenA.mint(user, 10e18);
        tokenB.mint(user, 10e18);

        LiquidityV2Router.AddLiquidityParams memory params = LiquidityV2Router.AddLiquidityParams({
            ammRouter: address(ammRouter),
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            amountADesired: 10e18,
            amountBDesired: 8e18,
            amountAMin: 0,
            amountBMin: 0,
            lpRecipient: lpRecipient,
            refundRecipient: refundRecipient,
            deadline: block.timestamp
        });

        vm.startPrank(user);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        (uint256 usedA, uint256 usedB, uint256 liquidity) = router.guardedAddLiquidity(params);
        vm.stopPrank();

        assertEq(usedA, 7e18);
        assertEq(usedB, 4e18);
        assertEq(liquidity, 9e18);
        assertEq(tokenA.balanceOf(refundRecipient), 3e18);
        assertEq(tokenB.balanceOf(refundRecipient), 4e18);
        assertEq(pair.balanceOf(lpRecipient), 9e18);
    }

    function test_guardedAddLiquidityEthValidatesValueAndRefunds() public {
        LiquidityV2Router.AddLiquidityETHParams memory params = LiquidityV2Router.AddLiquidityETHParams({
            ammRouter: address(ammRouter),
            token: address(tokenA),
            amountTokenDesired: 10e18,
            amountTokenMin: 0,
            amountETHMin: 0,
            lpRecipient: lpRecipient,
            refundRecipient: refundRecipient,
            deadline: block.timestamp
        });

        vm.expectRevert(LiquidityV2Router.InvalidEthValue.selector);
        router.guardedAddLiquidityETH(params);

        tokenA.mint(user, 10e18);
        ammRouter.setAddLiquidityEthResult(6e18, 3e18, 5e18, 2e18);
        vm.deal(address(ammRouter), 5e18);
        vm.deal(user, 5e18);
        uint256 refundBefore = refundRecipient.balance;

        vm.startPrank(user);
        tokenA.approve(address(router), type(uint256).max);
        (uint256 tokenUsed, uint256 ethUsed, uint256 liquidity) = router.guardedAddLiquidityETH{value: 5e18}(params);
        vm.stopPrank();

        assertEq(tokenUsed, 6e18);
        assertEq(ethUsed, 3e18);
        assertEq(liquidity, 5e18);
        assertEq(tokenA.balanceOf(refundRecipient), 4e18);
        assertEq(refundRecipient.balance - refundBefore, 2e18);
        assertEq(ethPair.balanceOf(lpRecipient), 5e18);
    }

    function test_guardedRemoveLiquidityRevertsWhenPairMissing() public {
        LiquidityV2Router.RemoveLiquidityParams memory params = LiquidityV2Router.RemoveLiquidityParams({
            ammRouter: address(ammRouter),
            tokenA: address(tokenA),
            tokenB: address(0x9999),
            lpAmountToBurn: 1e18,
            amountAMin: 0,
            amountBMin: 0,
            tokenRecipient: lpRecipient,
            deadline: block.timestamp
        });

        vm.prank(user);
        vm.expectRevert(LiquidityV2Router.PairNotFound.selector);
        router.guardedRemoveLiquidity(params);
    }

    function test_guardedRemoveLiquidityTransfersLpAndOutputs() public {
        ammRouter.setRemoveLiquidityResult(3e18, 2e18);
        pair.mint(user, 5e18);

        LiquidityV2Router.RemoveLiquidityParams memory params = LiquidityV2Router.RemoveLiquidityParams({
            ammRouter: address(ammRouter),
            tokenA: address(tokenA),
            tokenB: address(tokenB),
            lpAmountToBurn: 5e18,
            amountAMin: 0,
            amountBMin: 0,
            tokenRecipient: lpRecipient,
            deadline: block.timestamp
        });

        vm.startPrank(user);
        pair.approve(address(router), type(uint256).max);
        (uint256 amountAOut, uint256 amountBOut, uint256 packedRiskReport) = router.guardedRemoveLiquidity(params);
        vm.stopPrank();

        assertEq(amountAOut, 3e18);
        assertEq(amountBOut, 2e18);
        assertEq(tokenA.balanceOf(lpRecipient), 3e18);
        assertEq(tokenB.balanceOf(lpRecipient), 2e18);
        assertEq(packedRiskReport, 0);
    }

    function test_guardedRemoveLiquidityEthWorks() public {
        ammRouter.setRemoveLiquidityEthResult(2e18, 1e18);
        vm.deal(address(ammRouter), 5e18);
        ethPair.mint(user, 4e18);

        LiquidityV2Router.RemoveLiquidityETHParams memory params = LiquidityV2Router.RemoveLiquidityETHParams({
            ammRouter: address(ammRouter),
            token: address(tokenA),
            lpAmountToBurn: 4e18,
            amountTokenMin: 0,
            amountETHMin: 0,
            recipient: lpRecipient,
            deadline: block.timestamp
        });

        uint256 ethBefore = lpRecipient.balance;
        vm.startPrank(user);
        ethPair.approve(address(router), type(uint256).max);
        (uint256 tokenOut, uint256 ethOut, uint256 packedRiskReport) = router.guardedRemoveLiquidityETH(params);
        vm.stopPrank();

        assertEq(tokenOut, 2e18);
        assertEq(ethOut, 1e18);
        assertEq(packedRiskReport, 0);
        assertEq(tokenA.balanceOf(lpRecipient), 2e18);
        assertEq(lpRecipient.balance - ethBefore, 1e18);
    }

    function test_decodeAndRescueFunctionsWork() public {
        policy.setDecodeFields(uint8(LiquidityOpType.REMOVE_ETH), 91);
        assertEq(router.decodePackedRisk(1).core.compositeScore, 91);

        tokenA.mint(address(router), 2e18);
        router.rescueERC20(address(tokenA), lpRecipient, 2e18);
        assertEq(tokenA.balanceOf(lpRecipient), 2e18);

        vm.deal(address(router), 1e18);
        uint256 balanceBefore = lpRecipient.balance;
        router.rescueETH(payable(lpRecipient), 1e18);
        assertEq(lpRecipient.balance - balanceBefore, 1e18);
    }
}
