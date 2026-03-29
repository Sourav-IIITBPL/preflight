// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VaultGuardResult, LiquidityV2GuardResult, SwapV2GuardResult} from "../../types/OnChainTypes.sol";
import {VaultOpType, LiquidityOpType, SwapOpType} from "../../types/OffChainTypes.sol";
import {ERC4626DecodedRiskReport} from "../../riskpolicies/ERC4626RiskPolicy.sol";
import {LiquidityV2DecodedRiskReport} from "../../riskpolicies/LiquidityV2RiskPolicy.sol";
import {SwapV2DecodedRiskReport} from "../../riskpolicies/SwapV2RiskPolicy.sol";

/**
 * @author Sourav-IITBPL
 * @notice Interface for minting risk report NFTs from packed policy outputs.
 */
interface IRiskReportNFT {
    /**
     * @notice Mints a new NFT for a packed risk report.
     * @param packedRiskReport Packed risk report value.
     * @return tokenId Minted NFT identifier.
     */
    function mint(uint256 packedRiskReport) external returns (uint256 tokenId);
}

/**
 * @author Sourav-IITBPL
 * @notice Interface for ERC-4626 risk policy evaluation and decoding.
 */
interface IERC4626RiskPolicy {
    /**
     * @notice Evaluates an ERC-4626 operation into a packed risk report.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @param onChainData Guard result from the vault guard.
     * @param operation ERC-4626 operation being evaluated.
     * @return packedReport Packed risk report value.
     */
    function evaluate(bytes calldata offChainData, VaultGuardResult memory onChainData, VaultOpType operation)
        external
        pure
        returns (uint256 packedReport);

    /**
     * @notice Decodes a packed ERC-4626 risk report.
     * @param packedReport Packed risk report value.
     * @return report Decoded ERC-4626 risk report.
     */
    function decode(uint256 packedReport) external pure returns (ERC4626DecodedRiskReport memory report);
}

/**
 * @author Sourav-IITBPL
 * @notice Interface for Uniswap V2 liquidity risk policy evaluation and decoding.
 */
interface ILiquidityV2RiskPolicy {
    /**
     * @notice Evaluates a liquidity operation into a packed risk report.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @param onChainData Guard result from the liquidity guard.
     * @param operation Liquidity operation being evaluated.
     * @return packedReport Packed risk report value.
     */
    function evaluate(bytes calldata offChainData, LiquidityV2GuardResult memory onChainData, LiquidityOpType operation)
        external
        pure
        returns (uint256 packedReport);

    /**
     * @notice Decodes a packed liquidity risk report.
     * @param packedReport Packed risk report value.
     * @return report Decoded liquidity risk report.
     */
    function decode(uint256 packedReport) external pure returns (LiquidityV2DecodedRiskReport memory report);
}

interface ISwapV2RiskPolicy {
    /**
     * @notice Evaluates a swap operation into a packed risk report.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @param onChainData Guard result from the swap guard.
     * @param operation Swap operation being evaluated.
     * @return packedReport Packed risk report value.
     */
    function evaluate(bytes calldata offChainData, SwapV2GuardResult memory onChainData, SwapOpType operation)
        external
        pure
        returns (uint256 packedReport);

    /**
     * @notice Decodes a packed swap risk report.
     * @param packedReport Packed risk report value.
     * @return report Decoded swap risk report.
     */
    function decode(uint256 packedReport) external pure returns (SwapV2DecodedRiskReport memory report);
}

