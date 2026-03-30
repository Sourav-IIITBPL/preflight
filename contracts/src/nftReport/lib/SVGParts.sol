// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "./SVGLib.sol";

/**
 * @title SVGParts
 * @author PreFlight Team
 * @notice Reusable UI components and primitives for the PreFlight Risk Report SVG.
 * @dev These components use glassmorphism effects (transparency + blur) and standard
 *      CSS-like primitives to build a modern, interactive-feeling report on-chain.
 */
library SVGParts {
    using Strings for uint256;

    /**
     * @notice Returns the shared <defs> section for the SVG, including gradients and filters.
     * @return defs The SVG definitions string.
     */
    function getDefs() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<defs>",
                // Main background gradient (deep space/dark mode)
                '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">',
                '<stop offset="0%" stop-color="#0d1117"/>',
                '<stop offset="100%" stop-color="#010409"/>',
                "</linearGradient>",
                // Glassmorphism overlay gradient
                '<linearGradient id="glass" x1="0" y1="0" x2="1" y2="1">',
                '<stop offset="0%" stop-color="#ffffff" stop-opacity="0.08"/>',
                '<stop offset="100%" stop-color="#ffffff" stop-opacity="0.02"/>',
                "</linearGradient>",
                // Color-ramped score meter gradient
                '<linearGradient id="scoreGrad" x1="0" y1="0" x2="1" y2="0">',
                '<stop offset="0%" stop-color="#3fb950"/>', // Safe (Green)
                '<stop offset="40%" stop-color="#d29922"/>', // Warning (Yellow/Gold)
                '<stop offset="70%" stop-color="#f85149"/>', // Critical (Red)
                '<stop offset="100%" stop-color="#8e1519"/>', // Extreme (Dark Red)
                "</linearGradient>",
                // Glow effect for markers and critical chips
                '<filter id="glow"><feGaussianBlur stdDeviation="4" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
                "</defs>"
            )
        );
    }

    /**
     * @notice Renders the top header section with the report title, policy kind, and final category badge.
     * @param tokenId The NFT identifier.
     * @param kind Label for the policy kind (e.g., "ERC4626").
     * @param op Label for the operation (e.g., "DEPOSIT").
     * @param color Primary accent color based on risk level.
     * @param label Human-readable risk level (e.g., "CRITICAL").
     * @return header The SVG header group.
     */
    function getHeader(uint256 tokenId, string memory kind, string memory op, string memory color, string memory label)
        external
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<rect x="30" y="30" width="940" height="130" rx="24" fill="url(#glass)" stroke="',
                color,
                '" stroke-opacity="0.3"/>',
                '<text x="60" y="85" font-family="Arial, sans-serif" font-size="36" font-weight="bold" fill="#f0f6fc">PreFlight Report</text>',
                '<text x="60" y="125" font-family="Arial, sans-serif" font-size="18" fill="#8b949e">',
                kind,
                " | ",
                op,
                " | #",
                tokenId.toString(),
                "</text>",
                // Final Category Badge
                '<rect x="740" y="65" width="200" height="60" rx="15" fill="',
                color,
                '" fill-opacity="0.15" stroke="',
                color,
                '" stroke-opacity="0.6"/>',
                '<text x="840" y="103" font-family="Arial, sans-serif" font-size="22" font-weight="bold" fill="',
                color,
                '" text-anchor="middle">',
                label,
                "</text>"
            )
        );
    }

    /**
     * @notice Renders the horizontal risk score meter with a position marker.
     * @param score The 0-100 composite risk score.
     * @param color The accent color for the marker.
     * @return meter The SVG meter component.
     */
    function getScoreMeter(uint8 score, string memory color) external pure returns (string memory) {
        uint256 markerX = 60 + (uint256(score) * 880) / 100;
        return string(
            abi.encodePacked(
                '<text x="60" y="200" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="#8b949e">COMPOSITE RISK SCORE</text>',
                '<rect x="60" y="220" width="880" height="14" rx="7" fill="#21262d"/>',
                '<rect x="60" y="220" width="880" height="14" rx="7" fill="url(#scoreGrad)"/>',
                // Interactive-style marker
                '<circle cx="',
                markerX.toString(),
                '" cy="227" r="12" fill="#0d1117" stroke="',
                color,
                '" stroke-width="3" filter="url(#glow)"/>',
                '<text x="',
                markerX.toString(),
                '" y="265" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="',
                color,
                '" text-anchor="middle">',
                uint256(score).toString(),
                "</text>"
            )
        );
    }

    /**
     * @notice Renders a row of three sub-metric cards (On-Chain, Off-Chain, Token).
     * @param onScore Sub-score for on-chain findings.
     * @param offScore Sub-score for off-chain simulation.
     * @param tScore Sub-score for token-level risks.
     * @return cards The SVG group of metric cards.
     */
    function getMetricCards(uint8 onScore, uint8 offScore, uint8 tScore) external pure returns (string memory) {
        return string(
            abi.encodePacked(
                getMetricCard(60, 290, 273, "ON-CHAIN", onScore, SVGLib.C_ACCENT),
                getMetricCard(363, 290, 273, "OFF-CHAIN", offScore, SVGLib.C_MED),
                getMetricCard(666, 290, 273, "TOKEN", tScore, SVGLib.C_TOKEN)
            )
        );
    }

    /**
     * @notice Primitive for a single metric card.
     * @param x X coordinate.
     * @param y Y coordinate.
     * @param w Width of the card.
     * @param label Trait label (e.g., "ON-CHAIN").
     * @param score Score value (0-100).
     * @param color Accent color for the score text.
     * @return card The SVG card primitive.
     */
    function getMetricCard(uint256 x, uint256 y, uint256 w, string memory label, uint8 score, string memory color)
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
                '" height="80" rx="16" fill="url(#glass)" stroke="#30363d"/>',
                '<text x="',
                (x + 20).toString(),
                '" y="',
                (y + 30).toString(),
                '" font-family="Arial, sans-serif" font-size="14" font-weight="bold" fill="#8b949e">',
                label,
                "</text>",
                '<text x="',
                (x + 20).toString(),
                '" y="',
                (y + 65).toString(),
                '" font-family="Arial, sans-serif" font-size="28" font-weight="bold" fill="',
                color,
                '">',
                uint256(score).toString(),
                '<tspan font-size="14" fill="#8b949e" dx="5">/100</tspan></text>'
            )
        );
    }

    /**
     * @notice Primitive for a section frame with a titled header bar.
     * @param x X coordinate.
     * @param y Y coordinate.
     * @param w Width.
     * @param h Height.
     * @param title Section title (e.g., "ON-CHAIN FINDINGS").
     * @param color Section accent color.
     * @return frame The SVG section frame group.
     */
    function getSectionFrame(uint256 x, uint256 y, uint256 w, uint256 h, string memory title, string memory color)
        external
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
                '" rx="20" fill="url(#glass)" stroke="#30363d"/>',
                '<rect x="',
                x.toString(),
                '" y="',
                y.toString(),
                '" width="',
                w.toString(),
                '" height="45" rx="20" fill="',
                color,
                '" fill-opacity="0.1"/>',
                '<text x="',
                (x + 25).toString(),
                '" y="',
                (y + 32).toString(),
                '" font-family="Arial, sans-serif" font-size="18" font-weight="bold" fill="',
                color,
                '">',
                title,
                "</text>"
            )
        );
    }

    /**
     * @notice Renders an interactive-style "chip" for a single risk finding.
     * @param x X coordinate.
     * @param y Y coordinate.
     * @param label The finding label (e.g., "Reentrancy").
     * @param color Chip accent color.
     * @param critical True if the chip should have a "glowing" indicator.
     * @return chip The SVG chip component.
     */
    function getChip(uint256 x, uint256 y, string memory label, string memory color, bool critical)
        external
        pure
        returns (string memory)
    {
        uint256 w = 35 + (bytes(label).length * 8);
        return string(
            abi.encodePacked(
                '<rect x="',
                x.toString(),
                '" y="',
                y.toString(),
                '" width="',
                w.toString(),
                '" height="28" rx="14" fill="',
                color,
                '" fill-opacity="0.12" stroke="',
                color,
                '" stroke-opacity="0.5"/>',
                critical ? '<circle cx="' : "",
                critical ? (x + 14).toString() : "",
                critical ? '" cy="' : "",
                critical ? (y + 14).toString() : "",
                critical ? '" r="4" fill="' : "",
                critical ? color : "",
                critical ? '" filter="url(#glow)"/>' : "",
                '<text x="',
                (x + (critical ? 26 : 14)).toString(),
                '" y="',
                (y + 19).toString(),
                '" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#f0f6fc">',
                label,
                "</text>"
            )
        );
    }

    /**
     * @notice Renders the footer section with ownership and block metadata.
     * @param owner Formatted owner address string.
     * @param minter Formatted source minter address string.
     * @param blockNum Minting block number.
     * @param ts Minting timestamp.
     * @return footer The SVG footer group.
     */
    function getFooter(string memory owner, string memory minter, uint256 blockNum, uint256 ts)
        external
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                '<rect x="30" y="1150" width="940" height="100" rx="20" fill="url(#glass)" stroke="#30363d"/>',
                '<text x="60" y="1185" font-family="Arial, sans-serif" font-size="14" fill="#8b949e">OWNER: <tspan fill="#f0f6fc">',
                owner,
                "</tspan></text>",
                '<text x="60" y="1215" font-family="Arial, sans-serif" font-size="14" fill="#8b949e">MINTER: <tspan fill="#f0f6fc">',
                minter,
                "</tspan></text>",
                '<text x="910" y="1185" font-family="Arial, sans-serif" font-size="14" fill="#8b949e" text-anchor="end">BLOCK: <tspan fill="#f0f6fc">',
                blockNum.toString(),
                "</tspan></text>",
                '<text x="910" y="1215" font-family="Arial, sans-serif" font-size="14" fill="#8b949e" text-anchor="end">TIME: <tspan fill="#f0f6fc">',
                ts.toString(),
                "</tspan></text>"
            )
        );
    }
}
