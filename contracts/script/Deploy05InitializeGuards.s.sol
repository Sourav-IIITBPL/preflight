// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {ERC4626VaultGuard} from "../src/guards/ERC4626VaultGuard.sol";
import {SwapV2Guard} from "../src/guards/V2Guards/SwapV2Guard.sol";
import {LiquidityGuard} from "../src/guards/V2Guards/LiquidityV2Guard.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";

contract Deploy05InitializeGuards is BaseDeployScript {
    function run() external {
        address tokenGuard = _envAddress("TOKEN_GUARD_ADDRESS");
        address erc4626VaultGuardProxy = _envAddress("ERC4626_VAULT_GUARD_PROXY_ADDRESS");
        address swapV2GuardProxy = _envAddress("SWAP_V2_GUARD_PROXY_ADDRESS");
        address liquidityV2GuardProxy = _envAddress("LIQUIDITY_V2_GUARD_PROXY_ADDRESS");
        uint256 snapshotBlockInterval = vm.envUint("SNAPSHOT_BLOCK_INTERVAL");

        vm.startBroadcast(_privateKey());
        ERC4626VaultGuard(erc4626VaultGuardProxy).initialize(tokenGuard);
        SwapV2Guard(swapV2GuardProxy).initialize(snapshotBlockInterval, tokenGuard);
        LiquidityGuard(liquidityV2GuardProxy).initialize(tokenGuard);
        vm.stopBroadcast();

        console2.log("Initialized ERC4626VaultGuard proxy:", erc4626VaultGuardProxy);
        console2.log("Initialized SwapV2Guard proxy:", swapV2GuardProxy);
        console2.log("Initialized LiquidityV2Guard proxy:", liquidityV2GuardProxy);
    }
}
