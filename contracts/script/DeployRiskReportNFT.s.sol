// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {RiskReportNFT} from "../src/RiskReportNFT.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";
import {SVG_RENDERER_ADDRESS} from "./constants.sol";

contract DeployRiskReportNFT is BaseDeployScript {
    function run() external returns (address riskReportNFT) {
         vm.startBroadcast(_privateKey());
        RiskReportNFT riskReportNFTImpl = new RiskReportNFT(SVG_RENDERER_ADDRESS);
            vm.stopBroadcast();
            riskReportNFT = address(riskReportNFTImpl);
    
            console2.log("RiskReportNFT deployed at:", riskReportNFT);
    }
}
