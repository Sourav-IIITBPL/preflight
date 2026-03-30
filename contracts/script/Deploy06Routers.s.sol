// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {ERC4626Router} from "../src/preflightRouters/ERC4626Router.sol";
import {SwapV2Router} from "../src/preflightRouters/V2Routers/SwapV2Router.sol";
import {LiquidityV2Router} from "../src/preflightRouters/V2Routers/LiquidityV2Router.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";

contract Deploy06Routers is BaseDeployScript {
    function run() external returns (address erc4626Router, address swapV2Router, address liquidityV2Router) {
        address riskReportNFT = _envAddress("RISK_REPORT_NFT_ADDRESS");

        address erc4626VaultGuardProxy = _envAddress("ERC4626_VAULT_GUARD_PROXY_ADDRESS");
        address erc4626RiskPolicy = _envAddress("ERC4626_RISK_POLICY_ADDRESS");

        address swapV2GuardProxy = _envAddress("SWAP_V2_GUARD_PROXY_ADDRESS");
        address swapV2RiskPolicy = _envAddress("SWAP_V2_RISK_POLICY_ADDRESS");

        address liquidityV2GuardProxy = _envAddress("LIQUIDITY_V2_GUARD_PROXY_ADDRESS");
        address liquidityV2RiskPolicy = _envAddress("LIQUIDITY_V2_RISK_POLICY_ADDRESS");

        vm.startBroadcast(_privateKey());
        erc4626Router = address(new ERC4626Router(erc4626VaultGuardProxy, erc4626RiskPolicy, riskReportNFT));
        swapV2Router = address(new SwapV2Router(swapV2GuardProxy, swapV2RiskPolicy, riskReportNFT));
        liquidityV2Router =
            address(new LiquidityV2Router(liquidityV2GuardProxy, liquidityV2RiskPolicy, riskReportNFT));
        vm.stopBroadcast();

        console2.log("ERC4626Router deployed at:", erc4626Router);
        console2.log("SwapV2Router deployed at:", swapV2Router);
        console2.log("LiquidityV2Router deployed at:", liquidityV2Router);
    }
}
