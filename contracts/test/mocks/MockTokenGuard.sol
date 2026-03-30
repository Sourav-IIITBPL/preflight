// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITokenGuard, TokenGuardResult} from "../../src/guards/interfaces/ITokenGuard.sol";

contract MockTokenGuard is ITokenGuard {
    mapping(address => TokenGuardResult) internal results;

    function setResult(address token, TokenGuardResult calldata result) external {
        results[token] = result;
    }

    function checkToken(address token) external view returns (TokenGuardResult memory r) {
        return results[token];
    }
}
