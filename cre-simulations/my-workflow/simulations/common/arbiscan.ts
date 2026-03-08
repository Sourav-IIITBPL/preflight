// ============================================================================
//  arbiscan.ts — Contract verification via Arbiscan API
//
//  BUG IN ORIGINAL: checked `response.status === 200` (always true for Arbiscan).
//  Correct check: body.status === "1" AND SourceCode is non-empty.
// ============================================================================

export interface VerificationResult {
    isVerified:      boolean;
    contractName:    string;
    compilerVersion: string;
}

const UNVERIFIED: VerificationResult = { isVerified: false, contractName: "", compilerVersion: "" };

export async function checkContractVerified(
    http:    any,
    address: string,
    apiKey:  string = process.env.ARBISCAN_API_KEY ?? ""
): Promise<VerificationResult> {
    try {
        const url = `https://api.arbiscan.io/api?module=contract&action=getsourcecode` +
                    `&address=${address}&apikey=${apiKey}`;
        const response = await http.get({ url });
        const body     = response?.data ?? response?.body ?? response;

        if (!body || body.status !== "1") return UNVERIFIED;

        const r          = Array.isArray(body.result) ? body.result[0] : body.result;
        const sourceCode = r?.SourceCode ?? "";

        return {
            isVerified:      !!sourceCode && sourceCode.length > 0,
            contractName:    r?.ContractName   ?? "",
            compilerVersion: r?.CompilerVersion ?? "",
        };
    } catch {
        return UNVERIFIED;
    }
}