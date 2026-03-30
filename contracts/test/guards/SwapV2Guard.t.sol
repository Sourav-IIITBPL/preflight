// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SwapV2Guard} from "../../src/guards/V2Guards/SwapV2Guard.sol";
import {MockTokenGuard} from "../mocks/MockTokenGuard.sol";
import {MockERC20Metadata} from "../mocks/MockERC20Metadata.sol";
import {MockV2Factory} from "../mocks/MockV2Factory.sol";
import {MockV2Router} from "../mocks/MockV2Router.sol";
import {MockV2Pair} from "../mocks/MockV2Pair.sol";

contract SwapV2GuardTest is Test {
    MockTokenGuard internal tokenGuard;
    MockERC20Metadata internal tokenA;
    MockERC20Metadata internal tokenB;
    MockERC20Metadata internal weth;
    MockV2Factory internal factory;
    MockV2Router internal router;
    MockV2Pair internal pair;
    SwapV2Guard internal guard;

    address internal preflightCaller = address(this);
    address internal user = address(0xBEEF);
    address internal forwarder = address(0xF0);

    function setUp() public {
        tokenGuard = new MockTokenGuard();
        tokenA = new MockERC20Metadata("Token A", "A", 18);
        tokenB = new MockERC20Metadata("Token B", "B", 18);
        weth = new MockERC20Metadata("Wrapped Ether", "WETH", 18);

        tokenA.setTotalSupply(1_000_000e18);
        tokenB.setTotalSupply(1_000_000e18);

        factory = new MockV2Factory();
        router = new MockV2Router(address(factory), address(weth));
        pair = new MockV2Pair(address(tokenA), address(tokenB), address(factory));

        factory.setPair(address(tokenA), address(tokenB), address(pair));
        pair.setReserves(2_000e18, 2_000e18, 0);
        pair.setTotalSupply(10_000e18);
        pair.setCumulatives(0, 0);

        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[0] = 1e18;
        amountsOut[1] = 9e17;
        router.setAmountsOut(amountsOut);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 11e17;
        amountsIn[1] = 1e18;
        router.setAmountsIn(amountsIn);

        SwapV2Guard implementation = new SwapV2Guard();
        bytes memory initData = abi.encodeCall(SwapV2Guard.initialize, (5, address(tokenGuard)));
        guard = SwapV2Guard(address(new ERC1967Proxy(address(implementation), initData)));
    }

    function test_initializeWithZeroIntervalDefaultsToOne() public {
        SwapV2Guard implementation = new SwapV2Guard();
        bytes memory initData = abi.encodeCall(SwapV2Guard.initialize, (0, address(tokenGuard)));
        SwapV2Guard localGuard = SwapV2Guard(address(new ERC1967Proxy(address(implementation), initData)));

        assertEq(localGuard.snapshotBlockInterval(), 1);
    }

    function test_initializeCannotBeCalledTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        guard.initialize(10, address(tokenGuard));
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

        guard.addTrackedPool(address(pair));
        assertEq(guard.trackedPoolsLength(), 1);

        guard.removeTrackedPool(address(pair));
        assertEq(guard.trackedPoolsLength(), 0);
    }

    function test_onlyOwnerCanCallSetters() public {
        address nonOwner = address(0xBAD);
        vm.startPrank(nonOwner);

        vm.expectRevert("Ownable: caller is not the owner");
        guard.setSnapshotBlockInterval(10);

        vm.expectRevert("Ownable: caller is not the owner");
        guard.setTrustedRouter(address(router), true);

        vm.expectRevert("Ownable: caller is not the owner");
        guard.setTrustedFactory(address(factory), true);

        vm.expectRevert("Ownable: caller is not the owner");
        guard.setAutomationForwarder(forwarder);

        vm.expectRevert("Ownable: caller is not the owner");
        guard.setPreflightCaller(preflightCaller, true);

        vm.expectRevert("Ownable: caller is not the owner");
        guard.addTrackedPool(address(pair));

        vm.expectRevert("Ownable: caller is not the owner");
        guard.removeTrackedPool(address(pair));

        vm.expectRevert("Ownable: caller is not the owner");
        guard.setTokenGuard(address(0x123));

        vm.stopPrank();
    }

    function test_storeSwapCheckRequiresAuthorizedCaller() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert(bytes("NOT_AUTHORIZED_PREFLIGHT_CALLER"));
        guard.storeSwapCheck(address(router), path, 1e18, true, user);
    }

    function test_swapCheckFlagsForUntrustedRouterFactoryAndDuplicatePath() public {
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenA);

        (SwapV2Guard.SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);

        assertTrue(result.ROUTER_NOT_TRUSTED);
        assertTrue(result.FACTORY_NOT_TRUSTED);
        assertTrue(result.DUPLICATE_TOKEN_IN_PATH);
    }

    function test_swapCheckFlagsPoolMissing() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(weth);

        (SwapV2Guard.SwapV2GuardResult memory result,) = guard.swapCheckV2(address(router), path, 1e18, true);
        assertTrue(result.POOL_NOT_EXISTS);
    }

    function test_storeGetAndValidateRoundTrip() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedFactory(address(factory), true);
        guard.setPreflightCaller(preflightCaller, true);
        guard.addTrackedPool(address(pair));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        guard.storeSwapCheck(address(router), path, 1e18, true, user);

        (SwapV2Guard.SwapV2GuardResult memory result, uint256 amountOut) = guard.getStoredCheck(user, address(router));
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
        vm.roll(block.number + 1);

        vm.expectRevert(bytes("STALE_CHECK"));
        guard.validateSwapCheck(address(router), path, 1e18, true, user);
    }

    function test_validateSwapCheckRevertsOnMismatchedParameters() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedFactory(address(factory), true);
        guard.setPreflightCaller(preflightCaller, true);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        guard.storeSwapCheck(address(router), path, 1e18, true, user);

        // Mismatched amount
        vm.expectRevert(bytes("FINGERPRINT_MISMATCH"));
        guard.validateSwapCheck(address(router), path, 2e18, true, user);

        // Mismatched direction
        vm.expectRevert(bytes("FINGERPRINT_MISMATCH"));
        guard.validateSwapCheck(address(router), path, 1e18, false, user);

        // Mismatched path
        address[] memory path2 = new address[](2);
        path2[0] = address(tokenB);
        path2[1] = address(tokenA);
        vm.expectRevert(bytes("FINGERPRINT_MISMATCH"));
        guard.validateSwapCheck(address(router), path2, 1e18, true, user);
    }

    function test_checkUpkeepAndPerformUpkeepRecordsSnapshot() public {
        guard.addTrackedPool(address(pair));
        (, , , uint256 initialLastBlock) = guard.snapshots(address(pair));

        vm.roll(block.number + 6);
        (bool upkeepNeeded, bytes memory performData) = guard.checkUpkeep("");
        assertTrue(upkeepNeeded);

        guard.setAutomationForwarder(forwarder);
        vm.prank(forwarder);
        guard.performUpkeep(performData);

        (, , , uint256 updatedLastBlock) = guard.snapshots(address(pair));
        assertGt(updatedLastBlock, initialLastBlock);
    }
}
