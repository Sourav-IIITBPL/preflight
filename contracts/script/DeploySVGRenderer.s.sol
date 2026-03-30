// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";
import {SVGRenderer} from "../src/nftReport/SVGRenderer.sol";

/**
 * @title DeploySVGRenderer
 * @notice Script to deploy the SVGRenderer contract.
 */
contract DeploySVGRenderer is BaseDeployScript {
    function run() external returns (address svgRenderer) {
        vm.startBroadcast(_privateKey());

        SVGRenderer renderer = new SVGRenderer();

        vm.stopBroadcast();

        svgRenderer = address(renderer);
        console2.log("SVGRenderer deployed at:", svgRenderer);
    }
}
