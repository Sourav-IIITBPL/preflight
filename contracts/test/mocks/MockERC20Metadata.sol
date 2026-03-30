// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockERC20Metadata {
    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint256 internal _totalSupply;

    mapping(address => uint256) internal _balances;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function setBalance(address account, uint256 amount) external {
        _balances[account] = amount;
    }
}
