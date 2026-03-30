// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {RiskReportNFT} from "../src/RiskReportNFT.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";

contract Deploy02RiskReportNFT is BaseDeployScript {
    function run() external returns (address riskReportNFT) {
        vm.startBroadcast(_privateKey());
        riskReportNFT = address(new RiskReportNFT());
        vm.stopBroadcast();

        console2.log("RiskReportNFT deployed at:", riskReportNFT);
    }
}
