// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {ERC4626RiskPolicy} from "../src/riskpolicies/ERC4626RiskPolicy.sol";
import {SwapV2RiskPolicy} from "../src/riskpolicies/SwapV2RiskPolicy.sol";
import {LiquidityV2RiskPolicy} from "../src/riskpolicies/LiquidityV2RiskPolicy.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";

contract Deploy03RiskPolicies is BaseDeployScript {
    function run()
        external
        returns (address erc4626RiskPolicy, address swapV2RiskPolicy, address liquidityV2RiskPolicy)
    {
        vm.startBroadcast(_privateKey());
        erc4626RiskPolicy = address(new ERC4626RiskPolicy());
        swapV2RiskPolicy = address(new SwapV2RiskPolicy());
        liquidityV2RiskPolicy = address(new LiquidityV2RiskPolicy());
        vm.stopBroadcast();

        console2.log("ERC4626RiskPolicy deployed at:", erc4626RiskPolicy);
        console2.log("SwapV2RiskPolicy deployed at:", swapV2RiskPolicy);
        console2.log("LiquidityV2RiskPolicy deployed at:", liquidityV2RiskPolicy);
    }
}
