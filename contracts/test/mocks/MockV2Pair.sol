// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockV2Pair {
    address internal _token0;
    address internal _token1;
    address internal _factory;
    uint112 internal _reserve0;
    uint112 internal _reserve1;
    uint32 internal _blockTimestampLast;
    uint256 internal _totalSupply;
    uint256 internal _price0CumulativeLast;
    uint256 internal _price1CumulativeLast;
    uint256 internal _kLast;

    constructor(address token0_, address token1_, address factory_) {
        _token0 = token0_;
        _token1 = token1_;
        _factory = factory_;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function price0CumulativeLast() external view returns (uint256) {
        return _price0CumulativeLast;
    }

    function price1CumulativeLast() external view returns (uint256) {
        return _price1CumulativeLast;
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }

    function factory() external view returns (address) {
        return _factory;
    }

    function kLast() external view returns (uint256) {
        return _kLast;
    }

    function setReserves(uint112 reserve0_, uint112 reserve1_, uint32 blockTimestampLast_) external {
        _reserve0 = reserve0_;
        _reserve1 = reserve1_;
        _blockTimestampLast = blockTimestampLast_;
    }

    function setTotalSupply(uint256 totalSupply_) external {
        _totalSupply = totalSupply_;
    }

    function setCumulatives(uint256 price0CumulativeLast_, uint256 price1CumulativeLast_) external {
        _price0CumulativeLast = price0CumulativeLast_;
        _price1CumulativeLast = price1CumulativeLast_;
    }

    function setKLast(uint256 kLast_) external {
        _kLast = kLast_;
    }

    function setFactory(address factory_) external {
        _factory = factory_;
    }
}
