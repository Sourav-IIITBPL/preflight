// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ERC4626VaultGuard} from "../../src/guards/ERC4626VaultGuard.sol";
import {VaultOpType} from "../../src/types/OffChainTypes.sol";
import {MockTokenGuard} from "../mocks/MockTokenGuard.sol";
import {MockERC20Metadata} from "../mocks/MockERC20Metadata.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";

contract ERC4626VaultGuardTest is Test {
    MockTokenGuard internal tokenGuard;
    MockERC20Metadata internal asset;
    MockERC4626Vault internal vault;
    ERC4626VaultGuard internal guard;

    address internal router = address(this);
    address internal user = address(0xBEEF);

    function setUp() public {
        tokenGuard = new MockTokenGuard();
        asset = new MockERC20Metadata("Asset", "AST", 18);
        vault = new MockERC4626Vault(address(asset), 18);

        asset.setTotalSupply(1_000_000e18);
        asset.setBalance(address(vault), 100e18);

        vault.setAccounting(100e18, 100e18);
        vault.setMaxValues(type(uint256).max, type(uint256).max, type(uint256).max, type(uint256).max);
        vault.setPreviewValues(1e18, 1e18, 1e18, 1e18);
        vault.setConvertValues(1e18, 1e18);

        ERC4626VaultGuard implementation = new ERC4626VaultGuard();
        bytes memory initData = abi.encodeCall(ERC4626VaultGuard.initialize, (address(tokenGuard)));
        guard = ERC4626VaultGuard(address(new ERC1967Proxy(address(implementation), initData)));
    }

    function test_whitelistLifecycle() public {
        guard.whitelistVault(address(vault));
        assertTrue(guard.isWhitelisted(address(vault)));

        address secondVault = address(0xCAFE);
        address[] memory vaults = new address[](3);
        vaults[0] = secondVault;
        vaults[1] = address(0);
        vaults[2] = secondVault;
        guard.addWhitelistedVaults(vaults);

        assertTrue(guard.isWhitelisted(secondVault));
        guard.removeWhitelistedVault(address(vault));
        assertFalse(guard.isWhitelisted(address(vault)));
    }

    function test_storeCheckRequiresAuthorizedRouter() public {
        vm.expectRevert(bytes("NOT_AUTHORIZED_ROUTER"));
        guard.storeCheck(address(vault), user, 1e18, VaultOpType.DEPOSIT);
    }

    function test_checkVaultFlagsForUnwhitelistedDonationAndBalanceMismatch() public {
        vault.setAccounting(2 ether, 0);
        asset.setBalance(address(vault), 1 ether);

        (ERC4626VaultGuard.VaultGuardResult memory result,,) = guard.checkVault(address(vault), 1e18, VaultOpType.DEPOSIT);

        assertTrue(result.VAULT_NOT_WHITELISTED);
        assertTrue(result.VAULT_ZERO_SUPPLY);
        assertTrue(result.DONATION_ATTACK);
        assertTrue(result.VAULT_BALANCE_MISMATCH);
    }

    function test_checkVaultSetsPreviewRevertOnDeposit() public {
        vault.setPreviewReverts(true, false, false, false);

        (ERC4626VaultGuard.VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets) =
            guard.checkVault(address(vault), 1e18, VaultOpType.DEPOSIT);

        assertTrue(result.PREVIEW_REVERT);
        assertEq(previewShares, 0);
        assertEq(previewAssets, 0);
    }

    function test_checkVaultSetsDepositSpecificFlags() public {
        vault.setMaxValues(5e18, type(uint256).max, type(uint256).max, type(uint256).max);
        vault.setPreviewValues(999, 1e18, 1e18, 1e18);
        vault.setConvertValues(2000, 1e18);

        (ERC4626VaultGuard.VaultGuardResult memory result,,) =
            guard.checkVault(address(vault), 10e18, VaultOpType.DEPOSIT);

        assertTrue(result.EXCEEDS_MAX_DEPOSIT);
        assertTrue(result.DUST_SHARES);
        assertTrue(result.EXCHANGE_RATE_ANOMALY);
        assertTrue(result.PREVIEW_CONVERT_MISMATCH);
    }

    function test_storeGetAndValidateRoundTrip() public {
        guard.whitelistVault(address(vault));
        guard.setAuthorizedRouter(router, true);

        guard.storeCheck(address(vault), user, 1e18, VaultOpType.DEPOSIT);

        (ERC4626VaultGuard.VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNo)
        = guard.getLastCheck(address(vault), user);

        assertFalse(result.VAULT_NOT_WHITELISTED);
        assertEq(previewShares, 1e18);
        assertEq(previewAssets, 0);
        assertEq(blockNo, block.number);

        guard.validate(address(vault), user, 1e18, VaultOpType.DEPOSIT);
    }

    function test_validateRevertsWhenStale() public {
        guard.whitelistVault(address(vault));
        guard.setAuthorizedRouter(router, true);
        guard.storeCheck(address(vault), user, 1e18, VaultOpType.DEPOSIT);

        vm.roll(block.number + 1);
        vm.expectRevert(bytes("STALE_CHECK"));
        guard.validate(address(vault), user, 1e18, VaultOpType.DEPOSIT);
    }
}
