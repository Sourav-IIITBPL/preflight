// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {PolicyKind, PolicyRiskCategory} from "./types/OnChainTypes.sol";

/**
 * @title SVGRenderer
 * @author Sourav-IITBPL
 * @notice Pure renderer/decoder for packed PreFlight policy reports.
 *         It converts a single packed `uint256` into:
 *         1. a user-friendly SVG
 *         2. fully on-chain JSON metadata
 *
 *         The bit layout mirrors `BaseRiskPolicy`.
 */
library SVGRenderer {
    using Strings for uint256;

    struct RenderContext {
        uint256 packedReport;
        address owner;
        address sourceMinter;
        uint64 mintedAt;
        uint64 mintedBlock;
    }

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

    string internal constant C_BG = "#07111f";
    string internal constant C_PANEL = "#0d1b2a";
    string internal constant C_PANEL_ALT = "#102338";
    string internal constant C_TEXT = "#e8eef6";
    string internal constant C_MUTED = "#8aa0b8";
    string internal constant C_BORDER = "#1d3853";
    string internal constant C_INFO = "#3fb950";
    string internal constant C_WARN = "#f4b942";
    string internal constant C_MED = "#f97316";
    string internal constant C_CRIT = "#ef4444";
    string internal constant C_ACCENT = "#38bdf8";
    string internal constant C_TOKEN = "#c084fc";
    string internal constant C_SOFT = "#1f4b7a";

    uint8 internal constant SHIFT_ONCHAIN_FLAGS = 0;
    uint8 internal constant SHIFT_OFFCHAIN_FLAGS = 32;
    uint8 internal constant SHIFT_COMPOSITE_SCORE = 64;
    uint8 internal constant SHIFT_ONCHAIN_SCORE = 72;
    uint8 internal constant SHIFT_OFFCHAIN_SCORE = 80;
    uint8 internal constant SHIFT_FINAL_CATEGORY = 88;
    uint8 internal constant SHIFT_OFFCHAIN_CATEGORY = 90;
    uint8 internal constant SHIFT_ANY_HARD_BLOCK = 92;
    uint8 internal constant SHIFT_OFFCHAIN_VALID = 93;
    uint8 internal constant SHIFT_ONCHAIN_CRITICAL = 94;
    uint8 internal constant SHIFT_ONCHAIN_WARNING = 100;
    uint8 internal constant SHIFT_OFFCHAIN_FINDINGS = 106;
    uint8 internal constant SHIFT_PRICE_IMPACT = 112;
    uint8 internal constant SHIFT_OUTPUT_DISCREPANCY = 128;
    uint8 internal constant SHIFT_RATIO_DEVIATION = 144;
    uint8 internal constant SHIFT_OPERATION = 160;
    uint8 internal constant SHIFT_POLICY_KIND = 164;
    uint8 internal constant SHIFT_POLICY_VERSION = 166;
    uint8 internal constant SHIFT_TOKEN_FLAGS = 174;
    uint8 internal constant SHIFT_TOKEN_CRITICAL = 206;
    uint8 internal constant SHIFT_TOKEN_WARNING = 212;
    uint8 internal constant SHIFT_TOKEN_EVALUATED = 218;
    uint8 internal constant SHIFT_ECONOMIC_TIER = 219;
    uint8 internal constant SHIFT_ORACLE_AGE_TIER = 222;
    uint8 internal constant SHIFT_EXCESS_PULL_TIER = 225;
    uint8 internal constant SHIFT_SHARE_DRIFT_TIER = 228;
    uint8 internal constant SHIFT_COMPOUND_COUNT = 231;
    uint8 internal constant SHIFT_SIM_REVERT_BLOCK = 234;
    uint8 internal constant SHIFT_SWEEP_TIER = 235;
    uint8 internal constant SHIFT_ENHANCED_PRESENT = 238;

    uint8 internal constant OFFCHAIN_VALID = 0;

    function buildTokenURI(uint256 tokenId, RenderContext memory context) internal pure returns (string memory) {
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
        string memory categoryColor = _categoryColor(report.finalCategory);

        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1280" width="1000" height="1280">',
                _defs(),
                '<rect width="1000" height="1280" rx="28" fill="url(#bg)"/>',
                '<rect x="14" y="14" width="972" height="1252" rx="24" fill="none" stroke="',
                categoryColor,
                '" stroke-opacity="0.48" stroke-width="2"/>',
                '<rect x="26" y="26" width="948" height="210" rx="24" fill="url(#hero)"/>',
                _hero(tokenId, context, report),
                _meters(report, categoryColor),
                _onChainPanel(report),
                _offChainPanel(report),
                _tokenPanel(report),
                _footer(context, report),
                "</svg>"
            )
        );
    }

    function _defs() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<defs>",
                '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">',
                '<stop offset="0%" stop-color="#04101d"/>',
                '<stop offset="100%" stop-color="#071726"/>',
                "</linearGradient>",
                '<linearGradient id="hero" x1="0" y1="0" x2="1" y2="1">',
                '<stop offset="0%" stop-color="#0d2033"/>',
                '<stop offset="50%" stop-color="#10263d"/>',
                '<stop offset="100%" stop-color="#0b1828"/>',
                "</linearGradient>",
                '<linearGradient id="meter" x1="0" y1="0" x2="1" y2="0">',
                '<stop offset="0%" stop-color="#3fb950"/>',
                '<stop offset="35%" stop-color="#f4b942"/>',
                '<stop offset="65%" stop-color="#f97316"/>',
                '<stop offset="100%" stop-color="#ef4444"/>',
                "</linearGradient>",
                '<filter id="softGlow"><feGaussianBlur stdDeviation="7" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
                "</defs>"
            )
        );
    }

    function _hero(uint256 tokenId, RenderContext memory context, DecodedReport memory report)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(_heroTop(tokenId, report), _heroBottom(context)));
    }

    function _heroTop(uint256 tokenId, DecodedReport memory report) internal pure returns (string memory) {
        return string(abi.encodePacked(_heroTitle(), _heroBadges(tokenId, report)));
    }

    function _heroTitle() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<text x="64" y="72" font-family="Georgia, serif" font-size="36" font-weight="700" fill="',
                C_TEXT,
                '">PreFlight Risk Report</text>',
                '<text x="64" y="103" font-family="Verdana, sans-serif" font-size="16" fill="',
                C_MUTED,
                '">Fully on-chain decoded audit NFT for guarded execution</text>'
            )
        );
    }

    function _heroBadges(uint256 tokenId, DecodedReport memory report) internal pure returns (string memory) {
        string memory categoryColor = _categoryColor(report.finalCategory);
        string memory hardBlockLabel = report.anyHardBlock ? "HARD BLOCK" : "NO HARD BLOCK";
        string memory hardBlockColor = report.anyHardBlock ? C_CRIT : C_INFO;

        return string(
            abi.encodePacked(
                _badge(64, 132, 138, 34, categoryColor, _categoryLabel(report.finalCategory)),
                _badge(214, 132, 230, 34, C_ACCENT, _operationLabel(report.kind, report.operation)),
                _badge(456, 132, 152, 34, hardBlockColor, hardBlockLabel),
                _badge(756, 52, 174, 32, C_SOFT, string(abi.encodePacked("TOKEN #", tokenId.toString()))),
                _badge(756, 96, 174, 32, categoryColor, _policyKindLabel(report.kind))
            )
        );
    }

    function _heroBottom(RenderContext memory context) internal pure returns (string memory) {
        string memory ownerText = _shortAddress(context.owner);
        string memory minterText = _shortAddress(context.sourceMinter);

        return string(
            abi.encodePacked(
                '<text x="64" y="192" font-family="Verdana, sans-serif" font-size="14" fill="',
                C_MUTED,
                '">Owner</text>',
                '<text x="64" y="214" font-family="monospace" font-size="18" fill="',
                C_TEXT,
                '">',
                ownerText,
                "</text>",
                '<text x="344" y="192" font-family="Verdana, sans-serif" font-size="14" fill="',
                C_MUTED,
                '">Minter</text>',
                '<text x="344" y="214" font-family="monospace" font-size="18" fill="',
                C_TEXT,
                '">',
                minterText,
                "</text>",
                '<text x="628" y="192" font-family="Verdana, sans-serif" font-size="14" fill="',
                C_MUTED,
                '">Minted</text>',
                '<text x="628" y="214" font-family="monospace" font-size="18" fill="',
                C_TEXT,
                '">block ',
                uint256(context.mintedBlock).toString(),
                " / ts ",
                uint256(context.mintedAt).toString(),
                "</text>"
            )
        );
    }

    function _onChainPanel(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _sectionFrame(44, 316, 912, 220, "ON-CHAIN FINDINGS", C_ACCENT, _onChainSubtitle(report)),
                _renderOnChainChips(report, 316)
            )
        );
    }

    function _offChainPanel(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _sectionFrame(44, 566, 912, 292, "OFF-CHAIN FINDINGS", C_MED, _offChainSubtitle(report)),
                _renderOffChainChips(report, 566)
            )
        );
    }

    function _tokenPanel(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _sectionFrame(44, 888, 912, 252, "TOKEN RISK", C_TOKEN, _tokenSubtitle(report)),
                _renderTokenChips(report, 888)
            )
        );
    }

    function _meters(DecodedReport memory report, string memory categoryColor) internal pure returns (string memory) {
        uint256 markerX = 72 + (uint256(report.compositeScore) * 830) / 100;

        return string(
            abi.encodePacked(
                _metricCard(44, 252, 210, 86, "Composite", report.compositeScore, categoryColor),
                _metricCard(274, 252, 210, 86, "On-Chain", report.onChainScore, C_ACCENT),
                _metricCard(504, 252, 210, 86, "Off-Chain", report.offChainScore, C_MED),
                _metricTextCard(734, 252, 222, 86, "Findings", _findingSummary(report)),
                '<rect x="58" y="360" width="854" height="18" rx="9" fill="#11263a"/>',
                '<rect x="58" y="360" width="854" height="18" rx="9" fill="url(#meter)"/>',
                '<circle cx="',
                markerX.toString(),
                '" cy="369" r="12" fill="#06111d" stroke="',
                categoryColor,
                '" stroke-width="3" filter="url(#softGlow)"/>',
                '<circle cx="',
                markerX.toString(),
                '" cy="369" r="5" fill="',
                categoryColor,
                '"/>',
                '<text x="58" y="398" font-family="Verdana, sans-serif" font-size="13" fill="#3fb950">INFO</text>',
                '<text x="310" y="398" font-family="Verdana, sans-serif" font-size="13" fill="#f4b942">WARNING</text>',
                '<text x="548" y="398" font-family="Verdana, sans-serif" font-size="13" fill="#f97316">MEDIUM</text>',
                '<text x="815" y="398" font-family="Verdana, sans-serif" font-size="13" fill="#ef4444">CRITICAL</text>'
            )
        );
    }

    function _findingSummary(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                uint256(_countSetBits32(report.onChainFlagsPacked)).toString(),
                " on / ",
                uint256(_countSetBits32(_clearBit(report.offChainFlagsPacked, OFFCHAIN_VALID))).toString(),
                " off / ",
                uint256(_countSetBits32(report.tokenFlagsPacked)).toString(),
                " token"
            )
        );
    }

    function _metricCard(
        uint256 x,
        uint256 y,
        uint256 w,
        uint256 h,
        string memory title,
        uint256 value,
        string memory color
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(_metricCardFrame(x, y, w, h), _metricCardContent(x, y, title, value, color)));
    }

    function _metricTextCard(uint256 x, uint256 y, uint256 w, uint256 h, string memory title, string memory value)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(_metricCardFrame(x, y, w, h), _metricTextCardContent(x, y, title, value)));
    }

    function _metricCardFrame(uint256 x, uint256 y, uint256 w, uint256 h) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<rect x="',
                x.toString(),
                '" y="',
                y.toString(),
                '" width="',
                w.toString(),
                '" height="',
                h.toString(),
                '" rx="20" fill="',
                C_PANEL,
                '" stroke="',
                C_BORDER,
                '"/>'
            )
        );
    }

    function _metricCardContent(uint256 x, uint256 y, string memory title, uint256 value, string memory color)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<text x="',
                (x + 20).toString(),
                '" y="',
                (y + 28).toString(),
                '" font-family="Verdana, sans-serif" font-size="13" fill="',
                C_MUTED,
                '">',
                title,
                "</text>",
                '<text x="',
                (x + 20).toString(),
                '" y="',
                (y + 63).toString(),
                '" font-family="Georgia, serif" font-size="34" font-weight="700" fill="',
                color,
                '">',
                value.toString(),
                '<tspan font-size="18" fill="',
                C_MUTED,
                '">/100</tspan></text>'
            )
        );
    }

    function _metricTextCardContent(uint256 x, uint256 y, string memory title, string memory value)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<text x="',
                (x + 20).toString(),
                '" y="',
                (y + 28).toString(),
                '" font-family="Verdana, sans-serif" font-size="13" fill="',
                C_MUTED,
                '">',
                title,
                "</text>",
                '<text x="',
                (x + 20).toString(),
                '" y="',
                (y + 60).toString(),
                '" font-family="Verdana, sans-serif" font-size="18" fill="',
                C_TEXT,
                '">',
                value,
                "</text>"
            )
        );
    }

    function _sectionFrame(
        uint256 x,
        uint256 y,
        uint256 w,
        uint256 h,
        string memory title,
        string memory accent,
        string memory subtitle
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(_sectionFrameBox(x, y, w, h, accent), _sectionFrameText(x, y, title, subtitle)));
    }

    function _sectionFrameBox(uint256 x, uint256 y, uint256 w, uint256 h, string memory accent)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<rect x="',
                x.toString(),
                '" y="',
                y.toString(),
                '" width="',
                w.toString(),
                '" height="',
                h.toString(),
                '" rx="24" fill="',
                C_PANEL_ALT,
                '" stroke="',
                C_BORDER,
                '"/>',
                '<rect x="',
                x.toString(),
                '" y="',
                y.toString(),
                '" width="',
                w.toString(),
                '" height="12" rx="24" fill="',
                accent,
                '" fill-opacity="0.22"/>'
            )
        );
    }

    function _sectionFrameText(uint256 x, uint256 y, string memory title, string memory subtitle)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<text x="',
                (x + 24).toString(),
                '" y="',
                (y + 42).toString(),
                '" font-family="Georgia, serif" font-size="28" font-weight="700" fill="',
                C_TEXT,
                '">',
                title,
                "</text>",
                '<text x="',
                (x + 24).toString(),
                '" y="',
                (y + 68).toString(),
                '" font-family="Verdana, sans-serif" font-size="14" fill="',
                C_MUTED,
                '">',
                subtitle,
                "</text>"
            )
        );
    }

    function _renderOnChainChips(DecodedReport memory report, uint256 baseY) internal pure returns (string memory) {
        return _renderFlagSection(report.kind, report.operation, report.onChainFlagsPacked, 0, baseY + 94);
    }

    function _renderOffChainChips(DecodedReport memory report, uint256 baseY) internal pure returns (string memory) {
        return _renderFlagSection(report.kind, report.operation, report.offChainFlagsPacked, 1, baseY + 94);
    }

    function _renderTokenChips(DecodedReport memory report, uint256 baseY) internal pure returns (string memory) {
        if (!report.tokenRiskEvaluated) {
            return _emptyChip("Token analysis unavailable", baseY + 106, C_MUTED);
        }
        return _renderFlagSection(report.kind, report.operation, report.tokenFlagsPacked, 2, baseY + 94);
    }

    function _renderFlagSection(PolicyKind kind, uint8 operation, uint32 packed, uint8 section, uint256 startY)
        internal
        pure
        returns (string memory out)
    {
        uint256 x = 68;
        uint256 y = startY;
        uint8 shown;
        uint8 maxBits = section == 0 ? _onChainFlagCount(kind) : (section == 1 ? 27 : 28);

        for (uint8 i = 0; i < maxBits;) {
            if (_isSet(packed, i)) {
                if (section == 1 && i == OFFCHAIN_VALID) {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                string memory label = section == 0
                    ? _onChainLabel(kind, operation, i)
                    : (section == 1 ? _offChainLabel(i) : _tokenLabel(i));

                if (bytes(label).length > 0) {
                    bool critical = section == 0
                        ? _isOnChainCritical(kind, operation, i)
                        : (section == 1 ? _isOffChainCritical(i) : _isTokenCritical(i));

                    string memory chipColor = critical ? C_CRIT : (section == 2 ? C_TOKEN : C_WARN);
                    uint256 width = _chipWidth(label);

                    if (x + width > 900) {
                        x = 68;
                        y += 30;
                    }

                    out = string(abi.encodePacked(out, _chip(x, y, width, chipColor, label, critical ? "C" : "W")));
                    x += width + 10;
                    shown++;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (shown == 0) {
            out = _emptyChip("No triggered findings", startY + 12, C_INFO);
        }
    }

    function _chip(uint256 x, uint256 y, uint256 width, string memory color, string memory label, string memory tier)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(_chipFrame(x, y, width, color), _chipText(x, y, width, color, label, tier)));
    }

    function _chipFrame(uint256 x, uint256 y, uint256 width, string memory color)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<rect x="',
                x.toString(),
                '" y="',
                y.toString(),
                '" width="',
                width.toString(),
                '" height="22" rx="11" fill="',
                color,
                '" fill-opacity="0.11" stroke="',
                color,
                '" stroke-opacity="0.7"/>',
                '<circle cx="',
                (x + 14).toString(),
                '" cy="',
                (y + 11).toString(),
                '" r="4" fill="',
                color,
                '"/>'
            )
        );
    }

    function _chipText(
        uint256 x,
        uint256 y,
        uint256 width,
        string memory color,
        string memory label,
        string memory tier
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<text x="',
                (x + 26).toString(),
                '" y="',
                (y + 15).toString(),
                '" font-family="Verdana, sans-serif" font-size="11" fill="',
                C_TEXT,
                '">',
                label,
                "</text>",
                '<text x="',
                (x + width - 14).toString(),
                '" y="',
                (y + 15).toString(),
                '" font-family="monospace" font-size="10" fill="',
                color,
                '" text-anchor="middle">',
                tier,
                "</text>"
            )
        );
    }

    function _emptyChip(string memory label, uint256 y, string memory color) internal pure returns (string memory) {
        return _chip(68, y, _chipWidth(label), color, label, "-");
    }

    function _footer(RenderContext memory context, DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<rect x="44" y="1170" width="912" height="80" rx="22" fill="',
                C_PANEL,
                '" stroke="',
                C_BORDER,
                '"/>',
                _footerLeft(report),
                _footerRight(context)
            )
        );
    }

    function _footerLeft(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<text x="68" y="1201" font-family="Verdana, sans-serif" font-size="13" fill="',
                C_MUTED,
                '">Encoded Metrics</text>',
                '<text x="68" y="1228" font-family="monospace" font-size="15" fill="',
                C_TEXT,
                '">priceImpact=',
                uint256(report.priceImpactBps).toString(),
                "bps  outputDiscrepancy=",
                uint256(report.outputDiscrepancyBps).toString(),
                "bps  ratioDeviation=",
                uint256(report.ratioDeviationBps).toString(),
                "bps</text>",
                '<text x="68" y="1248" font-family="Verdana, sans-serif" font-size="12" fill="',
                C_MUTED,
                '">economicTier=',
                uint256(report.economicSeverityTier).toString(),
                "  oracleTier=",
                uint256(report.oracleAgeTier).toString(),
                "  excessPullTier=",
                uint256(report.excessPullTier).toString(),
                "  driftTier=",
                uint256(report.sharePriceDriftTier).toString(),
                "  compound=",
                uint256(report.compoundRiskCount).toString(),
                "  sweepTier=",
                uint256(report.sweepSeverityTier).toString(),
                "</text>"
            )
        );
    }

    function _footerRight(RenderContext memory context) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<text x="926" y="1205" font-family="monospace" font-size="12" fill="',
                C_MUTED,
                '" text-anchor="end">packed=0x',
                _toMinimalHex(context.packedReport),
                "</text>"
            )
        );
    }

    function _name(uint256 tokenId, DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "PreFlight ",
                _policyKindLabel(report.kind),
                " ",
                _operationLabel(report.kind, report.operation),
                " #",
                tokenId.toString()
            )
        );
    }

    function _description(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "Packed on-chain risk report for ",
                _policyKindLabel(report.kind),
                " ",
                _operationLabel(report.kind, report.operation),
                ". Final category: ",
                _categoryLabel(report.finalCategory),
                ". Composite score: ",
                uint256(report.compositeScore).toString(),
                "/100. This NFT decodes on-chain findings, off-chain findings, token risk, and encoded severity tiers directly from the stored packed report."
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
                _baseAttributes(report),
                ",",
                _scoreAttributes(report),
                ",",
                _findingAttributes(report),
                ",",
                _footerAttributes(context, report)
            )
        );
    }

    function _baseAttributes(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _attr("Policy Kind", _policyKindLabel(report.kind)),
                ",",
                _attr("Operation", _operationLabel(report.kind, report.operation)),
                ",",
                _attr("Final Category", _categoryLabel(report.finalCategory)),
                ",",
                _attr("Off-Chain Category", _categoryLabel(report.offChainCategory))
            )
        );
    }

    function _scoreAttributes(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _numAttr("Composite Score", report.compositeScore),
                ",",
                _numAttr("On-Chain Score", report.onChainScore),
                ",",
                _numAttr("Off-Chain Score", report.offChainScore)
            )
        );
    }

    function _findingAttributes(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _numAttr("On-Chain Triggered Flags", _countSetBits32(report.onChainFlagsPacked)),
                ",",
                _numAttr(
                    "Off-Chain Triggered Flags", _countSetBits32(_clearBit(report.offChainFlagsPacked, OFFCHAIN_VALID))
                ),
                ",",
                _numAttr("Token Triggered Flags", _countSetBits32(report.tokenFlagsPacked)),
                ",",
                _attr("Hard Block", report.anyHardBlock ? "YES" : "NO"),
                ",",
                _attr("Off-Chain Valid", report.offChainValid ? "YES" : "NO")
            )
        );
    }

    function _footerAttributes(RenderContext memory context, DecodedReport memory report)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                _numAttr("Price Impact BPS", report.priceImpactBps),
                ",",
                _numAttr("Output Discrepancy BPS", report.outputDiscrepancyBps),
                ",",
                _numAttr("Ratio Deviation BPS", report.ratioDeviationBps),
                ",",
                _numAttr("Minted Block", context.mintedBlock),
                ",",
                _attr("Source Minter", _hexAddress(context.sourceMinter))
            )
        );
    }

    function _attr(string memory trait, string memory value) internal pure returns (string memory) {
        return string(abi.encodePacked('{"trait_type":"', trait, '","value":"', value, '"}'));
    }

    function _numAttr(string memory trait, uint256 value) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked('{"trait_type":"', trait, '","display_type":"number","value":', value.toString(), "}")
            );
    }

    function _onChainSubtitle(DecodedReport memory report) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                _policyKindLabel(report.kind),
                " / ",
                _operationLabel(report.kind, report.operation),
                " / ",
                uint256(_countSetBits32(report.onChainFlagsPacked)).toString(),
                " flagged conditions"
            )
        );
    }

    function _offChainSubtitle(DecodedReport memory report) internal pure returns (string memory) {
        return report.offChainValid
            ? string(
                abi.encodePacked(
                    uint256(_countSetBits32(_clearBit(report.offChainFlagsPacked, OFFCHAIN_VALID))).toString(),
                    " off-chain findings decoded from simulation and trace analysis"
                )
            )
            : "No off-chain payload was marked valid for this report";
    }

    function _tokenSubtitle(DecodedReport memory report) internal pure returns (string memory) {
        return report.tokenRiskEvaluated
            ? string(
                abi.encodePacked(
                    uint256(_countSetBits32(report.tokenFlagsPacked)).toString(),
                    " token-level findings / ",
                    uint256(report.tokenCriticalCount).toString(),
                    " critical / ",
                    uint256(report.tokenWarningCount).toString(),
                    " warning"
                )
            )
            : "Token analysis was not included in the packed report";
    }

    function _badge(uint256 x, uint256 y, uint256 width, uint256 height, string memory color, string memory label)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<rect x="',
                x.toString(),
                '" y="',
                y.toString(),
                '" width="',
                width.toString(),
                '" height="',
                height.toString(),
                '" rx="',
                (height / 2).toString(),
                '" fill="',
                color,
                '" fill-opacity="0.13" stroke="',
                color,
                '" stroke-opacity="0.75"/>',
                '<text x="',
                (x + (width / 2)).toString(),
                '" y="',
                (y + 22).toString(),
                '" font-family="Verdana, sans-serif" font-size="12" fill="',
                color,
                '" text-anchor="middle">',
                label,
                "</text>"
            )
        );
    }

    function _categoryColor(PolicyRiskCategory category) internal pure returns (string memory) {
        if (category == PolicyRiskCategory.INFO) return C_INFO;
        if (category == PolicyRiskCategory.WARNING) return C_WARN;
        if (category == PolicyRiskCategory.MEDIUM) return C_MED;
        return C_CRIT;
    }

    function _categoryLabel(PolicyRiskCategory category) internal pure returns (string memory) {
        if (category == PolicyRiskCategory.INFO) return "INFO";
        if (category == PolicyRiskCategory.WARNING) return "WARNING";
        if (category == PolicyRiskCategory.MEDIUM) return "MEDIUM";
        return "CRITICAL";
    }

    function _policyKindLabel(PolicyKind kind) internal pure returns (string memory) {
        if (kind == PolicyKind.ERC4626) return "ERC4626";
        if (kind == PolicyKind.SWAP_V2) return "SWAP V2";
        return "LIQUIDITY V2";
    }

    function _operationLabel(PolicyKind kind, uint8 operation) internal pure returns (string memory) {
        if (kind == PolicyKind.ERC4626) {
            if (operation == 0) return "DEPOSIT";
            if (operation == 1) return "MINT";
            if (operation == 2) return "WITHDRAW";
            return "REDEEM";
        }
        if (kind == PolicyKind.SWAP_V2) {
            if (operation == 0) return "EXACT TOKENS IN";
            if (operation == 1) return "EXACT TOKENS OUT";
            if (operation == 2) return "EXACT ETH IN";
            if (operation == 3) return "EXACT ETH OUT";
            if (operation == 4) return "TOKENS FOR ETH";
            return "TOKENS FOR EXACT ETH";
        }
        if (operation == 0) return "ADD";
        if (operation == 1) return "ADD ETH";
        if (operation == 2) return "REMOVE";
        return "REMOVE ETH";
    }

    function _onChainFlagCount(PolicyKind kind) internal pure returns (uint8) {
        if (kind == PolicyKind.ERC4626) return 14;
        return 15;
    }

    function _onChainLabel(PolicyKind kind, uint8 operation, uint8 index) internal pure returns (string memory) {
        if (kind == PolicyKind.ERC4626) {
            if (index == 0) return "Vault not whitelisted";
            if (index == 1) return "Vault zero supply";
            if (index == 2) return "Donation attack";
            if (index == 3) return "Share inflation risk";
            if (index == 4) return "Vault balance mismatch";
            if (index == 5) return "Exchange rate anomaly";
            if (index == 6) return "Preview revert";
            if (index == 7) return "Zero shares out";
            if (index == 8) return "Zero assets out";
            if (index == 9) return "Dust shares";
            if (index == 10) return "Dust assets";
            if (index == 11) return "Exceeds max deposit";
            if (index == 12) return "Exceeds max redeem";
            if (index == 13) return "Preview convert mismatch";
            return "";
        }
        if (kind == PolicyKind.SWAP_V2) {
            if (index == 0) return "Router not trusted";
            if (index == 1) return "Factory not trusted";
            if (index == 2) return "Deep multihop";
            if (index == 3) return "Duplicate token in path";
            if (index == 4) return "Pool not exists";
            if (index == 5) return "Factory mismatch";
            if (index == 6) return "Zero liquidity";
            if (index == 7) return "Low liquidity";
            if (index == 8) return "Low LP supply";
            if (index == 9) return "Pool too new";
            if (index == 10) return "Severe imbalance";
            if (index == 11) return "K invariant broken";
            if (index == 12) return "High swap impact";
            if (index == 13) return "Flashloan risk";
            if (index == 14) return "Price manipulated";
            return "";
        }

        if (index == 0) return "Router not trusted";
        if (index == 1) return "Pair not exists";
        if (index == 2) return "Zero liquidity";
        if (index == 3) return "Low liquidity";
        if (index == 4) return "Low LP supply";
        if (index == 5) return "First depositor risk";
        if (index == 6) return "Severe imbalance";
        if (index == 7) return "K invariant broken";
        if (index == 8) return "Pool too new";
        if (index == 9) return "Amount ratio deviation";
        if (index == 10) return "High LP impact";
        if (index == 11) return "Flashloan risk";
        if (index == 12) return "Zero LP out";
        if (index == 13) return "Zero amounts out";
        if (index == 14) return "Dust LP";
        return "";
    }

    function _isOnChainCritical(PolicyKind kind, uint8 operation, uint8 index) internal pure returns (bool) {
        if (kind == PolicyKind.ERC4626) {
            if (index == 2 || index == 4 || index == 6) return true;
            if (index == 7) return operation == 0 || operation == 1;
            if (index == 8) return operation == 2 || operation == 3;
            if (index == 11) return operation == 0 || operation == 1;
            if (index == 12) return operation == 2 || operation == 3;
            return false;
        }
        if (kind == PolicyKind.SWAP_V2) {
            return index == 3 || index == 4 || index == 6 || index == 11 || index == 14;
        }
        return index == 1 || index == 2 || index == 5 || index == 7 || index == 12 || index == 13;
    }

    function _offChainLabel(uint8 index) internal pure returns (string memory) {
        if (index == 1) return "Dangerous delegatecall";
        if (index == 2) return "Selfdestruct path";
        if (index == 3) return "Approval drain";
        if (index == 4) return "Owner sweep";
        if (index == 5) return "Reentrancy behavior";
        if (index == 6) return "Unexpected create";
        if (index == 7) return "Upgrade call";
        if (index == 8) return "Exit frozen";
        if (index == 9) return "Removal frozen";
        if (index == 10) return "First deposit";
        if (index == 11) return "High price impact";
        if (index == 12) return "High output discrepancy";
        if (index == 13) return "High ratio deviation";
        if (index == 14) return "Simulation reverted";
        if (index == 15) return "Fee on transfer";
        if (index == 16) return "Oracle stale";
        if (index == 17) return "Contract unverified";
        if (index == 18) return "Oracle deviation";
        if (index == 19) return "Excess pull";
        if (index == 20) return "Oracle critical";
        if (index == 21) return "Large sweep";
        if (index == 22) return "Zero headroom";
        if (index == 23) return "Simulation hard block";
        if (index == 24) return "Confirmed transfer fee";
        if (index == 25) return "Share price drift high";
        if (index == 26) return "Removal honeypot";
        return "";
    }

    function _isOffChainCritical(uint8 index) internal pure returns (bool) {
        return index == 1 || index == 2 || index == 3 || index == 4 || index == 5 || index == 6 || index == 7
            || index == 8 || index == 9 || index == 14 || index == 20 || index == 21 || index == 23 || index == 26;
    }

    function _tokenLabel(uint8 index) internal pure returns (string memory) {
        if (index == 0) return "Not a contract";
        if (index == 1) return "Empty bytecode";
        if (index == 2) return "Decimals revert";
        if (index == 3) return "Weird decimals";
        if (index == 4) return "High decimals";
        if (index == 5) return "Total supply revert";
        if (index == 6) return "Zero total supply";
        if (index == 7) return "Very low total supply";
        if (index == 8) return "Symbol revert";
        if (index == 9) return "Name revert";
        if (index == 10) return "EIP-1967 proxy";
        if (index == 11) return "EIP-1822 proxy";
        if (index == 12) return "Minimal proxy";
        if (index == 13) return "Has owner";
        if (index == 14) return "Ownership renounced";
        if (index == 15) return "Owner is EOA";
        if (index == 16) return "Is pausable";
        if (index == 17) return "Currently paused";
        if (index == 18) return "Has blacklist";
        if (index == 19) return "Has blocklist";
        if (index == 20) return "Possible fee on transfer";
        if (index == 21) return "Transfer fee getter";
        if (index == 22) return "Tax function";
        if (index == 23) return "Possible rebasing";
        if (index == 24) return "Mint capability";
        if (index == 25) return "Burn capability";
        if (index == 26) return "Has permit";
        if (index == 27) return "Has flash mint";
        return "";
    }

    function _isTokenCritical(uint8 index) internal pure returns (bool) {
        return index == 0 || index == 1 || index == 4 || index == 5 || index == 6 || index == 17;
    }

    function _chipWidth(string memory label) internal pure returns (uint256) {
        return 46 + (bytes(label).length * 7);
    }

    function _shortAddress(address account) internal pure returns (string memory) {
        string memory full = _hexAddress(account);
        bytes memory raw = bytes(full);
        if (raw.length < 12) return full;

        bytes memory out = new bytes(12);
        out[0] = raw[0];
        out[1] = raw[1];
        out[2] = raw[2];
        out[3] = raw[3];
        out[4] = raw[4];
        out[5] = raw[5];
        out[6] = bytes1(".");
        out[7] = bytes1(".");
        out[8] = raw[raw.length - 4];
        out[9] = raw[raw.length - 3];
        out[10] = raw[raw.length - 2];
        out[11] = raw[raw.length - 1];
        return string(out);
    }

    function _hexAddress(address account) internal pure returns (string memory) {
        return Strings.toHexString(uint256(uint160(account)), 20);
    }

    function _toMinimalHex(uint256 value) internal pure returns (string memory) {
        return Strings.toHexString(value);
    }

    function _decode(uint256 packedReport) internal pure returns (DecodedReport memory report) {
        report.kind = PolicyKind(_extract(packedReport, SHIFT_POLICY_KIND, 2));
        report.operation = uint8(_extract(packedReport, SHIFT_OPERATION, 4));
        report.version = uint8(_extract(packedReport, SHIFT_POLICY_VERSION, 8));
        report.finalCategory = PolicyRiskCategory(_extract(packedReport, SHIFT_FINAL_CATEGORY, 2));
        report.offChainCategory = PolicyRiskCategory(_extract(packedReport, SHIFT_OFFCHAIN_CATEGORY, 2));
        report.compositeScore = uint8(_extract(packedReport, SHIFT_COMPOSITE_SCORE, 8));
        report.onChainScore = uint8(_extract(packedReport, SHIFT_ONCHAIN_SCORE, 8));
        report.offChainScore = uint8(_extract(packedReport, SHIFT_OFFCHAIN_SCORE, 8));
        report.onChainCriticalCount = uint8(_extract(packedReport, SHIFT_ONCHAIN_CRITICAL, 6));
        report.onChainWarningCount = uint8(_extract(packedReport, SHIFT_ONCHAIN_WARNING, 6));
        report.offChainFindingCount = uint8(_extract(packedReport, SHIFT_OFFCHAIN_FINDINGS, 6));
        report.anyHardBlock = _extract(packedReport, SHIFT_ANY_HARD_BLOCK, 1) == 1;
        report.offChainValid = _extract(packedReport, SHIFT_OFFCHAIN_VALID, 1) == 1;
        report.onChainFlagsPacked = uint32(_extract(packedReport, SHIFT_ONCHAIN_FLAGS, 32));
        report.offChainFlagsPacked = uint32(_extract(packedReport, SHIFT_OFFCHAIN_FLAGS, 32));
        report.tokenFlagsPacked = uint32(_extract(packedReport, SHIFT_TOKEN_FLAGS, 32));
        report.priceImpactBps = uint16(_extract(packedReport, SHIFT_PRICE_IMPACT, 16));
        report.outputDiscrepancyBps = uint16(_extract(packedReport, SHIFT_OUTPUT_DISCREPANCY, 16));
        report.ratioDeviationBps = uint16(_extract(packedReport, SHIFT_RATIO_DEVIATION, 16));
        report.tokenCriticalCount = uint8(_extract(packedReport, SHIFT_TOKEN_CRITICAL, 6));
        report.tokenWarningCount = uint8(_extract(packedReport, SHIFT_TOKEN_WARNING, 6));
        report.tokenRiskEvaluated = _extract(packedReport, SHIFT_TOKEN_EVALUATED, 1) == 1;
        report.economicSeverityTier = uint8(_extract(packedReport, SHIFT_ECONOMIC_TIER, 3));
        report.oracleAgeTier = uint8(_extract(packedReport, SHIFT_ORACLE_AGE_TIER, 3));
        report.excessPullTier = uint8(_extract(packedReport, SHIFT_EXCESS_PULL_TIER, 3));
        report.sharePriceDriftTier = uint8(_extract(packedReport, SHIFT_SHARE_DRIFT_TIER, 3));
        report.compoundRiskCount = uint8(_extract(packedReport, SHIFT_COMPOUND_COUNT, 3));
        report.simulationRevertBlock = _extract(packedReport, SHIFT_SIM_REVERT_BLOCK, 1) == 1;
        report.sweepSeverityTier = uint8(_extract(packedReport, SHIFT_SWEEP_TIER, 3));
        report.enhancedPresent = _extract(packedReport, SHIFT_ENHANCED_PRESENT, 1) == 1;
    }

    function _extract(uint256 packed, uint8 shift, uint8 width) internal pure returns (uint256) {
        return (packed >> shift) & ((uint256(1) << width) - 1);
    }

    function _isSet(uint32 packed, uint8 bit) internal pure returns (bool) {
        return ((packed >> bit) & 1) == 1;
    }

    function _clearBit(uint32 packed, uint8 bit) internal pure returns (uint32) {
        return packed & ~(uint32(1) << bit);
    }

    function _countSetBits32(uint32 value) internal pure returns (uint8 count) {
        while (value != 0) {
            value &= value - 1;
            unchecked {
                ++count;
            }
        }
    }
}
