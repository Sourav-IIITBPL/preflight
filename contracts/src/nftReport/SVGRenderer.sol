// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {PolicyKind, PolicyRiskCategory} from "../types/OnChainTypes.sol";
import "./lib/SVGLib.sol";
import "./lib/SVGParts.sol";

import {ISVGRenderer, RenderContext} from "./interfaces/ISVGRenderer.sol";

/**
 * @title SVGRenderer
 * @notice Redesigned and split renderer for PreFlight Risk Report NFTs.
 *         Uses SVGLib for labels and SVGParts for UI components to avoid 24KB limit.
 */
contract SVGRenderer is ISVGRenderer {
    using Strings for uint256;

    struct DecodedReport {
        PolicyKind kind;
        uint8 operation;
        uint8 version;
        PolicyRiskCategory finalCategory;
        PolicyRiskCategory offChainCategory;
        uint8 compositeScore;
        uint8 onChainScore;
        uint8 offChainScore;
        uint8 onChainCriticalCount;
        uint8 onChainWarningCount;
        uint8 offChainFindingCount;
        bool anyHardBlock;
        bool offChainValid;
        uint32 onChainFlagsPacked;
        uint32 offChainFlagsPacked;
        uint32 tokenFlagsPacked;
        uint16 priceImpactBps;
        uint16 outputDiscrepancyBps;
        uint16 ratioDeviationBps;
        uint8 tokenCriticalCount;
        uint8 tokenWarningCount;
        bool tokenRiskEvaluated;
        uint8 economicSeverityTier;
        uint8 oracleAgeTier;
        uint8 excessPullTier;
        uint8 sharePriceDriftTier;
        uint8 compoundRiskCount;
        bool simulationRevertBlock;
        uint8 sweepSeverityTier;
        bool enhancedPresent;
    }

    function buildTokenURI(uint256 tokenId, RenderContext memory context) external pure returns (string memory) {
        DecodedReport memory report = _decode(context.packedReport);
        string memory svg = _renderSVG(tokenId, context, report);

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name":"',
                        _name(tokenId, report),
                        '","description":"',
                        _description(report),
                        '","image":"data:image/svg+xml;base64,',
                        Base64.encode(bytes(svg)),
                        '","attributes":[',
                        _attributes(context, report),
                        "]}"
                    )
                )
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function _renderSVG(uint256 tokenId, RenderContext memory context, DecodedReport memory report)
        internal
        pure
        returns (string memory)
    {
        string memory categoryColor = SVGLib.getCategoryColor(report.finalCategory);
        string memory kindLabel = SVGLib.getPolicyKindLabel(report.kind);
        string memory opLabel = SVGLib.getOperationLabel(report.kind, report.operation);
        string memory catLabel = SVGLib.getCategoryLabel(report.finalCategory);

        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1280" width="1000" height="1280" fill="none">',
                SVGParts.getDefs(),
                '<rect width="1000" height="1280" rx="30" fill="url(#bg)"/>',
                SVGParts.getHeader(tokenId, kindLabel, opLabel, categoryColor, catLabel),
                SVGParts.getScoreMeter(report.compositeScore, categoryColor),
                SVGParts.getMetricCards(
                    report.onChainScore, report.offChainScore, report.tokenRiskEvaluated ? report.onChainScore : 0
                ),
                _renderFindings(report),
                _renderTiers(report),
                SVGParts.getFooter(
                    _shortAddress(context.owner),
                    _shortAddress(context.sourceMinter),
                    context.mintedBlock,
                    context.mintedAt
                ),
                "</svg>"
            )
        );
    }

    function _renderFindings(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _renderFindingSection(report, 390, 240, "ON-CHAIN FINDINGS", SVGLib.C_ACCENT, 0),
                _renderFindingSection(report, 645, 240, "OFF-CHAIN FINDINGS", SVGLib.C_MED, 1),
                _renderFindingSection(report, 900, 230, "TOKEN RISK FINDINGS", SVGLib.C_TOKEN, 2)
            )
        );
    }

    function _renderFindingSection(
        DecodedReport memory report,
        uint256 y,
        uint256 h,
        string memory title,
        string memory color,
        uint8 section
    ) internal pure returns (string memory) {
        string memory content;
        uint256 x = 85;
        uint256 rowY = y + 70;
        uint32 flags = section == 0
            ? report.onChainFlagsPacked
            : (section == 1 ? report.offChainFlagsPacked : report.tokenFlagsPacked);
        uint8 count;

        for (uint8 i = 0; i < 32; i++) {
            if (((flags >> i) & 1) == 1) {
                if (section == 1 && i == SVGLib.OFFCHAIN_VALID_BIT) continue;

                string memory label = section == 0
                    ? SVGLib.getOnChainLabel(report.kind, i)
                    : (section == 1 ? SVGLib.getOffChainLabel(i) : SVGLib.getTokenLabel(i));

                if (bytes(label).length > 0) {
                    bool crit = section == 0
                        ? SVGLib.isOnChainCritical(report.kind, report.operation, i)
                        : (section == 1 ? SVGLib.isOffChainCritical(i) : SVGLib.isTokenCritical(i));

                    uint256 w = 35 + (bytes(label).length * 8);
                    if (x + w > 940) {
                        x = 85;
                        rowY += 35;
                    }
                    if (rowY < y + h - 20) {
                        content = string(
                            abi.encodePacked(
                                content, SVGParts.getChip(x, rowY, label, crit ? SVGLib.C_CRIT : color, crit)
                            )
                        );
                        x += w + 12;
                        count++;
                    }
                }
            }
        }

        if (count == 0) {
            content = string(
                abi.encodePacked(
                    '<text x="85" y="',
                    (y + 80).toString(),
                    '" font-family="Arial, sans-serif" font-size="16" fill="#8b949e">No findings detected in this section.</text>'
                )
            );
        }

        return string(abi.encodePacked(SVGParts.getSectionFrame(60, y, 880, h, title, color), content));
    }

    function _renderTiers(DecodedReport memory report) internal pure returns (string memory) {
        uint256 y = 1140; // This might need adjustment if footer is at 1150
        // Adjusting footer to 1170 and Tiers to 1110
        return string(
            abi.encodePacked(
                '<text x="60" y="1135" font-family="Arial, sans-serif" font-size="14" font-weight="bold" fill="#8b949e">SEVERITY TIERS</text>',
                _tierBox(180, 1122, "ECON", report.economicSeverityTier),
                _tierBox(320, 1122, "ORACLE", report.oracleAgeTier),
                _tierBox(460, 1122, "PULL", report.excessPullTier),
                _tierBox(600, 1122, "DRIFT", report.sharePriceDriftTier),
                _tierBox(740, 1122, "SWEEP", report.sweepSeverityTier)
            )
        );
    }

    function _tierBox(uint256 x, uint256 y, string memory label, uint8 tier) internal pure returns (string memory) {
        string memory color =
            tier >= 3 ? SVGLib.C_CRIT : (tier >= 2 ? SVGLib.C_MED : (tier >= 1 ? SVGLib.C_WARN : SVGLib.C_INFO));
        return string(
            abi.encodePacked(
                '<rect x="',
                x.toString(),
                '" y="',
                y.toString(),
                '" width="120" height="20" rx="4" fill="',
                color,
                '" fill-opacity="0.1" stroke="',
                color,
                '" stroke-opacity="0.4"/>',
                '<text x="',
                (x + 5).toString(),
                '" y="',
                (y + 15).toString(),
                '" font-family="Arial, sans-serif" font-size="11" fill="#8b949e">',
                label,
                ":</text>",
                '<text x="',
                (x + 115).toString(),
                '" y="',
                (y + 15).toString(),
                '" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="',
                color,
                '" text-anchor="end">',
                SVGLib.getTierLabel(tier),
                "</text>"
            )
        );
    }

    function _name(uint256 tokenId, DecodedReport memory report) internal pure returns (string memory) {
        return string(abi.encodePacked("PreFlight ", SVGLib.getPolicyKindLabel(report.kind), " #", tokenId.toString()));
    }

    function _description(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "Risk report for ",
                SVGLib.getPolicyKindLabel(report.kind),
                ". Score: ",
                uint256(report.compositeScore).toString(),
                "/100. ",
                "Category: ",
                SVGLib.getCategoryLabel(report.finalCategory),
                "."
            )
        );
    }

    function _attributes(RenderContext memory context, DecodedReport memory report)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '{"trait_type":"Policy","value":"',
                SVGLib.getPolicyKindLabel(report.kind),
                '"},',
                '{"trait_type":"Operation","value":"',
                SVGLib.getOperationLabel(report.kind, report.operation),
                '"},',
                '{"trait_type":"Score","display_type":"number","value":',
                uint256(report.compositeScore).toString(),
                "},",
                '{"trait_type":"Category","value":"',
                SVGLib.getCategoryLabel(report.finalCategory),
                '"},',
                '{"trait_type":"Price Impact BPS","value":',
                uint256(report.priceImpactBps).toString(),
                "}"
            )
        );
    }

    function _shortAddress(address account) internal pure returns (string memory) {
        string memory full = Strings.toHexString(uint256(uint160(account)), 20);
        bytes memory raw = bytes(full);
        bytes memory out = new bytes(13);
        out[0] = raw[0];
        out[1] = raw[1];
        out[2] = raw[2];
        out[3] = raw[3];
        out[4] = raw[4];
        out[5] = raw[5];
        out[6] = ".";
        out[7] = ".";
        out[8] = ".";
        out[9] = raw[38];
        out[10] = raw[39];
        out[11] = raw[40];
        out[12] = raw[41];
        return string(out);
    }

    function _decode(uint256 packed) internal pure returns (DecodedReport memory r) {
        r.kind = PolicyKind((packed >> SVGLib.SHIFT_POLICY_KIND) & 3);
        r.operation = uint8((packed >> SVGLib.SHIFT_OPERATION) & 15);
        r.version = uint8((packed >> SVGLib.SHIFT_POLICY_VERSION) & 255);
        r.finalCategory = PolicyRiskCategory((packed >> SVGLib.SHIFT_FINAL_CATEGORY) & 3);
        r.offChainCategory = PolicyRiskCategory((packed >> SVGLib.SHIFT_OFFCHAIN_CATEGORY) & 3);
        r.compositeScore = uint8((packed >> SVGLib.SHIFT_COMPOSITE_SCORE) & 255);
        r.onChainScore = uint8((packed >> SVGLib.SHIFT_ONCHAIN_SCORE) & 255);
        r.offChainScore = uint8((packed >> SVGLib.SHIFT_OFFCHAIN_SCORE) & 255);
        r.onChainCriticalCount = uint8((packed >> SVGLib.SHIFT_ONCHAIN_CRITICAL) & 63);
        r.onChainWarningCount = uint8((packed >> SVGLib.SHIFT_ONCHAIN_WARNING) & 63);
        r.offChainFindingCount = uint8((packed >> SVGLib.SHIFT_OFFCHAIN_FINDINGS) & 63);
        r.anyHardBlock = ((packed >> SVGLib.SHIFT_ANY_HARD_BLOCK) & 1) == 1;
        r.offChainValid = ((packed >> SVGLib.SHIFT_OFFCHAIN_VALID) & 1) == 1;
        r.onChainFlagsPacked = uint32((packed >> SVGLib.SHIFT_ONCHAIN_FLAGS) & 0xFFFFFFFF);
        r.offChainFlagsPacked = uint32((packed >> SVGLib.SHIFT_OFFCHAIN_FLAGS) & 0xFFFFFFFF);
        r.tokenFlagsPacked = uint32((packed >> SVGLib.SHIFT_TOKEN_FLAGS) & 0xFFFFFFFF);
        r.priceImpactBps = uint16((packed >> SVGLib.SHIFT_PRICE_IMPACT) & 0xFFFF);
        r.outputDiscrepancyBps = uint16((packed >> SVGLib.SHIFT_OUTPUT_DISCREPANCY) & 0xFFFF);
        r.ratioDeviationBps = uint16((packed >> SVGLib.SHIFT_RATIO_DEVIATION) & 0xFFFF);
        r.tokenCriticalCount = uint8((packed >> SVGLib.SHIFT_TOKEN_CRITICAL) & 63);
        r.tokenWarningCount = uint8((packed >> SVGLib.SHIFT_TOKEN_WARNING) & 63);
        r.tokenRiskEvaluated = ((packed >> SVGLib.SHIFT_TOKEN_EVALUATED) & 1) == 1;
        r.economicSeverityTier = uint8((packed >> SVGLib.SHIFT_ECONOMIC_TIER) & 7);
        r.oracleAgeTier = uint8((packed >> SVGLib.SHIFT_ORACLE_AGE_TIER) & 7);
        r.excessPullTier = uint8((packed >> SVGLib.SHIFT_EXCESS_PULL_TIER) & 7);
        r.sharePriceDriftTier = uint8((packed >> SVGLib.SHIFT_SHARE_DRIFT_TIER) & 7);
        r.compoundRiskCount = uint8((packed >> SVGLib.SHIFT_COMPOUND_COUNT) & 7);
        r.simulationRevertBlock = ((packed >> SVGLib.SHIFT_SIM_REVERT_BLOCK) & 1) == 1;
        r.sweepSeverityTier = uint8((packed >> SVGLib.SHIFT_SWEEP_TIER) & 7);
        r.enhancedPresent = ((packed >> SVGLib.SHIFT_ENHANCED_PRESENT) & 1) == 1;
    }
}
