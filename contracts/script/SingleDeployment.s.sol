// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";

// Import all contracts
import {TokenGuard} from "../src/guards/lib/TokenGuard.sol";
import {SVGRenderer} from "../src/nftReport/SVGRenderer.sol";
import {RiskReportNFT} from "../src/nftReport/RiskReportNFT.sol";

import {ERC4626VaultGuard} from "../src/guards/ERC4626VaultGuard.sol";
import {SwapV2Guard} from "../src/guards/V2Guards/SwapV2Guard.sol";
import {LiquidityGuard} from "../src/guards/V2Guards/LiquidityV2Guard.sol";

import {ERC4626RiskPolicy} from "../src/riskpolicies/ERC4626RiskPolicy.sol";
import {SwapV2RiskPolicy} from "../src/riskpolicies/SwapV2RiskPolicy.sol";
import {LiquidityV2RiskPolicy} from "../src/riskpolicies/LiquidityV2RiskPolicy.sol";

import {ERC4626Router} from "../src/preflightRouters/ERC4626Router.sol";
import {SwapV2Router} from "../src/preflightRouters/V2Routers/SwapV2Router.sol";
import {LiquidityV2Router} from "../src/preflightRouters/V2Routers/LiquidityV2Router.sol";

/**
 * @title SingleDeployment
 * @notice A single deployment script that deploys the entire codebase and dynamically links them.
 */
contract SingleDeployment is BaseDeployScript {
    function run() external {
        vm.startBroadcast(_privateKey());

        console2.log("--- Starting Deployment ---");

        // 1. Deploy TokenGuard
        address tokenGuard;
        bytes memory creationCode = type(TokenGuard).creationCode;
        assembly {
            tokenGuard := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(tokenGuard != address(0), "TOKEN_GUARD_DEPLOY_FAILED");
        console2.log("TokenGuard deployed at: ", tokenGuard);

        // 2. Deploy SVGRenderer
        SVGRenderer svgRenderer = new SVGRenderer();
        console2.log("SVGRenderer deployed at:", address(svgRenderer));

        // 3. Deploy RiskReportNFT
        RiskReportNFT riskReportNFT = new RiskReportNFT(address(svgRenderer));
        console2.log("RiskReportNFT deployed at:", address(riskReportNFT));

        // 4. Deploy Guards
        ERC4626VaultGuard erc4626VaultGuard = new ERC4626VaultGuard(tokenGuard);
        SwapV2Guard swapV2Guard = new SwapV2Guard(1, tokenGuard); // 1 is _snapshotBlockInterval
        LiquidityGuard liquidityV2Guard = new LiquidityGuard(tokenGuard);

        console2.log("ERC4626VaultGuard deployed at:", address(erc4626VaultGuard));
        console2.log("SwapV2Guard deployed at:      ", address(swapV2Guard));
        console2.log("LiquidityV2Guard deployed at: ", address(liquidityV2Guard));

        // 5. Deploy Risk Policies
        ERC4626RiskPolicy erc4626RiskPolicy = new ERC4626RiskPolicy();
        SwapV2RiskPolicy swapV2RiskPolicy = new SwapV2RiskPolicy();
        LiquidityV2RiskPolicy liquidityV2RiskPolicy = new LiquidityV2RiskPolicy();

        console2.log("ERC4626RiskPolicy deployed at:", address(erc4626RiskPolicy));
        console2.log("SwapV2RiskPolicy deployed at: ", address(swapV2RiskPolicy));
        console2.log("LiquidityV2RiskPolicy deployed at:", address(liquidityV2RiskPolicy));

        // 6. Deploy Routers
        ERC4626Router erc4626Router =
            new ERC4626Router(address(erc4626VaultGuard), address(erc4626RiskPolicy), address(riskReportNFT));

        SwapV2Router swapV2Router =
            new SwapV2Router(address(swapV2Guard), address(swapV2RiskPolicy), address(riskReportNFT));

        LiquidityV2Router liquidityV2Router =
            new LiquidityV2Router(address(liquidityV2Guard), address(liquidityV2RiskPolicy), address(riskReportNFT));

        console2.log("ERC4626Router deployed at:    ", address(erc4626Router));
        console2.log("SwapV2Router deployed at:     ", address(swapV2Router));
        console2.log("LiquidityV2Router deployed at:", address(liquidityV2Router));

        console2.log("--- Deployment Completed ---");

        vm.stopBroadcast();
    }
}
