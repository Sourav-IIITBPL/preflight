interface IERC20 {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
}

interface IOwnable {
    function owner() external view returns (address);
}

interface IPausable {
    function paused() external view returns (bool);
}