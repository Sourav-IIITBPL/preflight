// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { VaultGuard } from "../../contracts/guards/VaultGuard.sol";
import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/*//////////////////////////////////////////////////////////////
    Mock Vault for Testing
//////////////////////////////////////////////////////////////*/

contract MockAsset is IERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function approve(address spender, uint256 amt) external returns (bool) {
        allowance[msg.sender][spender] = amt;
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
    }
}

contract MockVault is IERC4626 {
    MockAsset public assetToken;
    uint256 public override totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(MockAsset _asset) {
        assetToken = _asset;
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function totalAssets() public view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        if (totalSupply == 0) return assets;
        return (assets * totalSupply) / totalAssets();
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        uint256 shares =
            totalSupply == 0 ? assets : (assets * totalSupply) / totalAssets();
        assetToken.transferFrom(msg.sender, address(this), assets);
        balanceOf[receiver] += shares;
        totalSupply += shares;
        return shares;
    }
}

/*//////////////////////////////////////////////////////////////
                        VaultGuard Tests
//////////////////////////////////////////////////////////////*/

contract VaultGuardTest is Test {
    VaultGuard guard;
    MockAsset asset;
    MockVault vault;

    function setUp() public {
        asset = new MockAsset();
        vault = new MockVault(asset);
        guard = new VaultGuard();

        asset.mint(address(this), 1_000 ether);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_blocksZeroSupplyInflation() public {
        // Donate before first deposit
        asset.transfer(address(vault), 100 ether);

        (VaultGuard.RiskLevel level, ) =
            guard.checkVault(address(vault), 10 ether);

        assertEq(uint256(level), uint256(VaultGuard.RiskLevel.BLOCK));
    }

    function test_allowsNormalDeposit() public {
        vault.deposit(100 ether, address(this));

        (VaultGuard.RiskLevel level, ) =
            guard.checkVault(address(vault), 10 ether);

        assertEq(uint256(level), uint256(VaultGuard.RiskLevel.SAFE));
    }

    function test_detectsBalanceMismatch() public {
        vault.deposit(100 ether, address(this));

        // External donation
        asset.mint(address(vault), 50 ether);

        (VaultGuard.RiskLevel level, ) =
            guard.checkVault(address(vault), 10 ether);

        assertEq(uint256(level), uint256(VaultGuard.RiskLevel.BLOCK));
    }

    function test_warnsOnDustShares() public {
        vault.deposit(1 ether, address(this));

        (VaultGuard.RiskLevel level, ) =
            guard.checkVault(address(vault), 1 wei);

        assertEq(uint256(level), uint256(VaultGuard.RiskLevel.WARNING));
    }
}
