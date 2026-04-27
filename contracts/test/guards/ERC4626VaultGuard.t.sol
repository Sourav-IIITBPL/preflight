// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {ERC4626VaultGuard, VaultGuardResult} from "../../src/guards/ERC4626VaultGuard.sol";
import {VaultOpType} from "../../src/types/OffChainTypes.sol";
import {MockTokenGuard} from "../mocks/MockTokenGuard.sol";
import {MockERC20Metadata} from "../mocks/MockERC20Metadata.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";

contract ERC4626VaultGuardTest is Test {
    MockTokenGuard internal tokenGuard;
    MockERC20Metadata internal asset;
    MockERC20Metadata internal vaultToken; // To avoid confusion with the vault contract
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

        guard = new ERC4626VaultGuard(address(tokenGuard));
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

        // Length should be 1 (secondVault). address(0) is skipped, duplicate secondVault is skipped.
        assertEq(guard.getWhitelistedVaults().length, 1);
    }

    function test_onlyOwnerCanCallSetters() public {
        address nonOwner = address(0xBAD);
        vm.startPrank(nonOwner);

        vm.expectRevert("Ownable: caller is not the owner");
        guard.whitelistVault(address(vault));

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);
        vm.expectRevert("Ownable: caller is not the owner");
        guard.addWhitelistedVaults(vaults);

        vm.expectRevert("Ownable: caller is not the owner");
        guard.removeWhitelistedVault(address(vault));

        vm.expectRevert("Ownable: caller is not the owner");
        guard.setAuthorizedRouter(router, true);

        vm.stopPrank();
    }

    function test_storeCheckRequiresAuthorizedRouter() public {
        vm.expectRevert(bytes("NOT_AUTHORIZED_ROUTER"));
        guard.storeCheck(address(vault), user, 1e18, VaultOpType.DEPOSIT);
    }

    function test_checkVaultFlagsForUnwhitelistedDonationAndBalanceMismatch() public {
        vault.setAccounting(2 ether, 0);
        asset.setBalance(address(vault), 1 ether);

        (VaultGuardResult memory result,,) =
            guard.checkVault(address(vault), 1e18, VaultOpType.DEPOSIT);

        assertTrue(result.VAULT_NOT_WHITELISTED);
        assertTrue(result.VAULT_ZERO_SUPPLY);
        assertTrue(result.DONATION_ATTACK);
        assertTrue(result.VAULT_BALANCE_MISMATCH);
    }

    function test_checkVaultFlagsInflationRisk() public {
        vault.setAccounting(1000e18, 1e18);
        (VaultGuardResult memory result,,) = guard.checkVault(address(vault), 1e18, VaultOpType.DEPOSIT);
        assertTrue(result.SHARE_INFLATION_RISK);
    }

    function test_checkVaultSetsPreviewRevertOnAllOps() public {
        vault.setPreviewReverts(true, true, true, true);

        (VaultGuardResult memory result,,) = guard.checkVault(address(vault), 1e18, VaultOpType.DEPOSIT);
        assertTrue(result.PREVIEW_REVERT);

        (result,,) = guard.checkVault(address(vault), 1e18, VaultOpType.MINT);
        assertTrue(result.PREVIEW_REVERT);

        (result,,) = guard.checkVault(address(vault), 1e18, VaultOpType.WITHDRAW);
        assertTrue(result.PREVIEW_REVERT);

        (result,,) = guard.checkVault(address(vault), 1e18, VaultOpType.REDEEM);
        assertTrue(result.PREVIEW_REVERT);
    }

    function test_checkVaultMintFlags() public {
        // MINT uses maxMint which is indexed at opType=1
        vault.setMaxValues(type(uint256).max, 5e18, type(uint256).max, type(uint256).max);
        vault.setPreviewValues(0, 10, 0, 0); // dust assets
        vault.setConvertValues(0, 20); // mismatch

        (VaultGuardResult memory result, , uint256 previewAssets) =
            guard.checkVault(address(vault), 10e18, VaultOpType.MINT);

        // For MINT, EXCEEDS_MAX_DEPOSIT is used as the flag for maxMint overflow
        assertTrue(result.EXCEEDS_MAX_DEPOSIT);
        assertTrue(result.DUST_ASSETS);
        assertTrue(result.PREVIEW_CONVERT_MISMATCH);
        assertEq(previewAssets, 10);
    }

    function test_checkVaultRedeemFlags() public {
        vault.setMaxValues(type(uint256).max, type(uint256).max, type(uint256).max, 5e18);
        vault.setPreviewValues(0, 0, 0, 0); // zero assets out
        
        (VaultGuardResult memory result,,) = guard.checkVault(address(vault), 10e18, VaultOpType.REDEEM);

        assertTrue(result.EXCEEDS_MAX_REDEEM);
        assertTrue(result.ZERO_ASSETS_OUT);
    }

    function test_checkVaultWithdrawFlags() public {
        vault.setMaxValues(type(uint256).max, type(uint256).max, type(uint256).max, 5e18);
        // set previewWithdraw to 0 explicitly
        vault.setPreviewValues(0, 0, 0, 0); 

        (VaultGuardResult memory result,,) = guard.checkVault(address(vault), 10e18, VaultOpType.WITHDRAW);

        assertTrue(result.EXCEEDS_MAX_REDEEM);
        assertTrue(result.ZERO_SHARES_OUT);
    }

    function test_storeGetAndValidateRoundTrip() public {
        guard.whitelistVault(address(vault));
        guard.setAuthorizedRouter(router, true);

        guard.storeCheck(address(vault), user, 1e18, VaultOpType.DEPOSIT);

        (
            VaultGuardResult memory result,
            uint256 previewShares,
            uint256 previewAssets,
            uint256 blockNo
        ) = guard.getLastCheck(address(vault), user);

        assertFalse(result.VAULT_NOT_WHITELISTED);
        assertEq(previewShares, 1e18);
        assertEq(previewAssets, 0);
        assertEq(blockNo, block.number);

        guard.validate(address(vault), user, 1e18, VaultOpType.DEPOSIT);
    }

    function test_validateRevertsOnMismatchedParameters() public {
        guard.whitelistVault(address(vault));
        guard.setAuthorizedRouter(router, true);
        guard.storeCheck(address(vault), user, 1e18, VaultOpType.DEPOSIT);

        // Mismatched amount -> previewShares will be 2e18 instead of 1e18
        vm.expectRevert(bytes("VAULT_STATE_CHANGED"));
        guard.validate(address(vault), user, 2e18, VaultOpType.DEPOSIT);

        // Mismatched opType -> we'll make previewWithdraw return something else
        vault.setPreviewValues(0, 0, 555, 0); 
        vm.expectRevert(bytes("VAULT_STATE_CHANGED"));
        guard.validate(address(vault), user, 1e18, VaultOpType.WITHDRAW);
    }

    function test_validateRevertsWhenStale() public {
        guard.whitelistVault(address(vault));
        guard.setAuthorizedRouter(router, true);
        guard.storeCheck(address(vault), user, 1e18, VaultOpType.DEPOSIT);

        vm.roll(block.number + 1);
        vm.expectRevert(bytes("STALE_CHECK"));
        guard.validate(address(vault), user, 1e18, VaultOpType.DEPOSIT);
    }

    function test_normalizeEdgeCases() public {
        MockERC20Metadata highDecToken = new MockERC20Metadata("High", "HI", 20);
        MockERC4626Vault highDecVault = new MockERC4626Vault(address(highDecToken), 20);
        guard.whitelistVault(address(highDecVault));
        guard.checkVault(address(highDecVault), 1e20, VaultOpType.DEPOSIT);
    }
}
