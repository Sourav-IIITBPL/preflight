// ============================================================================
//  tokenOverrides.ts — State override helpers for fork simulation
//
//  ERC20 balance:
//    Lives in the token contract's storage as `_balances[user]`.
//    OZ slot 0:  keccak256(abi.encode(user, uint256(0)))
//    USDT-style: keccak256(abi.encode(user, uint256(1)))
//    We use slot 0 by default; caller can override.
//
//  ERC20 allowance:
//    Lives at keccak256(abi.encode(spender, keccak256(abi.encode(owner, slot+1))))
//    OZ pattern for _allowances mapping is slot 1.
//
//  Native ETH balance:
//    In stateOverrides: { [address]: { balance: hexAmount } }
//    This is DIFFERENT from ERC20 — it sets the native ETH balance directly.
//    Use this only for ETH-in/out swaps (swapExactETHForTokens etc.).
// ============================================================================

import { ethers } from "ethers";

export interface StorageOverride {
    stateDiff: Record<string, string>;
}

// ─── Storage slot computation ─────────────────────────────────────────────────

/** keccak256(abi.encode(key, mappingSlot)) — standard Solidity mapping slot */
function mappingSlot(key: string, slot: number): string {
    return ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [key, slot])
    );
}

/** keccak256(abi.encode(innerKey, keccak256(abi.encode(outerKey, baseSlot)))) — nested mapping */
function nestedMappingSlot(outerKey: string, innerKey: string, baseSlot: number): string {
    const outer = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [outerKey, baseSlot])
    );
    return ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(["address", "bytes32"], [innerKey, outer])
    );
}

function padHex(value: ethers.BigNumber): string {
    return ethers.utils.hexZeroPad(value.toHexString(), 32);
}

// ─── ERC20 balance override ───────────────────────────────────────────────────

/**
 * Builds a `stateOverrides[tokenAddress]` entry that sets `user`'s balance to `amount`.
 * Uses the OZ `_balances` mapping at slot `mappingSlotIndex` (default 0).
 *
 * Usage in evm.call:
 *   stateOverrides: {
 *     [tokenAddress]: buildERC20BalanceOverride(tokenAddress, user, amount)
 *   }
 */
export function buildERC20BalanceOverride(
    tokenAddress: string,
    user:         string,
    amount:       ethers.BigNumber,
    slotIndex:    number = 0
): StorageOverride {
    return {
        stateDiff: {
            [mappingSlot(user, slotIndex)]: padHex(amount),
        },
    };
}

// ─── ERC20 allowance override ─────────────────────────────────────────────────

/**
 * Builds an allowance override: `owner` grants `spender` infinite allowance.
 * OZ `_allowances` is a nested mapping at slot 1: _allowances[owner][spender].
 * Solidity storage: keccak256(abi.encode(spender, keccak256(abi.encode(owner, 1))))
 */
export function buildERC20AllowanceOverride(
    tokenAddress: string,
    owner:        string,
    spender:      string,
    amount:       ethers.BigNumber = ethers.constants.MaxUint256,
    baseSlot:     number = 1
): StorageOverride {
    const slot = nestedMappingSlot(owner, spender, baseSlot);
    return {
        stateDiff: {
            [slot]: padHex(amount),
        },
    };
}

// ─── Combined ERC20 balance + allowance override ──────────────────────────────

/**
 * Combines balance and allowance overrides for a single token.
 * Required for simulations where the user must both HOLD and have APPROVED
 * a contract to pull their tokens (e.g., vault deposit, LP add).
 */
export function buildERC20Override(p: {
    tokenAddress:  string;
    user:          string;
    amount:        ethers.BigNumber;
    spender:       string;
    allowance?:    ethers.BigNumber;
    balanceSlot?:  number;
    allowanceSlot?: number;
}): StorageOverride {
    const bal = buildERC20BalanceOverride(p.tokenAddress, p.user, p.amount, p.balanceSlot ?? 0);
    const alw = buildERC20AllowanceOverride(
        p.tokenAddress, p.user, p.spender,
        p.allowance ?? ethers.constants.MaxUint256,
        p.allowanceSlot ?? 1
    );
    return { stateDiff: { ...bal.stateDiff, ...alw.stateDiff } };
}

// ─── Native ETH balance override ─────────────────────────────────────────────

/**
 * For ETH-in swaps (swapExactETHForTokens, swapETHForExactTokens).
 * Sets the user's native ETH balance to `amount`.
 *
 * This is a TOP-LEVEL stateOverrides entry, NOT nested under a token address:
 *   stateOverrides: {
 *     [userAddress]: buildNativeETHOverride(amount)
 *   }
 */
export function buildNativeETHOverride(amount: ethers.BigNumber): { balance: string } {
    return { balance: ethers.utils.hexValue(amount) };
}

// ─── Multi-token override builder ─────────────────────────────────────────────

/**
 * Merges multiple token overrides into one stateOverrides map.
 * Handles deduplication if the same token appears twice.
 */
export function mergeOverrides(
    overrides: Record<string, StorageOverride | { balance: string }>
): Record<string, any> {
    return overrides;
}