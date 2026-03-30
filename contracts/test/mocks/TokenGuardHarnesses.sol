// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";

import {TokenGuard} from "../../src/guards/lib/TokenGuard.sol";
import {TokenGuardResult} from "../../src/guards/interfaces/ITokenGuard.sol";

contract TokenGuardHarness {
    function check(address token) external view returns (TokenGuardResult memory) {
        return TokenGuard.checkToken(token);
    }
}

contract CleanTokenSample {
    function name() external pure returns (string memory) {
        return "Clean";
    }

    function symbol() external pure returns (string memory) {
        return "CLN";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external pure returns (uint256) {
        return 2_000_000e18;
    }
}

contract FeatureRichTokenSample {
    bytes32 internal constant SELECTOR_MARKERS =
        0xfe575a870a714e57f3b7b24e5b7d3b4599a0c2b840c10f1942966c683644e515;

    function name() external pure returns (string memory) {
        return "Feature";
    }

    function symbol() external pure returns (string memory) {
        return "FTR";
    }

    function decimals() external pure returns (uint8) {
        return 19;
    }

    function totalSupply() external pure returns (uint256) {
        return 100;
    }

    function owner() external pure returns (address) {
        return address(0xBEEF);
    }

    function paused() external pure returns (bool) {
        return true;
    }

    function implementation() external pure returns (address) {
        return address(0x123456);
    }

    function proxiableUUID() external pure returns (bytes32) {
        return bytes32(uint256(uint160(address(0x654321))));
    }

    function blacklisted(address) external pure returns (bool) {
        return true;
    }

    function isBlocklisted(address) external pure returns (bool) {
        return true;
    }

    function transferFee() external pure returns (uint256) {
        return 1;
    }

    function taxRate() external pure returns (uint256) {
        return 1;
    }

    function rebase(uint256, uint256) external pure returns (uint256) {
        return 0;
    }

    function mint(address, uint256) external pure {}

    function burn(uint256) external pure {}

    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return keccak256("DOMAIN_SEPARATOR");
    }

    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external pure {}

    function flashLoan(address, address, uint256, bytes calldata) external pure returns (bool) {
        return true;
    }

    function selectorMarkers() external pure returns (bytes32) {
        return SELECTOR_MARKERS;
    }
}

contract RenouncedOwnerTokenSample {
    function name() external pure returns (string memory) {
        return "Renounced";
    }

    function symbol() external pure returns (string memory) {
        return "RNC";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external pure returns (uint256) {
        return 5_000_000e18;
    }

    function owner() external pure returns (address) {
        return address(0);
    }
}

contract CloneImplementationSample {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract CloneFactorySample {
    function clone(address implementation) external returns (address instance) {
        instance = Clones.clone(implementation);
    }
}
