// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {SwapV2Router} from "../../src/preflightRouters/V2Routers/SwapV2Router.sol";
import {SwapOpType} from "../../src/types/OffChainTypes.sol";
import {
    MockERC20,
    MockSwapV2Guard,
    MockSwapV2RiskPolicy,
    MockRiskReportNFT,
    MockExecutableV2Router
} from "../mocks/RouterExecutionMocks.sol";
import {MockV2Factory} from "../mocks/MockV2Factory.sol";

contract SwapV2RouterTest is Test {
    MockERC20 internal tokenIn;
    MockERC20 internal tokenOut;
    MockERC20 internal weth;
    MockSwapV2Guard internal guard;
    MockSwapV2RiskPolicy internal policy;
    MockRiskReportNFT internal riskReportNFT;
    MockV2Factory internal factory;
    MockExecutableV2Router internal ammRouter;
    SwapV2Router internal router;

    address internal user = address(0xA11CE);
    address internal receiver = address(0xB0B);
    address internal refundRecipient = address(0xCAFE);

    function setUp() public {
        tokenIn = new MockERC20("Token In", "TIN", 18);
        tokenOut = new MockERC20("Token Out", "TOUT", 18);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        guard = new MockSwapV2Guard();
        policy = new MockSwapV2RiskPolicy();
        riskReportNFT = new MockRiskReportNFT();
        factory = new MockV2Factory();
        ammRouter = new MockExecutableV2Router(address(factory), address(weth));
        router = new SwapV2Router(address(guard), address(policy), address(riskReportNFT));
    }

    function test_constructorRevertsForZeroAddressInputs() public {
        vm.expectRevert(SwapV2Router.ZeroAddress.selector);
        new SwapV2Router(address(0), address(policy), address(riskReportNFT));

        vm.expectRevert(SwapV2Router.ZeroAddress.selector);
        new SwapV2Router(address(guard), address(0), address(riskReportNFT));

        vm.expectRevert(SwapV2Router.ZeroAddress.selector);
        new SwapV2Router(address(guard), address(policy), address(0));
    }

    function test_ownerSettersUpdateDependencies() public {
        MockSwapV2Guard newGuard = new MockSwapV2Guard();
        MockSwapV2RiskPolicy newPolicy = new MockSwapV2RiskPolicy();
        MockRiskReportNFT newNft = new MockRiskReportNFT();

        router.setSwapGuard(address(newGuard));
        router.setRiskPolicy(address(newPolicy));
        router.setRiskReportNFT(address(newNft));

        assertEq(address(router.swapGuard()), address(newGuard));
        assertEq(address(router.riskPolicy()), address(newPolicy));
        assertEq(address(router.riskReportNFT()), address(newNft));
    }

    function test_guardedPreviewUsesTailForExactInAndHeadForExactOut() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        uint256[] memory quote = new uint256[](2);
        quote[0] = 10e18;
        quote[1] = 7e18;
        guard.setQuote(quote);

        (, uint256 exactInOut) = router.guardedPreview(address(ammRouter), path, true, 10e18);
        (, uint256 exactOutIn) = router.guardedPreview(address(ammRouter), path, false, 7e18);

        assertEq(exactInOut, 7e18);
        assertEq(exactOutIn, 10e18);
    }

    function test_storeAndMintSwapCheckRevertsForInvalidPath() public {
        address[] memory path = new address[](1);
        path[0] = address(tokenIn);

        vm.prank(user);
        vm.expectRevert(SwapV2Router.InvalidPath.selector);
        router.storeAndMintSwapCheck(address(ammRouter), path, 1e18, SwapOpType.EXACT_TOKENS_IN, "");
    }

    function test_storeAndMintSwapCheckCallsPolicyAndNft() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);
        policy.setEvaluateReturn(2222);

        vm.prank(user);
        uint256 packed = router.storeAndMintSwapCheck(address(ammRouter), path, 3e18, SwapOpType.EXACT_TOKENS_OUT, hex"abcd");

        assertEq(packed, 2222);
        assertEq(guard.lastRouter(), address(ammRouter));
        assertEq(guard.lastAmount(), 3e18);
        assertFalse(guard.lastIsExactTokenIn());
        assertEq(guard.lastUser(), user);
        assertEq(riskReportNFT.lastPackedRiskReport(), 2222);
        assertEq(riskReportNFT.lastRecipient(), user);
    }

    function test_guardedSwapExactTokensForTokensRevertsForInvalidReceiver() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        vm.prank(user);
        vm.expectRevert(SwapV2Router.InvalidReceiver.selector);
        router.guardedSwapExactTokensForTokens(address(ammRouter), 1e18, 0, path, address(0), block.timestamp);
    }

    function test_guardedSwapTokensForExactTokensRefundsUnusedInput() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 6e18;
        amounts[1] = 4e18;
        ammRouter.setSwapResult(amounts, 0);

        tokenIn.mint(user, 20e18);
        vm.startPrank(user);
        tokenIn.approve(address(router), type(uint256).max);
        (uint256[] memory resultAmounts, uint256 packedRiskReport) = router.guardedSwapTokensForExactTokens(
            address(ammRouter), 4e18, 10e18, path, receiver, refundRecipient, block.timestamp
        );
        vm.stopPrank();

        assertEq(resultAmounts[0], 6e18);
        assertEq(tokenIn.balanceOf(refundRecipient), 4e18);
        assertEq(tokenOut.balanceOf(receiver), 4e18);
        assertEq(packedRiskReport, 0);
    }

    function test_guardedSwapExactEthForTokensValidatesPathAndValue() public {
        address[] memory badPath = new address[](2);
        badPath[0] = address(tokenIn);
        badPath[1] = address(tokenOut);

        vm.expectRevert(SwapV2Router.InvalidWethPath.selector);
        router.guardedSwapExactETHForTokens(address(ammRouter), 0, badPath, receiver, block.timestamp);

        address[] memory goodPath = new address[](2);
        goodPath[0] = address(weth);
        goodPath[1] = address(tokenOut);

        vm.expectRevert(SwapV2Router.InvalidEthValue.selector);
        router.guardedSwapExactETHForTokens(address(ammRouter), 0, goodPath, receiver, block.timestamp);
    }

    function test_guardedSwapEthForExactTokensRefundsEth() public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenOut);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3e18;
        amounts[1] = 5e18;
        ammRouter.setSwapResult(amounts, 2e18);
        vm.deal(address(ammRouter), 10e18);
        vm.deal(user, 5e18);

        uint256 refundBefore = refundRecipient.balance;
        vm.prank(user);
        router.guardedSwapETHForExactTokens{value: 5e18}(
            address(ammRouter), 5e18, path, receiver, refundRecipient, block.timestamp
        );

        assertEq(refundRecipient.balance - refundBefore, 2e18);
        assertEq(tokenOut.balanceOf(receiver), 5e18);
    }

    function test_guardedSwapExactTokensForEthSendsEthOut() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(weth);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 8e18;
        amounts[1] = 3e18;
        ammRouter.setSwapResult(amounts, 0);
        vm.deal(address(ammRouter), 10e18);
        tokenIn.mint(user, 10e18);

        uint256 receiverBefore = receiver.balance;
        vm.startPrank(user);
        tokenIn.approve(address(router), type(uint256).max);
        router.guardedSwapExactTokensForETH(address(ammRouter), 8e18, 2e18, path, receiver, block.timestamp);
        vm.stopPrank();

        assertEq(receiver.balance - receiverBefore, 3e18);
    }

    function test_decodeAndRescueFunctionsWork() public {
        policy.setDecodeFields(uint8(SwapOpType.EXACT_ETH_OUT), 99);
        assertEq(router.decodePackedRisk(1).core.compositeScore, 99);

        tokenIn.mint(address(router), 2e18);
        router.rescueERC20(address(tokenIn), receiver, 2e18);
        assertEq(tokenIn.balanceOf(receiver), 2e18);

        vm.deal(address(router), 1e18);
        uint256 balanceBefore = receiver.balance;
        router.rescueETH(payable(receiver), 1e18);
        assertEq(receiver.balance - balanceBefore, 1e18);
    }
}
