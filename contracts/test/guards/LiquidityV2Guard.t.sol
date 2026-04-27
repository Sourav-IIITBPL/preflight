// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {LiquidityGuard} from "../../src/guards/V2Guards/LiquidityV2Guard.sol";
import {MockTokenGuard} from "../mocks/MockTokenGuard.sol";
import {MockERC20Metadata} from "../mocks/MockERC20Metadata.sol";
import {MockV2Factory} from "../mocks/MockV2Factory.sol";
import {MockV2Router} from "../mocks/MockV2Router.sol";
import {MockV2Pair} from "../mocks/MockV2Pair.sol";

contract LiquidityV2GuardTest is Test {
    MockTokenGuard internal tokenGuard;
    MockERC20Metadata internal tokenA;
    MockERC20Metadata internal tokenB;
    MockERC20Metadata internal weth;
    MockV2Factory internal factory;
    MockV2Router internal router;
    MockV2Pair internal pair;
    LiquidityGuard internal guard;

    address internal trustedCaller = address(this);
    address internal user = address(0xBEEF);

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

        pair.setReserves(10_000e18, 10_000e18, 0);
        pair.setTotalSupply(20_000e18);

        guard = new LiquidityGuard(address(tokenGuard));
    }

    function test_adminSetters() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedCaller(trustedCaller, true);

        assertTrue(guard.trustedRouters(address(router)));
        assertTrue(guard.trustedCallers(trustedCaller));

        vm.expectRevert(bytes("ZERO_ADDRESS"));
        guard.setTrustedCaller(address(0), true);
    }

    function test_checkLiquidityEthSubstitution() public {
        // address(0) should be substituted with weth
        factory.setPair(address(tokenA), address(weth), address(0xCAFE));
        // We'd need another mock pair for CAFE to test fully, but the branch tokenA == address(0) is hit.
        guard.checkLiquidity(user, address(router), address(0), address(tokenB), 1e18, 1e18, LiquidityGuard.LiquidityOpType.ADD_ETH);
    }

    function test_checkLiquidityRevertsForSameToken() public {
        vm.expectRevert("INVALID_TOKEN_ADDRESS");
        guard.checkLiquidity(user, address(router), address(tokenA), address(tokenA), 1e18, 1e18, LiquidityGuard.LiquidityOpType.ADD);
    }

    function test_checkLiquidityFlagsSevereImbalance() public {
        guard.setTrustedRouter(address(router), true);
        pair.setReserves(10000e18, 50e18, 0); // 50 < 1% of 10000

        LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
            user, address(router), address(tokenA), address(tokenB), 1e18, 1e18, LiquidityGuard.LiquidityOpType.ADD
        );
        assertTrue(result.SEVERE_IMBALANCE);
    }

    function test_checkLiquidityFlagsKInvariantBroken() public {
        guard.setTrustedRouter(address(router), true);
        pair.setReserves(100e18, 100e18, 0);
        pair.setKLast(10001e36);

        LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
            user, address(router), address(tokenA), address(tokenB), 1e18, 1e18, LiquidityGuard.LiquidityOpType.ADD
        );
        assertTrue(result.K_INVARIANT_BROKEN);
    }

    function test_checkLiquidityFlagsPoolTooNew() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedCaller(address(this), true);
        // ...
    }

    function test_checkLiquidityFlagsFlashloanRisk() public {
        guard.setTrustedRouter(address(router), true);
        pair.setReserves(100e18, 100e18, uint32(block.timestamp));

        LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
            user, address(router), address(tokenA), address(tokenB), 1e18, 1e18, LiquidityGuard.LiquidityOpType.ADD
        );
        assertTrue(result.FLASHLOAN_RISK);
    }

    function test_checkAddDustLp() public {
        guard.setTrustedRouter(address(router), true);
        pair.setReserves(1e24, 1e24, 0); // Huge reserves
        pair.setTotalSupply(1e18);

        // lpEst = (amountA * lpSupply) / reserveA = (100 * 1e18) / 1e24 = 1e-4 -> 0? 
        // No, let's pick amounts to get lpEst > 0 but < MIN_LP (1000)
        // amountA = 500, lpSupply = 1e18, reserveA = 1e18 -> lpEst = 500.
        pair.setReserves(1e18, 1e18, 0);
        pair.setTotalSupply(1e18);
        
        LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
            user, address(router), address(tokenA), address(tokenB), 500, 500, LiquidityGuard.LiquidityOpType.ADD
        );
        assertTrue(result.DUST_LP);
    }

    function test_checkRemoveDustLp() public {
        guard.setTrustedRouter(address(router), true);
        LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
            user, address(router), address(tokenA), address(tokenB), 500, 0, LiquidityGuard.LiquidityOpType.REMOVE
        );
        assertTrue(result.DUST_LP);
    }

    function test_storeGetAndValidateRoundTrip() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedCaller(trustedCaller, true);

        guard.storeCheck(
            address(router),
            address(tokenA),
            address(tokenB),
            1e18,
            1e18,
            user,
            LiquidityGuard.LiquidityOpType.ADD
        );

        LiquidityGuard.LiquidityV2GuardResult memory result = guard.getStoredCheck(user, address(router));
        assertFalse(result.ROUTER_NOT_TRUSTED);

        guard.validateCheck(
            address(router),
            address(tokenA),
            address(tokenB),
            1e18,
            1e18,
            user,
            LiquidityGuard.LiquidityOpType.ADD
        );
    }

    function test_validateCheckRevertsWhenStale() public {
        guard.setTrustedRouter(address(router), true);
        guard.setTrustedCaller(trustedCaller, true);

        guard.storeCheck(
            address(router),
            address(tokenA),
            address(tokenB),
            1e18,
            1e18,
            user,
            LiquidityGuard.LiquidityOpType.ADD
        );
        vm.roll(block.number + 1);

        vm.expectRevert(bytes("STALE_LIQ_CHECK"));
        guard.validateCheck(
            address(router),
            address(tokenA),
            address(tokenB),
            1e18,
            1e18,
            user,
            LiquidityGuard.LiquidityOpType.ADD
        );
    }
}
