// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

abstract contract BaseDeployScript is Script {
    function _privateKey() internal view returns (uint256) {
        return vm.envUint("PRIVATE_KEY");
    }

    function _envAddress(string memory key) internal view returns (address value) {
        value = vm.envAddress(key);
        require(value != address(0), string.concat(key, " is zero"));
    }
}
