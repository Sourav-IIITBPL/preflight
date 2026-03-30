// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ERC4626VaultGuard} from "../src/guards/ERC4626VaultGuard.sol";
import {SwapV2Guard} from "../src/guards/V2Guards/SwapV2Guard.sol";
import {LiquidityGuard} from "../src/guards/V2Guards/LiquidityV2Guard.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";

contract Deploy04GuardsAndProxies is BaseDeployScript {
    function run()
        external
        returns (
            address erc4626VaultGuardImplementation,
            address erc4626VaultGuardProxy,
            address swapV2GuardImplementation,
            address swapV2GuardProxy,
            address liquidityV2GuardImplementation,
            address liquidityV2GuardProxy
        )
    {
        vm.startBroadcast(_privateKey());

        ERC4626VaultGuard erc4626VaultGuardImpl = new ERC4626VaultGuard();
        SwapV2Guard swapV2GuardImpl = new SwapV2Guard();
        LiquidityGuard liquidityV2GuardImpl = new LiquidityGuard();

        ERC1967Proxy erc4626Proxy = new ERC1967Proxy(address(erc4626VaultGuardImpl), bytes(""));
        ERC1967Proxy swapProxy = new ERC1967Proxy(address(swapV2GuardImpl), bytes(""));
        ERC1967Proxy liquidityProxy = new ERC1967Proxy(address(liquidityV2GuardImpl), bytes(""));

        vm.stopBroadcast();

        erc4626VaultGuardImplementation = address(erc4626VaultGuardImpl);
        erc4626VaultGuardProxy = address(erc4626Proxy);
        swapV2GuardImplementation = address(swapV2GuardImpl);
        swapV2GuardProxy = address(swapProxy);
        liquidityV2GuardImplementation = address(liquidityV2GuardImpl);
        liquidityV2GuardProxy = address(liquidityProxy);

        console2.log("ERC4626VaultGuard implementation:", erc4626VaultGuardImplementation);
        console2.log("ERC4626VaultGuard proxy:", erc4626VaultGuardProxy);
        console2.log("SwapV2Guard implementation:", swapV2GuardImplementation);
        console2.log("SwapV2Guard proxy:", swapV2GuardProxy);
        console2.log("LiquidityV2Guard implementation:", liquidityV2GuardImplementation);
        console2.log("LiquidityV2Guard proxy:", liquidityV2GuardProxy);
    }
}
