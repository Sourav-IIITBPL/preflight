// ============================================================================
//  main.ts — CRE Workflow entry point
//
//  Routes HTTP trigger to the correct simulation based on context.data.type
//
//  Supported types:
//    VAULT     → vaultLogic (deposit | mint | withdraw | redeem)
//    SWAP      → swapLogic  (exactTokensIn | exactTokensOut | exactETHIn |
//                            exactETHOut | exactTokensForETH | tokensForExactETH)
//    LIQUIDITY → liquidityLogic (add | addETH | remove | removeETH)
// ============================================================================

import { swapLogic      } from "./simulations/swapLogic.js";
import { vaultLogic     } from "./simulations/vaultLogic.js";
import { liquidityLogic } from "./simulations/liquidityLogic.js";

export const onHttpTrigger = async (runtime: any, context: any) => {
    const { type } = context.data;

    if (!type) {
        return { error: "MISSING_TYPE", message: "context.data.type must be VAULT | SWAP | LIQUIDITY" };
    }

    try {
        switch (type) {
            case "VAULT":     return await vaultLogic(runtime, context);
            case "SWAP":      return await swapLogic(runtime, context);
            case "LIQUIDITY": return await liquidityLogic(runtime, context);
            default:
                return { error: "UNKNOWN_TYPE", message: `Unknown type '${type}'` };
        }
    } catch (err: any) {
        return {
            isSafe:      false,
            riskLevel:   "CRITICAL",
            riskScore:   100,
            error:       "UNHANDLED_SIMULATION_ERROR",
            message:     err?.message ?? "Unknown error",
            simulatedAt: Math.floor(Date.now() / 1000),
            network:     "arbitrum-mainnet",
        };
    }
};