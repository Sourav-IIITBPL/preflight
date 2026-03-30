// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

import {TokenGuard} from "../src/guards/lib/TokenGuard.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";

contract DeployTokenGuard is BaseDeployScript {
    function run() external returns (address tokenGuard) {
        bytes memory creationCode = type(TokenGuard).creationCode;

        vm.startBroadcast(_privateKey());
        assembly {
            tokenGuard := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        vm.stopBroadcast();

        require(tokenGuard != address(0), "TOKEN_GUARD_DEPLOY_FAILED");
        console2.log("TokenGuard deployed at:", tokenGuard);
    }
}
