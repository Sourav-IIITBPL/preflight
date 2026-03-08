// ============================================================================
//  traceAnalysis.ts — Execution trace inspection helpers (Geth callTracer)
// ============================================================================

import { ethers } from "ethers";
import { TraceEntry, SELECTORS } from "./types.js";

// ─── Flatten nested call tree ─────────────────────────────────────────────────

export function flattenTrace(entries: TraceEntry[]): TraceEntry[] {
    const result: TraceEntry[] = [];
    const walk = (nodes: TraceEntry[]) => {
        for (const n of nodes) {
            result.push({ ...n, calls: undefined });
            if (n.calls?.length) walk(n.calls);
        }
    };
    walk(entries);
    return result;
}

// ─── DELEGATECALL ─────────────────────────────────────────────────────────────

/**
 * Flags the first DELEGATECALL whose target is NOT in knownSafeTargets.
 * knownSafeTargets should include: the top-level contract being called,
 * any known proxy implementation, any known library address.
 */
export function findDangerousDelegateCall(
    trace:            TraceEntry[],
    knownSafeTargets: string[]
): { found: boolean; target: string | null } {
    const safe = new Set(knownSafeTargets.map(a => a.toLowerCase()));
    const hit  = flattenTrace(trace).find(
        t => t.type === "DELEGATECALL" && t.to && !safe.has(t.to.toLowerCase())
    );
    return { found: !!hit, target: hit?.to ?? null };
}

// ─── SELFDESTRUCT ─────────────────────────────────────────────────────────────

export function findSelfDestruct(trace: TraceEntry[]): boolean {
    return flattenTrace(trace).some(t => t.type === "SELFDESTRUCT");
}

// ─── CREATE / CREATE2 ─────────────────────────────────────────────────────────

export function findUnexpectedCreates(trace: TraceEntry[]): string[] {
    return flattenTrace(trace)
        .filter(t => t.type === "CREATE" || t.type === "CREATE2")
        .map(t => t.to ?? "UNKNOWN");
}

// ─── Reentrancy ───────────────────────────────────────────────────────────────

/**
 * A contract is re-entered if it appears as both an ancestor caller (from)
 * and a descendant target (to) in the same call stack path.
 */
export function findReentrancy(trace: TraceEntry[]): { found: boolean; address: string | null } {
    const stack = new Set<string>();

    const walk = (entries: TraceEntry[]): { found: boolean; address: string | null } => {
        for (const e of entries) {
            const target = e.to?.toLowerCase();
            if (!target) continue;
            if (stack.has(target)) return { found: true, address: e.to! };
            stack.add(target);
            if (e.calls?.length) {
                const inner = walk(e.calls);
                if (inner.found) return inner;
            }
            stack.delete(target);
        }
        return { found: false, address: null };
    };

    return walk(trace);
}

// ─── Approval drain ───────────────────────────────────────────────────────────

/**
 * approve() or increaseAllowance() to a spender not in the legitimate set.
 * Catches vaults/routers that silently approve attacker addresses.
 */
export function findApprovalDrain(
    trace:          TraceEntry[],
    legitimateSet:  string[]
): { found: boolean; spender: string | null } {
    const legit = new Set(legitimateSet.map(a => a.toLowerCase()));

    for (const e of flattenTrace(trace)) {
        if (!e.input || e.input.length < 10) continue;
        const sel = e.input.slice(0, 10).toLowerCase();
        if (sel !== SELECTORS.APPROVE && sel !== SELECTORS.INCREASE_ALLOWANCE) continue;
        if (e.input.length < 74) continue;

        const rawSpender = "0x" + e.input.slice(34, 74);
        try {
            const spender = ethers.utils.getAddress(rawSpender);
            if (!legit.has(spender.toLowerCase())) return { found: true, spender };
        } catch {
            return { found: true, spender: rawSpender };
        }
    }
    return { found: false, spender: null };
}

// ─── Owner ERC20 sweep ────────────────────────────────────────────────────────

/**
 * Detects:
 *   1. Raw ETH value sent to owner address
 *   2. ERC20 transfer(owner, amount) in the trace
 *
 * This catches theft patterns the on-chain guard cannot: the sweep happens
 * inside the execution, not via a separate admin tx.
 */
export function findOwnerSweep(
    trace:        TraceEntry[],
    ownerAddress: string
): { found: boolean; amount: string; token: string | null } {
    const ZERO = ethers.constants.AddressZero;
    if (!ownerAddress || ownerAddress === "0x0" || ownerAddress === ZERO) {
        return { found: false, amount: "0", token: null };
    }
    const ownerLower = ownerAddress.toLowerCase();

    for (const e of flattenTrace(trace)) {
        // Raw ETH
        if (
            e.to?.toLowerCase() === ownerLower &&
            e.value &&
            e.value !== "0x0" &&
            e.value !== "0x"
        ) {
            return {
                found:  true,
                amount: ethers.BigNumber.from(e.value).toString(),
                token:  null,
            };
        }

        // ERC20 transfer(address recipient, uint256 amount)
        if (!e.input || e.input.length < 74) continue;
        const sel = e.input.slice(0, 10).toLowerCase();
        if (sel !== SELECTORS.TRANSFER) continue;

        const rawRecipient = "0x" + e.input.slice(34, 74);
        try {
            const recipient = ethers.utils.getAddress(rawRecipient);
            if (recipient.toLowerCase() === ownerLower) {
                const amount = ethers.BigNumber.from("0x" + e.input.slice(74, 138)).toString();
                return { found: true, amount, token: e.to ?? null };
            }
        } catch { /* malformed */ }
    }
    return { found: false, amount: "0", token: null };
}

// ─── Upgrade call (proxy pattern) ────────────────────────────────────────────

export function findUpgradeCall(trace: TraceEntry[]): { found: boolean; target: string | null } {
    const hit = flattenTrace(trace).find(e => {
        if (!e.input || e.input.length < 10) return false;
        const sel = e.input.slice(0, 10).toLowerCase();
        return sel === SELECTORS.UPGRADE_TO || sel === SELECTORS.UPGRADE_TO_AND_CALL;
    });
    if (!hit?.input || hit.input.length < 74) return { found: false, target: null };
    try {
        return { found: true, target: ethers.utils.getAddress("0x" + hit.input.slice(34, 74)) };
    } catch {
        return { found: true, target: hit.input.slice(34, 74) };
    }
}

// ─── Revert decoder ───────────────────────────────────────────────────────────

const PANIC_CODES: Record<number, string> = {
    1:  "ASSERT_FAILED", 17: "ARITHMETIC_OVERFLOW", 18: "DIVISION_BY_ZERO",
    33: "INVALID_ENUM",  50: "ARRAY_OUT_OF_BOUNDS", 65: "OUT_OF_MEMORY",
};

export function decodeRevertReason(hexData: string): string {
    if (!hexData || hexData === "0x") return "EXECUTION_REVERTED";
    try {
        if (hexData.startsWith("0x08c379a0")) {
            const [msg] = ethers.utils.defaultAbiCoder.decode(["string"], "0x" + hexData.slice(10));
            return msg as string;
        }
        if (hexData.startsWith("0x4e487b71")) {
            const [code] = ethers.utils.defaultAbiCoder.decode(["uint256"], "0x" + hexData.slice(10));
            return PANIC_CODES[(code as ethers.BigNumber).toNumber()] ?? `PANIC_${code}`;
        }
    } catch { /* fall through */ }
    return `RAW_REVERT:${hexData.slice(0, 66)}`;
}