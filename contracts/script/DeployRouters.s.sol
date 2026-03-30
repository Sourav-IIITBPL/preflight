// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {ERC4626Router} from "../src/preflightRouters/ERC4626Router.sol";
import {SwapV2Router} from "../src/preflightRouters/V2Routers/SwapV2Router.sol";
import {LiquidityV2Router} from "../src/preflightRouters/V2Routers/LiquidityV2Router.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";
import {
    ERC4626_VAULT_GUARD_ADDRESS,
    LIQUIDITY_V2_GUARD_ADDRESS,
    ERC4626_RISK_POLICY_ADDRESS,
    LIQUIDITY_V2_RISK_POLICY_ADDRESS,
    SWAP_V2_RISK_POLICY_ADDRESS,
    RISK_REPORT_NFT_ADDRESS,
    BASE_ERC4626_VAULT_GUARD_ADDRESS,
    BASE_LIQUIDITY_V2_GUARD_ADDRESS,
    BASE_RISK_REPORT_NFT_ADDRESS
} from "./constants.s.sol";

contract DeployRouters is BaseDeployScript {
    function run() external returns (address erc4626Router, address swapV2Router, address liquidityV2Router) {
        vm.startBroadcast(_privateKey());
        erc4626Router = address(
            new ERC4626Router(
                BASE_ERC4626_VAULT_GUARD_ADDRESS, ERC4626_RISK_POLICY_ADDRESS, BASE_RISK_REPORT_NFT_ADDRESS
            )
        );
        swapV2Router = address(
            new SwapV2Router(BASE_LIQUIDITY_V2_GUARD_ADDRESS, SWAP_V2_RISK_POLICY_ADDRESS, BASE_RISK_REPORT_NFT_ADDRESS)
        );
        liquidityV2Router = address(
            new LiquidityV2Router(
                BASE_LIQUIDITY_V2_GUARD_ADDRESS, LIQUIDITY_V2_RISK_POLICY_ADDRESS, BASE_RISK_REPORT_NFT_ADDRESS
            )
        );
        vm.stopBroadcast();

        console2.log("ERC4626Router deployed at:", erc4626Router);
        console2.log("SwapV2Router deployed at:", swapV2Router);
        console2.log("LiquidityV2Router deployed at:", liquidityV2Router);
    }
}
