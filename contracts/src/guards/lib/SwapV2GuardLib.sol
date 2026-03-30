// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SwapV2GuardResult, StoredSwapCheck} from "../V2Guards/SwapV2Guard.sol";
import {TokenGuardResult} from "../interfaces/ITokenGuard.sol";

library SwapV2GuardLib {
    function packedCheck(SwapV2GuardResult memory result, uint256 amount)
        external
        pure
        returns (StoredSwapCheck memory storedCheck)
    {
        uint16 core = _packSwapCore(result);

        uint8 length = uint8(result.tokenResult.length);
        uint32[] memory tokens = new uint32[](length);

        for (uint256 i; i < length; ++i) {
            tokens[i] = _packToken(result.tokenResult[i]);
        }

        if (length <= 7) {
            storedCheck.packed = _packSwapUint256(core, tokens);
            storedCheck.isCompact = true;
            storedCheck.length = length;
            storedCheck.value = amount;
        } else {
            storedCheck.data = _packSwapBytes(core, tokens);
            storedCheck.isCompact = false;
            storedCheck.length = length;
            storedCheck.packed = 0;
            storedCheck.value = amount;
        }
    }

    function unpackedCheck(StoredSwapCheck memory storedCheck)
        external
        pure
        returns (SwapV2GuardResult memory result, uint256 amountOut)
    {
        bool isCompact = storedCheck.isCompact;
        uint8 length = storedCheck.length;

        uint16 core;
        uint32[] memory tokens;

        if (isCompact) {
            (core, tokens) = _unpackSwapUint256(storedCheck.packed, length);
        } else {
            (core, tokens) = _unpackSwapBytes(storedCheck.data);
        }
        result = _unpack(core, tokens);
        amountOut = storedCheck.value;

        return (result, amountOut);
    }

    function _unpack(uint16 core, uint32[] memory tokens) internal pure returns (SwapV2GuardResult memory r) {
        r = _unpackSwapCore(core);
        uint256 length = tokens.length;
        r.tokenResult = new TokenGuardResult[](length);
        for (uint256 i; i < length; ++i) {
            r.tokenResult[i] = _unpackToken(tokens[i]);
        }
    }

    function _packSwapUint256(uint16 core, uint32[] memory tokens) internal pure returns (uint256 packed) {
        require(tokens.length <= 7, "TOO_MANY_TOKENS");
        packed = uint256(core);
        uint256 size = tokens.length;
        for (uint256 i; i < size; ++i) {
            packed |= uint256(tokens[i]) << (16 + i * 32);
        }
    }

    function _unpackSwapUint256(uint256 packed, uint8 len) internal pure returns (uint16 core, uint32[] memory tokens) {
        core = uint16(packed);
        tokens = new uint32[](len);
        for (uint256 i; i < len; ++i) {
            tokens[i] = uint32(packed >> (16 + i * 32));
        }
    }

    function _packSwapBytes(uint16 core, uint32[] memory tokens) internal pure returns (bytes memory out) {
        uint256 len = tokens.length;
        out = new bytes(2 + len * 4);

        assembly {
            mstore(add(out, 32), shl(240, core))
        }

        for (uint256 i; i < len; ++i) {
            uint32 t = tokens[i];
            uint256 offset = 2 + i * 4;

            assembly {
                let ptr := add(add(out, 32), offset)
                mstore(ptr, shl(224, t))
            }
        }
    }

    function _unpackSwapBytes(bytes memory data) internal pure returns (uint16 core, uint32[] memory tokens) {
        assembly {
            core := shr(240, mload(add(data, 32)))
        }

        uint256 len = (data.length - 2) / 4;
        tokens = new uint32[](len);

        for (uint256 i; i < len; ++i) {
            uint32 t;
            uint256 offset = 2 + i * 4;

            assembly {
                let ptr := add(add(data, 32), offset)
                t := shr(224, mload(ptr))
            }

            tokens[i] = t;
        }
    }

    function _packSwapCore(SwapV2GuardResult memory guardResult) internal pure returns (uint16 result) {
        if (guardResult.ROUTER_NOT_TRUSTED) result |= uint16(1) << 0;
        if (guardResult.FACTORY_NOT_TRUSTED) result |= uint16(1) << 1;
        if (guardResult.DEEP_MULTIHOP) result |= uint16(1) << 2;
        if (guardResult.DUPLICATE_TOKEN_IN_PATH) result |= uint16(1) << 3;
        if (guardResult.POOL_NOT_EXISTS) result |= uint16(1) << 4;
        if (guardResult.FACTORY_MISMATCH) result |= uint16(1) << 5;
        if (guardResult.ZERO_LIQUIDITY) result |= uint16(1) << 6;
        if (guardResult.LOW_LIQUIDITY) result |= uint16(1) << 7;
        if (guardResult.LOW_LP_SUPPLY) result |= uint16(1) << 8;
        if (guardResult.POOL_TOO_NEW) result |= uint16(1) << 9;
        if (guardResult.SEVERE_IMBALANCE) result |= uint16(1) << 10;
        if (guardResult.K_INVARIANT_BROKEN) result |= uint16(1) << 11;
        if (guardResult.HIGH_SWAP_IMPACT) result |= uint16(1) << 12;
        if (guardResult.FLASHLOAN_RISK) result |= uint16(1) << 13;
        if (guardResult.PRICE_MANIPULATED) result |= uint16(1) << 14;
    }

    function _unpackSwapCore(uint16 packed) internal pure returns (SwapV2GuardResult memory result) {
        result.ROUTER_NOT_TRUSTED = (packed >> 0) & 1 == 1;
        result.FACTORY_NOT_TRUSTED = (packed >> 1) & 1 == 1;
        result.DEEP_MULTIHOP = (packed >> 2) & 1 == 1;
        result.DUPLICATE_TOKEN_IN_PATH = (packed >> 3) & 1 == 1;
        result.POOL_NOT_EXISTS = (packed >> 4) & 1 == 1;
        result.FACTORY_MISMATCH = (packed >> 5) & 1 == 1;
        result.ZERO_LIQUIDITY = (packed >> 6) & 1 == 1;
        result.LOW_LIQUIDITY = (packed >> 7) & 1 == 1;
        result.LOW_LP_SUPPLY = (packed >> 8) & 1 == 1;
        result.POOL_TOO_NEW = (packed >> 9) & 1 == 1;
        result.SEVERE_IMBALANCE = (packed >> 10) & 1 == 1;
        result.K_INVARIANT_BROKEN = (packed >> 11) & 1 == 1;
        result.HIGH_SWAP_IMPACT = (packed >> 12) & 1 == 1;
        result.FLASHLOAN_RISK = (packed >> 13) & 1 == 1;
        result.PRICE_MANIPULATED = (packed >> 14) & 1 == 1;
    }

    function _packToken(TokenGuardResult memory tokenResult) internal pure returns (uint32 result) {
        if (tokenResult.NOT_A_CONTRACT) result |= uint32(1) << 0;
        if (tokenResult.EMPTY_BYTECODE) result |= uint32(1) << 1;
        if (tokenResult.DECIMALS_REVERT) result |= uint32(1) << 2;
        if (tokenResult.WEIRD_DECIMALS) result |= uint32(1) << 3;
        if (tokenResult.HIGH_DECIMALS) result |= uint32(1) << 4;
        if (tokenResult.TOTAL_SUPPLY_REVERT) result |= uint32(1) << 5;
        if (tokenResult.ZERO_TOTAL_SUPPLY) result |= uint32(1) << 6;
        if (tokenResult.VERY_LOW_TOTAL_SUPPLY) result |= uint32(1) << 7;
        if (tokenResult.SYMBOL_REVERT) result |= uint32(1) << 8;
        if (tokenResult.NAME_REVERT) result |= uint32(1) << 9;
        if (tokenResult.IS_EIP1967_PROXY) result |= uint32(1) << 10;
        if (tokenResult.IS_EIP1822_PROXY) result |= uint32(1) << 11;
        if (tokenResult.IS_MINIMAL_PROXY) result |= uint32(1) << 12;
        if (tokenResult.HAS_OWNER) result |= uint32(1) << 13;
        if (tokenResult.OWNERSHIP_RENOUNCED) result |= uint32(1) << 14;
        if (tokenResult.OWNER_IS_EOA) result |= uint32(1) << 15;
        if (tokenResult.IS_PAUSABLE) result |= uint32(1) << 16;
        if (tokenResult.IS_CURRENTLY_PAUSED) result |= uint32(1) << 17;
        if (tokenResult.HAS_BLACKLIST) result |= uint32(1) << 18;
        if (tokenResult.HAS_BLOCKLIST) result |= uint32(1) << 19;
        if (tokenResult.POSSIBLE_FEE_ON_TRANSFER) result |= uint32(1) << 20;
        if (tokenResult.HAS_TRANSFER_FEE_GETTER) result |= uint32(1) << 21;
        if (tokenResult.HAS_TAX_FUNCTION) result |= uint32(1) << 22;
        if (tokenResult.POSSIBLE_REBASING) result |= uint32(1) << 23;
        if (tokenResult.HAS_MINT_CAPABILITY) result |= uint32(1) << 24;
        if (tokenResult.HAS_BURN_CAPABILITY) result |= uint32(1) << 25;
        if (tokenResult.HAS_PERMIT) result |= uint32(1) << 26;
        if (tokenResult.HAS_FLASH_MINT) result |= uint32(1) << 27;
    }

    function _unpackToken(uint32 packed) internal pure returns (TokenGuardResult memory result) {
        result.NOT_A_CONTRACT = (packed >> 0) & 1 == 1;
        result.EMPTY_BYTECODE = (packed >> 1) & 1 == 1;
        result.DECIMALS_REVERT = (packed >> 2) & 1 == 1;
        result.WEIRD_DECIMALS = (packed >> 3) & 1 == 1;
        result.HIGH_DECIMALS = (packed >> 4) & 1 == 1;
        result.TOTAL_SUPPLY_REVERT = (packed >> 5) & 1 == 1;
        result.ZERO_TOTAL_SUPPLY = (packed >> 6) & 1 == 1;
        result.VERY_LOW_TOTAL_SUPPLY = (packed >> 7) & 1 == 1;
        result.SYMBOL_REVERT = (packed >> 8) & 1 == 1;
        result.NAME_REVERT = (packed >> 9) & 1 == 1;
        result.IS_EIP1967_PROXY = (packed >> 10) & 1 == 1;
        result.IS_EIP1822_PROXY = (packed >> 11) & 1 == 1;
        result.IS_MINIMAL_PROXY = (packed >> 12) & 1 == 1;
        result.HAS_OWNER = (packed >> 13) & 1 == 1;
        result.OWNERSHIP_RENOUNCED = (packed >> 14) & 1 == 1;
        result.OWNER_IS_EOA = (packed >> 15) & 1 == 1;
        result.IS_PAUSABLE = (packed >> 16) & 1 == 1;
        result.IS_CURRENTLY_PAUSED = (packed >> 17) & 1 == 1;
        result.HAS_BLACKLIST = (packed >> 18) & 1 == 1;
        result.HAS_BLOCKLIST = (packed >> 19) & 1 == 1;
        result.POSSIBLE_FEE_ON_TRANSFER = (packed >> 20) & 1 == 1;
        result.HAS_TRANSFER_FEE_GETTER = (packed >> 21) & 1 == 1;
        result.HAS_TAX_FUNCTION = (packed >> 22) & 1 == 1;
        result.POSSIBLE_REBASING = (packed >> 23) & 1 == 1;
        result.HAS_MINT_CAPABILITY = (packed >> 24) & 1 == 1;
        result.HAS_BURN_CAPABILITY = (packed >> 25) & 1 == 1;
        result.HAS_PERMIT = (packed >> 26) & 1 == 1;
        result.HAS_FLASH_MINT = (packed >> 27) & 1 == 1;
    }
}
