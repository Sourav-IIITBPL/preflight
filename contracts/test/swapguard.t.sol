// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/guards/SwapGuard.sol";

/*//////////////////////////////////////////////////////////////
    Mock AMM Pair
//////////////////////////////////////////////////////////////*/

contract MockPair {
    uint112 r0;
    uint112 r1;

    function setReserves(uint112 _r0, uint112 _r1) external {
        r0 = _r0;
        r1 = _r1;
    }

    function getReserves()
        external
        view
        returns (uint112, uint112, uint32)
    {
        return (r0, r1, uint32(block.timestamp));
    }
}

contract SwapGuardTest is Test {
    SwapGuard guard;
    MockPair pair;

    function setUp() public {
        guard = new SwapGuard();
        pair = new MockPair();

        pair.setReserves(100 ether, 100 ether);
    }

    function test_safeSwap() public {
        (SwapGuard.RiskLevel level, ) =
            guard.checkSwap(
                address(pair),
                100 ether,
                100 ether
            );

        assertEq(uint256(level), uint256(SwapGuard.RiskLevel.SAFE));
    }

    function test_blocksReserveManipulation() public {
        pair.setReserves(100 ether, 10 ether);

        (SwapGuard.RiskLevel level, ) =
            guard.checkSwap(
                address(pair),
                100 ether,
                100 ether
            );

        assertEq(uint256(level), uint256(SwapGuard.RiskLevel.BLOCK));
    }

    function test_warnsOnModerateDeviation() public {
        pair.setReserves(100 ether, 97 ether);

        (SwapGuard.RiskLevel level, ) =
            guard.checkSwap(
                address(pair),
                100 ether,
                100 ether
            );

        assertEq(uint256(level), uint256(SwapGuard.RiskLevel.WARNING));
    }

    function test_lowLiquidityWarning() public {
        pair.setReserves(1 ether, 1 ether);

        (SwapGuard.RiskLevel level, ) =
            guard.checkSwap(
                address(pair),
                1 ether,
                1 ether
            );

        assertEq(uint256(level), uint256(SwapGuard.RiskLevel.WARNING));
    }
}
