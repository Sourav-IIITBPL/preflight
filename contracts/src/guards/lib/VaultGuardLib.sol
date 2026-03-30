// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VaultGuardResult} from "../ERC4626VaultGuard.sol";
import {TokenGuardResult} from "../interfaces/ITokenGuard.sol";

library VaultGuardLib {
    function packed(VaultGuardResult memory vaultReport) external pure returns (uint48 result) {
        if (vaultReport.VAULT_NOT_WHITELISTED) result |= uint48(1) << 0;
        if (vaultReport.VAULT_ZERO_SUPPLY) result |= uint48(1) << 1;
        if (vaultReport.DONATION_ATTACK) result |= uint48(1) << 2;
        if (vaultReport.SHARE_INFLATION_RISK) result |= uint48(1) << 3;
        if (vaultReport.VAULT_BALANCE_MISMATCH) result |= uint48(1) << 4;
        if (vaultReport.EXCHANGE_RATE_ANOMALY) result |= uint48(1) << 5;
        if (vaultReport.PREVIEW_REVERT) result |= uint48(1) << 6;
        if (vaultReport.ZERO_SHARES_OUT) result |= uint48(1) << 7;
        if (vaultReport.ZERO_ASSETS_OUT) result |= uint48(1) << 8;
        if (vaultReport.DUST_SHARES) result |= uint48(1) << 9;
        if (vaultReport.DUST_ASSETS) result |= uint48(1) << 10;
        if (vaultReport.EXCEEDS_MAX_DEPOSIT) result |= uint48(1) << 11;
        if (vaultReport.EXCEEDS_MAX_REDEEM) result |= uint48(1) << 12;
        if (vaultReport.PREVIEW_CONVERT_MISMATCH) result |= uint48(1) << 13;

        TokenGuardResult memory tokenReport = vaultReport.tokenResult;

        if (tokenReport.NOT_A_CONTRACT) result |= uint48(1) << 14;
        if (tokenReport.EMPTY_BYTECODE) result |= uint48(1) << 15;
        if (tokenReport.DECIMALS_REVERT) result |= uint48(1) << 16;
        if (tokenReport.WEIRD_DECIMALS) result |= uint48(1) << 17;
        if (tokenReport.HIGH_DECIMALS) result |= uint48(1) << 18;
        if (tokenReport.TOTAL_SUPPLY_REVERT) result |= uint48(1) << 19;
        if (tokenReport.ZERO_TOTAL_SUPPLY) result |= uint48(1) << 20;
        if (tokenReport.VERY_LOW_TOTAL_SUPPLY) result |= uint48(1) << 21;
        if (tokenReport.SYMBOL_REVERT) result |= uint48(1) << 22;
        if (tokenReport.NAME_REVERT) result |= uint48(1) << 23;
        if (tokenReport.IS_EIP1967_PROXY) result |= uint48(1) << 24;
        if (tokenReport.IS_EIP1822_PROXY) result |= uint48(1) << 25;
        if (tokenReport.IS_MINIMAL_PROXY) result |= uint48(1) << 26;
        if (tokenReport.HAS_OWNER) result |= uint48(1) << 27;
        if (tokenReport.OWNERSHIP_RENOUNCED) result |= uint48(1) << 28;
        if (tokenReport.OWNER_IS_EOA) result |= uint48(1) << 29;
        if (tokenReport.IS_PAUSABLE) result |= uint48(1) << 30;
        if (tokenReport.IS_CURRENTLY_PAUSED) result |= uint48(1) << 31;
        if (tokenReport.HAS_BLACKLIST) result |= uint48(1) << 32;
        if (tokenReport.HAS_BLOCKLIST) result |= uint48(1) << 33;
        if (tokenReport.POSSIBLE_FEE_ON_TRANSFER) result |= uint48(1) << 34;
        if (tokenReport.HAS_TRANSFER_FEE_GETTER) result |= uint48(1) << 35;
        if (tokenReport.HAS_TAX_FUNCTION) result |= uint48(1) << 36;
        if (tokenReport.POSSIBLE_REBASING) result |= uint48(1) << 37;
        if (tokenReport.HAS_MINT_CAPABILITY) result |= uint48(1) << 38;
        if (tokenReport.HAS_BURN_CAPABILITY) result |= uint48(1) << 39;
        if (tokenReport.HAS_PERMIT) result |= uint48(1) << 40;
        if (tokenReport.HAS_FLASH_MINT) result |= uint48(1) << 41;

        return result;
    }

    function unpacked(uint48 packedReport) external pure returns (VaultGuardResult memory result) {
        result.VAULT_NOT_WHITELISTED = (packedReport >> 0) & 1 == 1;
        result.VAULT_ZERO_SUPPLY = (packedReport >> 1) & 1 == 1;
        result.DONATION_ATTACK = (packedReport >> 2) & 1 == 1;
        result.SHARE_INFLATION_RISK = (packedReport >> 3) & 1 == 1;
        result.VAULT_BALANCE_MISMATCH = (packedReport >> 4) & 1 == 1;
        result.EXCHANGE_RATE_ANOMALY = (packedReport >> 5) & 1 == 1;
        result.PREVIEW_REVERT = (packedReport >> 6) & 1 == 1;
        result.ZERO_SHARES_OUT = (packedReport >> 7) & 1 == 1;
        result.ZERO_ASSETS_OUT = (packedReport >> 8) & 1 == 1;
        result.DUST_SHARES = (packedReport >> 9) & 1 == 1;
        result.DUST_ASSETS = (packedReport >> 10) & 1 == 1;
        result.EXCEEDS_MAX_DEPOSIT = (packedReport >> 11) & 1 == 1;
        result.EXCEEDS_MAX_REDEEM = (packedReport >> 12) & 1 == 1;
        result.PREVIEW_CONVERT_MISMATCH = (packedReport >> 13) & 1 == 1;

        TokenGuardResult memory _tokenReport;

        _tokenReport.NOT_A_CONTRACT = (packedReport >> 14) & 1 == 1;
        _tokenReport.EMPTY_BYTECODE = (packedReport >> 15) & 1 == 1;
        _tokenReport.DECIMALS_REVERT = (packedReport >> 16) & 1 == 1;
        _tokenReport.WEIRD_DECIMALS = (packedReport >> 17) & 1 == 1;
        _tokenReport.HIGH_DECIMALS = (packedReport >> 18) & 1 == 1;
        _tokenReport.TOTAL_SUPPLY_REVERT = (packedReport >> 19) & 1 == 1;
        _tokenReport.ZERO_TOTAL_SUPPLY = (packedReport >> 20) & 1 == 1;
        _tokenReport.VERY_LOW_TOTAL_SUPPLY = (packedReport >> 21) & 1 == 1;
        _tokenReport.SYMBOL_REVERT = (packedReport >> 22) & 1 == 1;
        _tokenReport.NAME_REVERT = (packedReport >> 23) & 1 == 1;
        _tokenReport.IS_EIP1967_PROXY = (packedReport >> 24) & 1 == 1;
        _tokenReport.IS_EIP1822_PROXY = (packedReport >> 25) & 1 == 1;
        _tokenReport.IS_MINIMAL_PROXY = (packedReport >> 26) & 1 == 1;
        _tokenReport.HAS_OWNER = (packedReport >> 27) & 1 == 1;
        _tokenReport.OWNERSHIP_RENOUNCED = (packedReport >> 28) & 1 == 1;
        _tokenReport.OWNER_IS_EOA = (packedReport >> 29) & 1 == 1;
        _tokenReport.IS_PAUSABLE = (packedReport >> 30) & 1 == 1;
        _tokenReport.IS_CURRENTLY_PAUSED = (packedReport >> 31) & 1 == 1;
        _tokenReport.HAS_BLACKLIST = (packedReport >> 32) & 1 == 1;
        _tokenReport.HAS_BLOCKLIST = (packedReport >> 33) & 1 == 1;
        _tokenReport.POSSIBLE_FEE_ON_TRANSFER = (packedReport >> 34) & 1 == 1;
        _tokenReport.HAS_TRANSFER_FEE_GETTER = (packedReport >> 35) & 1 == 1;
        _tokenReport.HAS_TAX_FUNCTION = (packedReport >> 36) & 1 == 1;
        _tokenReport.POSSIBLE_REBASING = (packedReport >> 37) & 1 == 1;
        _tokenReport.HAS_MINT_CAPABILITY = (packedReport >> 38) & 1 == 1;
        _tokenReport.HAS_BURN_CAPABILITY = (packedReport >> 39) & 1 == 1;
        _tokenReport.HAS_PERMIT = (packedReport >> 40) & 1 == 1;
        _tokenReport.HAS_FLASH_MINT = (packedReport >> 41) & 1 == 1;

        result.tokenResult = _tokenReport;

        return result;
    }
}
