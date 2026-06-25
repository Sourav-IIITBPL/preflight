// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {SwapV2Guard, SwapV2GuardResult} from "../../src/guards/V2Guards/SwapV2Guard.sol";
import {MockTokenGuard} from "../mocks/MockTokenGuard.sol";
import {MockERC20Metadata} from "../mocks/MockERC20Metadata.sol";
import {MockV2Factory} from "../mocks/MockV2Factory.sol";
import {MockV2Router} from "../mocks/MockV2Router.sol";
import {MockV2Pair} from "../mocks/MockV2Pair.sol";

contract SwapV2GuardTest is Test {
    MockTokenGuard internal tokenGuard;
    MockERC20Metadata internal tokenA;
    MockERC20Metadata internal tokenB;
    MockERC20Metadata internal tokenC;
    MockERC20Metadata internal tokenD;
    MockERC20Metadata internal tokenE;
    MockERC20Metadata internal weth;
    MockV2Factory internal factory;
    MockV2Router internal router;
    MockV2Pair internal pairAB;
    MockV2Pair internal pairBC;
    MockV2Pair internal pairCD;
    MockV2Pair internal pairDE;
    SwapV2Guard internal guard;

    address internal preflightCaller = address(this);
    address internal user = address(0xBEEF);
    address internal forwarder = address(0xF0);

    function setUp() public {
        tokenGuard = new MockTokenGuard();
        tokenA = new MockERC20Metadata("Token A", "A", 18);
        tokenB = new MockERC20Metadata("Token B", "B", 18);
        tokenC = new MockERC20Metadata("Token C", "C", 18);
        tokenD = new MockERC20Metadata("Token D", "D", 18);
        tokenE = new MockERC20Metadata("Token E", "E", 18);
        weth = new MockERC20Metadata("Wrapped Ether", "WETH", 18);

        tokenA.setTotalSupply(1_000_000e18);
        tokenB.setTotalSupply(1_000_000e18);
        tokenC.setTotalSupply(1_000_000e18);
        tokenD.setTotalSupply(1_000_000e18);
        tokenE.setTotalSupply(1_000_000e18);

        factory = new MockV2Factory();
        router = new MockV2Router(address(factory), address(weth));
        pairAB = new MockV2Pair(address(tokenA), address(tokenB), address(factory));
        pairBC = new MockV2Pair(address(tokenB), address(tokenC), address(factory));
        pairCD = new MockV2Pair(address(tokenC), address(tokenD), address(factory));
        pairDE = new MockV2Pair(address(tokenD), address(tokenE), address(factory));

        factory.setPair(address(tokenA), address(tokenB), address(pairAB));
        factory.setPair(address(tokenB), address(tokenC), address(pairBC));
        factory.setPair(address(tokenC), address(tokenD), address(pairCD));
        factory.setPair(address(tokenD), address(tokenE), address(pairDE));

        pairAB.setReserves(2_000e18, 2_000e18, 0);
        pairAB.setTotalSupply(10_000e18);
        pairBC.setReserves(2_000e18, 2_000e18, 0);
        pairBC.setTotalSupply(10_000e18);
        pairCD.setReserves(2_000e18, 2_000e18, 0);
        pairCD.setTotalSupply(10_000e18);
        pairDE.setReserves(2_000e18, 2_000e18, 0);
        pairDE.setTotalSupply(10_000e18);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 9e17;
        router.setAmountsOut(amounts);
        router.setAmountsIn(amounts);

        guard = new SwapV2Guard(5, address(tokenGuard));
    }

    function test_adminSettersAndTrackedPoolLifecycle() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedFactory(address(factory), true);
        guard.setPreflightCaller(preflightCaller, true);
        guard.setAutomationForwarder(forwarder);

        assertTrue(guard.trustedRouters(address(router)));
        assertTrue(guard.trustedFactories(address(factory)));
        assertTrue(guard.authorizedPreflightCallers(preflightCaller));
        assertEq(guard.automationForwarder(), forwarder);

        guard.addTrackedPool(address(pairAB));
        assertEq(guard.trackedPoolsLength(), 1);

        guard.removeTrackedPool(address(pairAB));
        assertEq(guard.trackedPoolsLength(), 0);
    }

    function test_removeTrackedPoolRevertsIfMissing() public {
        vm.expectRevert("POOL_NOT_TRACKED");
        guard.removeTrackedPool(address(0xDEAD));
    }

    function test_swapCheckFlagsDeepMultihop() public {
        address[] memory path = new address[](6);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);
        path[3] = address(tokenD);
        path[4] = address(tokenE);
        path[5] = address(tokenA); // Just to fill length

        (SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);
        assertTrue(result.DEEP_MULTIHOP);
    }

    function test_swapCheckFlagsCircleRoute() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        (SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);
        assertTrue(result.DUPLICATE_TOKEN_IN_PATH);
    }

    function test_swapCheckFlagsSevereImbalance() public {
        guard.setTrustedRouter(address(router), true);
        // r0 = 2000, r1 = 10 -> r1 < 1% of r0 (20)
        pairAB.setReserves(2000e18, 10e18, uint32(block.timestamp - 1));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        (SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);
        assertTrue(result.SEVERE_IMBALANCE);
    }

    function test_swapCheckFlagsPoolTooNew() public {
        guard.setTrustedRouter(address(router), true);
        guard.addTrackedPool(address(pairAB)); // sets firstSeenBlock

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        (SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);
        assertTrue(result.POOL_TOO_NEW);
    }

    function test_swapCheckFlagsKInvariantBroken() public {
        guard.setTrustedRouter(address(router), true);
        pairAB.setReserves(100e18, 100e18, uint32(block.timestamp));
        pairAB.setKLast(10001e36); // current K = 10000e36 < kLast

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        (SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);
        assertTrue(result.K_INVARIANT_BROKEN);
    }

    function test_swapCheckFlagsFlashloanRisk() public {
        guard.setTrustedRouter(address(router), true);
        pairAB.setReserves(100e18, 100e18, uint32(block.timestamp)); // timestamp matches current

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        (SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);
        assertTrue(result.FLASHLOAN_RISK);
    }

    function test_swapCheckFlagsPriceManipulated() public {
        guard.setTrustedRouter(address(router), true);
        guard.addTrackedPool(address(pairAB));

        // Initial state: r0=2000, r1=2000 -> price=1. cumulativePrice=0. timestamp=1
        vm.warp(block.timestamp + 100);
        // Move spot: r0=2000, r1=2500 -> spot price = 1.25 (25% up)
        pairAB.setReserves(2000e18, 2500e18, uint32(block.timestamp - 50));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        (SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);
        assertTrue(result.PRICE_MANIPULATED);
    }

    function test_getTWAPReturnsZeroForUntrackedPool() public {
        (uint256 t0, uint256 t1, uint32 w) = guard.getTWAP(address(0xDEAD));
        assertEq(t0, 0);
        assertEq(t1, 0);
        assertEq(w, 0);
    }

    function test_performUpkeepRevertsForUnauthorized() public {
        vm.expectRevert();
        guard.performUpkeep("");
    }

    function test_storeGetAndValidateRoundTrip() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedFactory(address(factory), true);
        guard.setPreflightCaller(preflightCaller, true);
        guard.addTrackedPool(address(pairAB));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        guard.storeSwapCheck(address(router), path, 1e18, true, user);

        (SwapV2GuardResult memory result, uint256 amountOut) = guard.getStoredCheck(user, address(router));
        assertFalse(result.ROUTER_NOT_TRUSTED);
        assertEq(amountOut, 9e17);

        guard.validateSwapCheck(address(router), path, 1e18, true, user);
    }

    function test_validateSwapCheckRevertsWhenStale() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedFactory(address(factory), true);
        guard.setPreflightCaller(preflightCaller, true);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        guard.storeSwapCheck(address(router), path, 1e18, true, user);
        vm.roll(block.number + 16);

        vm.expectRevert(bytes("STALE_CHECK"));
        guard.validateSwapCheck(address(router), path, 1e18, true, user);
    }

    function test_validateSwapCheckRevertsOnMismatchedAmount() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedFactory(address(factory), true);
        guard.setPreflightCaller(preflightCaller, true);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        guard.storeSwapCheck(address(router), path, 1e18, true, user);

        uint256[] memory amountsOut2 = new uint256[](2);
        amountsOut2[0] = 2e18;
        amountsOut2[1] = 18e17;
        router.setAmountsOut(amountsOut2);
        vm.expectRevert(bytes("SWAP_STATE_CHANGED"));
        guard.validateSwapCheck(address(router), path, 2e18, true, user);
    }

    function test_validateSwapCheckRevertsOnMismatchedDirection() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedFactory(address(factory), true);
        guard.setPreflightCaller(preflightCaller, true);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        guard.storeSwapCheck(address(router), path, 1e18, true, user);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 11e17;
        amountsIn[1] = 1e18;
        router.setAmountsIn(amountsIn);
        vm.expectRevert(bytes("SWAP_STATE_CHANGED"));
        guard.validateSwapCheck(address(router), path, 1e18, false, user);
    }

    function test_validateSwapCheckRevertsOnMismatchedPath() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedFactory(address(factory), true);
        guard.setPreflightCaller(preflightCaller, true);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        guard.storeSwapCheck(address(router), path, 1e18, true, user);

        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenC);

        uint256[] memory amountsOut2 = new uint256[](2);
        amountsOut2[0] = 1e18;
        amountsOut2[1] = 5e17;
        router.setAmountsOut(amountsOut2);

        vm.expectRevert(bytes("SWAP_STATE_CHANGED"));
        guard.validateSwapCheck(address(router), path2, 1e18, true, user);
    }

    function test_checkUpkeepAndPerformUpkeepRecordsSnapshot() public {
        guard.addTrackedPool(address(pairAB));
        (,,, uint256 initialLastBlock) = guard.snapshots(address(pairAB));

        vm.roll(block.number + 6);
        (bool upkeepNeeded, bytes memory performData) = guard.checkUpkeep("");
        assertTrue(upkeepNeeded);

        guard.setAutomationForwarder(forwarder);
        vm.prank(forwarder);
        guard.performUpkeep(performData);

        (,,, uint256 updatedLastBlock) = guard.snapshots(address(pairAB));
        assertGt(updatedLastBlock, initialLastBlock);
    }
}
