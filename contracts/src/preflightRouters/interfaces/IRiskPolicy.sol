// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VaultGuardResult, LiquidityV2GuardResult} from "../../types/OnChainTypes.sol";
import {VaultOpType, LiquidityOpType} from "../../types/OffChainTypes.sol";
import {ERC4626DecodedRiskReport} from "../../riskpolicies/ERC4626RiskPolicy.sol";
import {LiquidityV2DecodedRiskReport} from "../../riskpolicies/LiquidityV2RiskPolicy.sol";

interface IRiskReportNFT {
    function mint(uint256 packedRiskReport) external returns (uint256 tokenId);
}

interface IERC4626RiskPolicy {
    function evaluate(bytes calldata offChainData, VaultGuardResult memory onChainData, VaultOpType operation)
        external
        pure
        returns (uint256 packedReport);

    function decode(uint256 packedReport) external pure returns (ERC4626DecodedRiskReport memory report);
}

interface ILiquidityV2RiskPolicy {
    function evaluate(bytes calldata offChainData, LiquidityV2GuardResult memory onChainData, LiquidityOpType operation)
        external
        pure
        returns (uint256 packedReport);

    function decode(uint256 packedReport) external pure returns (LiquidityV2DecodedRiskReport memory report);
}
