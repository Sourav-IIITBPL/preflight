// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// import {LiquidityGuard} from "../../src/guards/V2Guards/LiquidityV2Guard.sol";
// import {MockTokenGuard} from "../mocks/MockTokenGuard.sol";
// import {MockERC20Metadata} from "../mocks/MockERC20Metadata.sol";
// import {MockV2Factory} from "../mocks/MockV2Factory.sol";
// import {MockV2Router} from "../mocks/MockV2Router.sol";
// import {MockV2Pair} from "../mocks/MockV2Pair.sol";

// contract LiquidityV2GuardTest is Test {
//     MockTokenGuard internal tokenGuard;
//     MockERC20Metadata internal tokenA;
//     MockERC20Metadata internal tokenB;
//     MockERC20Metadata internal weth;
//     MockV2Factory internal factory;
//     MockV2Router internal router;
//     MockV2Pair internal pair;
//     LiquidityGuard internal guard;

//     address internal trustedCaller = address(this);
//     address internal user = address(0xBEEF);

//     function setUp() public {
//         tokenGuard = new MockTokenGuard();
//         tokenA = new MockERC20Metadata("Token A", "A", 18);
//         tokenB = new MockERC20Metadata("Token B", "B", 18);
//         weth = new MockERC20Metadata("Wrapped Ether", "WETH", 18);

//         tokenA.setTotalSupply(1_000_000e18);
//         tokenB.setTotalSupply(1_000_000e18);

//         factory = new MockV2Factory();
//         router = new MockV2Router(address(factory), address(weth));
//         pair = new MockV2Pair(address(tokenA), address(tokenB), address(factory));
//         factory.setPair(address(tokenA), address(tokenB), address(pair));

//         pair.setReserves(10_000e18, 10_000e18, 0);
//         pair.setTotalSupply(20_000e18);

//         LiquidityGuard implementation = new LiquidityGuard();
//         bytes memory initData = abi.encodeCall(LiquidityGuard.initialize, (address(tokenGuard)));
//         guard = LiquidityGuard(address(new ERC1967Proxy(address(implementation), initData)));
//     }

//     function test_adminSetters() public {
//         guard.setTrustedRouter(address(router), true);
//         guard.setTrustedCaller(trustedCaller, true);

//         assertTrue(guard.trustedRouters(address(router)));
//         assertTrue(guard.trustedCallers(trustedCaller));

//         vm.expectRevert(bytes("ZERO_ADDRESS"));
//         guard.setTrustedCaller(address(0), true);
//     }

//     function test_storeCheckRequiresTrustedCaller() public {
//         vm.expectRevert(bytes("NOT_AUTHORIZED_CALLER"));
//         guard.storeCheck(
//             address(router),
//             address(tokenA),
//             address(tokenB),
//             1e18,
//             1e18,
//             user,
//             LiquidityGuard.LiquidityOperationType.ADD
//         );
//     }

//     function test_checkLiquidityFlagsPairMissingAndRouterNotTrusted() public {
//         LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
//             user, address(router), address(tokenA), address(weth), 1e18, 1e18, LiquidityGuard.LiquidityOperationType.ADD
//         );

//         assertTrue(result.ROUTER_NOT_TRUSTED);
//         assertTrue(result.PAIR_NOT_EXISTS);
//     }

//     function test_checkLiquidityFlagsZeroLiquidityAndFirstDepositorRisk() public {
//         guard.setTrustedRouter(address(router), true);
//         pair.setReserves(0, 0, 0);

//         LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
//             user,
//             address(router),
//             address(tokenA),
//             address(tokenB),
//             1e18,
//             1e18,
//             LiquidityGuard.LiquidityOperationType.ADD
//         );

//         assertTrue(result.ZERO_LIQUIDITY);
//         assertTrue(result.FIRST_DEPOSITOR_RISK);
//     }

//     function test_checkLiquidityAddFlagsRatioDeviationAndHighImpact() public {
//         guard.setTrustedRouter(address(router), true);

//         LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
//             user,
//             address(router),
//             address(tokenA),
//             address(tokenB),
//             2_000e18,
//             100e18,
//             LiquidityGuard.LiquidityOperationType.ADD
//         );

//         assertTrue(result.AMOUNT_RATIO_DEVIATION);
//         assertTrue(result.HIGH_LP_IMPACT);
//     }

//     function test_checkLiquidityAddFlagsZeroLpOut() public {
//         guard.setTrustedRouter(address(router), true);
//         pair.setReserves(1_000_000e18, 1_000_000e18, 0);
//         pair.setTotalSupply(1_000e18);

//         LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
//             user, address(router), address(tokenA), address(tokenB), 1, 1, LiquidityGuard.LiquidityOperationType.ADD
//         );

//         assertTrue(result.ZERO_LP_OUT);
//     }

//     function test_checkLiquidityRemoveFlagsZeroAmountsOut() public {
//         guard.setTrustedRouter(address(router), true);
//         pair.setReserves(1_000e18, 1_000e18, 0);
//         pair.setTotalSupply(1_000_000_000e18);

//         LiquidityGuard.LiquidityV2GuardResult memory result = guard.checkLiquidity(
//             user,
//             address(router),
//             address(tokenA),
//             address(tokenB),
//             1_000,
//             0,
//             LiquidityGuard.LiquidityOperationType.REMOVE
//         );

//         assertTrue(result.ZERO_AMOUNTS_OUT);
//     }

//     function test_storeGetAndValidateRoundTrip() public {
//         guard.setTrustedRouter(address(router), true);
//         guard.setTrustedCaller(trustedCaller, true);

//         guard.storeCheck(
//             address(router),
//             address(tokenA),
//             address(tokenB),
//             1e18,
//             1e18,
//             user,
//             LiquidityGuard.LiquidityOperationType.ADD
//         );

//         LiquidityGuard.LiquidityV2GuardResult memory result = guard.getStoredCheck(user, address(router));
//         assertFalse(result.ROUTER_NOT_TRUSTED);

//         guard.validateCheck(
//             address(router),
//             address(tokenA),
//             address(tokenB),
//             1e18,
//             1e18,
//             user,
//             LiquidityGuard.LiquidityOperationType.ADD
//         );
//     }

//     function test_validateCheckRevertsWhenStale() public {
//         guard.setTrustedRouter(address(router), true);
//         guard.setTrustedCaller(trustedCaller, true);

//         guard.storeCheck(
//             address(router),
//             address(tokenA),
//             address(tokenB),
//             1e18,
//             1e18,
//             user,
//             LiquidityGuard.LiquidityOperationType.ADD
//         );
//         vm.roll(block.number + 1);

//         vm.expectRevert(bytes("STALE_LIQ_CHECK"));
//         guard.validateCheck(
//             address(router),
//             address(tokenA),
//             address(tokenB),
//             1e18,
//             1e18,
//             user,
//             LiquidityGuard.LiquidityOperationType.ADD
//         );
//     }
// }
