// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockV2Router {
    address internal _factory;
    address internal _weth;
    uint256[] internal _amountsOut;
    uint256[] internal _amountsIn;

    constructor(address factory_, address weth_) {
        _factory = factory_;
        _weth = weth_;
    }

    function factory() external view returns (address) {
        return _factory;
    }

    function WETH() external view returns (address) {
        return _weth;
    }

    function getAmountsOut(uint256, address[] calldata) external view returns (uint256[] memory amounts) {
        return _amountsOut;
    }

    function getAmountsIn(uint256, address[] calldata) external view returns (uint256[] memory amounts) {
        return _amountsIn;
    }

    function setFactory(address factory_) external {
        _factory = factory_;
    }

    function setWETH(address weth_) external {
        _weth = weth_;
    }

    function setAmountsOut(uint256[] calldata amounts) external {
        delete _amountsOut;
        uint256 len = amounts.length;
        for (uint256 i = 0; i < len; ++i) {
            _amountsOut.push(amounts[i]);
        }
    }

    function setAmountsIn(uint256[] calldata amounts) external {
        delete _amountsIn;
        uint256 len = amounts.length;
        for (uint256 i = 0; i < len; ++i) {
            _amountsIn.push(amounts[i]);
        }
    }
}
