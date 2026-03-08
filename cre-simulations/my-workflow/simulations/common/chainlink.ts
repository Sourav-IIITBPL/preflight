// ============================================================================
//  chainlink.ts — Arbitrum Chainlink price feed helpers
//
//  Arbitrum has NO FeedRegistry. Use individual aggregator addresses.
//  Source: https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum
// ============================================================================

import { ethers } from "ethers";
import { THRESHOLDS } from "./types.js";

// token address (lowercase) → token/USD aggregator on Arbitrum One
export const ARBITRUM_FEEDS: Record<string, string> = {
    // Native / WETH
    "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee": "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
    "0x82af49447d8a07e3bd95bd0d56f35241523fbab1": "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
    // Stablecoins
    "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8": "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
    "0xaf88d065e77c8cc2239327c5edb3a432268e5831": "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
    "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9": "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
    "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1": "0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB",
    // Major tokens
    "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f": "0xd0C7101eACbB49F3deCcCc166d238410D6D46d57",
    "0xf97f4df75117a78c1a5a0dbb814af92458539fb4": "0x86E53CF1B873786aC51Be4B21E17D5ec6E083d8F",
    "0x912ce59144191c1204e64559fe8253a0e49e6548": "0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6",
    "0xfc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a": "0xdb98056fecfff59d032ab628337a4887110df3db",
    "0x17fc002b466eec40dae837fc4be5c67993ddbd6f": "0x0809E3d38d1B4214958faf034ABe4B590E34e4A2",
};

export interface OraclePrice {
    feedAddress: string;
    priceUSD:    ethers.BigNumber;   // normalized to 1e18
    rawAnswer:   ethers.BigNumber;
    decimals:    number;
    updatedAt:   number;
    roundId:     ethers.BigNumber;
    isStale:     boolean;
    ageSeconds:  number;
    found:       boolean;
}

const ZERO_ORACLE: OraclePrice = {
    feedAddress: "",
    priceUSD:    ethers.BigNumber.from(0),
    rawAnswer:   ethers.BigNumber.from(0),
    decimals:    8,
    updatedAt:   0,
    roundId:     ethers.BigNumber.from(0),
    isStale:     false,
    ageSeconds:  0,
    found:       false,
};

export async function getTokenPrice(
    evm:           any,
    tokenAddress:  string,
    maxAgeSeconds: number = THRESHOLDS.MAX_ORACLE_AGE_SECONDS
): Promise<OraclePrice> {
    const feedAddress = ARBITRUM_FEEDS[tokenAddress.toLowerCase()];
    if (!feedAddress) return ZERO_ORACLE;

    try {
        const [roundData, feedDecimals] = await Promise.all([
            evm.read({ to: feedAddress, func: "latestRoundData()" }),
            evm.read({ to: feedAddress, func: "decimals()" }),
        ]);

        // CRE returns latestRoundData as an array: [roundId, answer, startedAt, updatedAt, answeredInRound]
        const answer    = ethers.BigNumber.from(roundData[1] ?? roundData.answer);
        const updatedAt = Number(roundData[3] ?? roundData.updatedAt);
        const decimals  = Number(feedDecimals);
        const nowSec    = Math.floor(Date.now() / 1000);
        const ageSeconds = nowSec - updatedAt;

        const priceUSD = answer.mul(ethers.BigNumber.from(10).pow(18 - decimals));

        return {
            feedAddress,
            priceUSD,
            rawAnswer: answer,
            decimals,
            updatedAt,
            roundId:   ethers.BigNumber.from(roundData[0] ?? roundData.roundId),
            isStale:   ageSeconds > maxAgeSeconds,
            ageSeconds,
            found:     true,
        };
    } catch {
        return { ...ZERO_ORACLE, feedAddress, found: false };
    }
}

/**
 * Compute fair expected output for a token→token or ETH→token swap.
 * All arithmetic in 1e36 precision to avoid overflow.
 *
 * Returns:
 *   fairAmountOut    — BigNumber in tokenOut decimals
 *   priceImpactBps   — (fair - actual) / fair × 10000; positive = you got less than fair
 */
export function computeFairOutput(p: {
    amountIn:         ethers.BigNumber;
    tokenInDecimals:  number;
    tokenInPriceUSD:  ethers.BigNumber;   // 1e18 normalized
    tokenOutDecimals: number;
    tokenOutPriceUSD: ethers.BigNumber;   // 1e18 normalized
}): {
    fairAmountOut:  ethers.BigNumber;
    priceImpactBps: (actualOut: ethers.BigNumber) => number;
} {
    if (p.tokenInPriceUSD.isZero() || p.tokenOutPriceUSD.isZero()) {
        return { fairAmountOut: ethers.BigNumber.from(0), priceImpactBps: () => 0 };
    }

    const SCALE = ethers.BigNumber.from(10).pow(36);

    // amountIn → 36 decimal space
    const adjIn = p.amountIn.mul(ethers.BigNumber.from(10).pow(36 - p.tokenInDecimals));

    // fair out in 36-decimal space
    const fair36 = adjIn
        .mul(p.tokenInPriceUSD)
        .div(p.tokenOutPriceUSD)
        .div(ethers.BigNumber.from(10).pow(36 - p.tokenOutDecimals));

    const priceImpactBps = (actualOut: ethers.BigNumber): number => {
        if (fair36.isZero()) return 0;
        const adj    = actualOut.mul(ethers.BigNumber.from(10).pow(36 - p.tokenOutDecimals));
        const diff   = fair36.sub(adj);
        // clamp to JS safe integer range (BPS are small)
        return diff.mul(10000).div(fair36).toNumber();
    };

    return { fairAmountOut: fair36, priceImpactBps };
}