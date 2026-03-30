// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ERC4626VaultGuard} from "../src/guards/ERC4626VaultGuard.sol";
import {SwapV2Guard} from "../src/guards/V2Guards/SwapV2Guard.sol";
import {LiquidityGuard} from "../src/guards/V2Guards/LiquidityV2Guard.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";
import {TOKEN_GUARD_ADDRESS, BASE_TOKEN_GUARD_ADDRESS} from "./constants.s.sol";

contract DeployGuards is BaseDeployScript {
    function run()
        external
        returns (
            address erc4626VaultGuardImplementation,
            //address swapV2GuardImplementation
            address liquidityV2GuardImplementation
        )
    {
        vm.startBroadcast(_privateKey());

        ERC4626VaultGuard erc4626VaultGuardImpl = new ERC4626VaultGuard(BASE_TOKEN_GUARD_ADDRESS);
        //SwapV2Guard swapV2GuardImpl = new SwapV2Guard(1,TOKEN_GUARD_ADDRESS);
        LiquidityGuard liquidityV2GuardImpl = new LiquidityGuard(BASE_TOKEN_GUARD_ADDRESS);

        vm.stopBroadcast();

        erc4626VaultGuardImplementation = address(erc4626VaultGuardImpl);

        //swapV2GuardImplementation = address(swapV2GuardImpl);

        liquidityV2GuardImplementation = address(liquidityV2GuardImpl);

        console2.log("ERC4626VaultGuard implementation:", erc4626VaultGuardImplementation);

        // console2.log("SwapV2Guard implementation:", swapV2GuardImplementation);

        console2.log("LiquidityV2Guard implementation:", liquidityV2GuardImplementation);
    }
}
