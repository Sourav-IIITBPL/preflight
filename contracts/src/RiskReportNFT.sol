// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title  RiskReportNFT
 * @notice Each token represents a stored pre-flight check for a vault deposit/redeem
 *         or a V2 swap. Minted when the user calls storeCheck (via PreFlightRouter).
 *         Marked CONSUMED when the associated guarded execution succeeds.
 *         Marked EXPIRED if a newer check for the same user+target is stored.
 *
 * Token metadata is fully on-chain: tokenURI returns a base64-encoded JSON blob
 * with an inline SVG image and a full attribute list of all flag states.
 *
 * Only authorised minters (PreFlightRouter) may mint or consume tokens.
 */
contract RiskReportNFT is ERC721, ERC721Enumerable, ERC721Burnable, Ownable {
    using Strings for uint256;
    using Strings for address;

    enum ReportType {
        VAULT_DEPOSIT,
        VAULT_REDEEM,
        SWAPV2,
        SWAPV3,
        SWAPV4
    }
    enum RiskLevel {
        SAFE,
        WARNING,
        CRITICAL
    }
    enum Status {
        PENDING,
        CONSUMED,
        EXPIRED
    }

    /**
     * @dev Core data stored per token.
     *      flagsPacked is a uint32 bitmask; bit indices match the flag field ordering
     *      in VaultGuardResult (bits 0-13) or SwapGuardResult (bits 0-12).
     *      criticalFlagCount  — number of absolute-hard-block flags that fired.
     *      softFlagCount      — number of soft-warn flags that fired.
     */
    struct RiskReport {
        ReportType reportType;
        RiskLevel riskLevel;
        Status status;
        address user;
        address target; // vault address or first token in swap path
        address router; // zero for vault ops
        uint256 amount;
        uint256 previewValue; // previewShares (deposit) | previewAssets (redeem) | 0 (swap)
        uint256 blockNumber;
        uint256 timestamp;
        bytes32 checkHash; // keccak256 of the full encoded check stored in the guard
        uint32 flagsPacked; // bitmask of all triggered flags
        uint8 totalFlags; // count of fields in result struct
        uint8 criticalCount; // critical flags set
        uint8 softCount; // soft / warning flags set
    }

    uint256 private _nextTokenId;

    mapping(uint256 => RiskReport) public reports;

    /// Authorised minters (PreFlightRouter address).
    mapping(address => bool) public authorizedMinters;

    /// Latest token per user+target (vault) or user+router (swap) for UX lookup.
    mapping(bytes32 => uint256) public latestTokenFor;

    event ReportMinted(uint256 indexed tokenId, address indexed user, ReportType reportType, RiskLevel riskLevel);

    event ReportConsumed(uint256 indexed tokenId, address indexed user);
    event ReportExpired(uint256 indexed tokenId, address indexed user);
    event MinterSet(address indexed minter, bool authorized);

    constructor() ERC721("PreFlight Risk", "PFR") Ownable(msg.sender) {}

    /**
     * @notice Mint a new risk report NFT.
     * @param to          Recipient (the user who ran the check).
     * @param report      Pre-populated RiskReport struct. status must be PENDING.
     * @return tokenId    Newly minted token ID.
     */
    function mint(address to, RiskReport calldata report) external onlyAuthorized returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        reports[tokenId] = report;

        // Mark any previous PENDING token for the same user+target as EXPIRED.
        bytes32 key = _key(report.user, report.target);
        uint256 prev = latestTokenFor[key];
        if (prev != 0 && reports[prev].status == Status.PENDING) {
            reports[prev].status = Status.EXPIRED;
            emit ReportExpired(prev, report.user);
        }
        latestTokenFor[key] = tokenId;

        emit ReportMinted(tokenId, to, report.reportType, report.riskLevel);
    }

    /**
     * @notice Mark a report as CONSUMED (execution succeeded).
     * @param tokenId The token to consume.
     */
    function consume(uint256 tokenId) external onlyAuthorized {
        require(_ownerOf(tokenId) != address(0), "TOKEN_NOT_EXISTS");
        require(reports[tokenId].status == Status.PENDING, "NOT_PENDING");
        reports[tokenId].status = Status.CONSUMED;
        emit ReportConsumed(tokenId, reports[tokenId].user);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "TOKEN_NOT_EXISTS");
        RiskReport memory r = reports[tokenId];

        string memory image = _buildSVG(r);
        string memory attrs = _buildAttributes(r);
        string memory name = string.concat("PreFlight #", tokenId.toString());
        string memory desc = _buildDescription(r);

        string memory json = Base64.encode(
            bytes(
                string.concat(
                    '{"name":"',
                    name,
                    '",' '"description":"',
                    desc,
                    '",' '"image":"data:image/svg+xml;base64,',
                    Base64.encode(bytes(image)),
                    '",' '"attributes":[',
                    attrs,
                    "]}"
                )
            )
        );

        return string.concat("data:application/json;base64,", json);
    }

    function _buildSVG(RiskReport memory r) internal pure returns (string memory) {
        (string memory riskColor, string memory riskLabel) = _riskStyle(r.riskLevel);
        (string memory statusColor, string memory statusLabel) = _statusStyle(r.status);
        string memory typeLabel = _typeLabel(r.reportType);

        string memory flagBar = _buildFlagBar(r.criticalCount, r.softCount, r.totalFlags);
        string memory preview =
            r.previewValue > 0 ? string.concat("Preview: ", _shortNum(r.previewValue)) : "Preview: N/A";

        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 220" width="360" height="220">',
            "<defs>",
            '<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">',
            '<stop offset="0%" stop-color="#0d1117"/>',
            '<stop offset="100%" stop-color="#161b22"/>',
            "</linearGradient>",
            '<linearGradient id="risk" x1="0" y1="0" x2="1" y2="0">',
            '<stop offset="0%" stop-color="',
            riskColor,
            '" stop-opacity="0.9"/>',
            '<stop offset="100%" stop-color="',
            riskColor,
            '" stop-opacity="0.3"/>',
            "</linearGradient>",
            "</defs>",
            // Background
            '<rect width="360" height="220" rx="16" fill="url(#bg)"/>',
            '<rect width="360" height="220" rx="16" fill="none" stroke="',
            riskColor,
            '" stroke-width="1.5" stroke-opacity="0.4"/>',
            // Risk accent bar at top
            '<rect x="0" y="0" width="360" height="4" rx="2" fill="url(#risk)"/>',
            // Header
            _svgShield(riskColor),
            '<text x="40" y="30" font-family="monospace" font-size="13" font-weight="bold" fill="#e6edf3">PREFLIGHT</text>',
            '<text x="40" y="44" font-family="monospace" font-size="9" fill="#8b949e">Risk Report NFT</text>',
            // Type badge
            '<rect x="250" y="14" width="95" height="22" rx="11" fill="',
            riskColor,
            '" fill-opacity="0.15" stroke="',
            riskColor,
            '" stroke-width="1"/>',
            '<text x="297" y="29" font-family="monospace" font-size="9" fill="',
            riskColor,
            '" text-anchor="middle">',
            typeLabel,
            "</text>",
            // Divider
            '<line x1="16" y1="58" x2="344" y2="58" stroke="#30363d" stroke-width="1"/>',
            // Risk level
            '<text x="16" y="80" font-family="monospace" font-size="11" fill="#8b949e">RISK LEVEL</text>',
            '<text x="16" y="98" font-family="monospace" font-size="22" font-weight="bold" fill="',
            riskColor,
            '">',
            riskLabel,
            "</text>",
            // Flag bar
            flagBar,
            // Target address
            '<text x="16" y="140" font-family="monospace" font-size="9" fill="#8b949e">TARGET</text>',
            '<text x="16" y="153" font-family="monospace" font-size="10" fill="#c9d1d9">',
            _shortAddr(r.target),
            "</text>",
            // Preview + block
            '<text x="200" y="140" font-family="monospace" font-size="9" fill="#8b949e">BLOCK</text>',
            '<text x="200" y="153" font-family="monospace" font-size="10" fill="#c9d1d9">',
            r.blockNumber.toString(),
            "</text>",
            // Divider
            '<line x1="16" y1="165" x2="344" y2="165" stroke="#30363d" stroke-width="1"/>',
            // Preview value
            '<text x="16" y="182" font-family="monospace" font-size="9" fill="#8b949e">',
            preview,
            "</text>",
            // Status badge
            '<rect x="250" y="170" width="94" height="22" rx="11" fill="',
            statusColor,
            '" fill-opacity="0.15" stroke="',
            statusColor,
            '" stroke-width="1"/>',
            '<circle cx="265" cy="181" r="4" fill="',
            statusColor,
            '"/>',
            '<text x="296" y="185" font-family="monospace" font-size="9" fill="',
            statusColor,
            '" text-anchor="middle">',
            statusLabel,
            "</text>",
            // Amount
            '<text x="16" y="210" font-family="monospace" font-size="9" fill="#484f58">Amount: ',
            _shortNum(r.amount),
            " | ",
            _shortAddr(r.user),
            "</text>",
            "</svg>"
        );
    }

    function _svgShield(string memory color) internal pure returns (string memory) {
        return string.concat(
            '<path d="M16 14 L24 11 L32 14 L32 22 C32 27 24 31 24 31 C24 31 16 27 16 22 Z" fill="',
            color,
            '" fill-opacity="0.2" stroke="',
            color,
            '" stroke-width="1.2"/>'
        );
    }

    function _buildFlagBar(uint8 crit, uint8 soft, uint8 total) internal pure returns (string memory) {
        // Visual flag count bar: [critical blocks] [soft warns] [clean]
        uint8 clean = total > crit + soft ? total - crit - soft : 0;
        uint256 barWidth = 328;
        uint256 critW = total > 0 ? (uint256(crit) * barWidth) / total : 0;
        uint256 softW = total > 0 ? (uint256(soft) * barWidth) / total : 0;
        uint256 cleanW = barWidth - critW - softW;

        string memory label = string.concat(
            uint256(crit).toString(),
            " critical  ",
            uint256(soft).toString(),
            " warnings  ",
            uint256(clean).toString(),
            " clean"
        );

        return string.concat(
            '<rect x="16" y="108" width="',
            barWidth.toString(),
            '" height="6" rx="3" fill="#21262d"/>',
            critW > 0
                ? string.concat(
                    '<rect x="16" y="108" width="', critW.toString(), '" height="6" rx="3" fill="#f85149"/>'
                )
                : "",
            softW > 0
                ? string.concat(
                    '<rect x="',
                    (16 + critW).toString(),
                    '" y="108" width="',
                    softW.toString(),
                    '" height="6" fill="#d29922"/>'
                )
                : "",
            cleanW > 0
                ? string.concat(
                    '<rect x="',
                    (16 + critW + softW).toString(),
                    '" y="108" width="',
                    cleanW.toString(),
                    '" height="6" rx="3" fill="#3fb950"/>'
                )
                : "",
            '<text x="16" y="126" font-family="monospace" font-size="8" fill="#8b949e">',
            label,
            "</text>"
        );
    }

    function _buildAttributes(RiskReport memory r) internal pure returns (string memory) {
        string memory base = string.concat(
            _attr("Report Type", _typeLabel(r.reportType), true),
            ",",
            _attr("Risk Level", _riskLabel(r.riskLevel), true),
            ",",
            _attr("Status", _statusLabel(r.status), true),
            ",",
            _attr("Target", r.target.toHexString(), true),
            ",",
            _attr("Block", r.blockNumber.toString(), false),
            ",",
            _attr("Critical Flags", uint256(r.criticalCount).toString(), false),
            ",",
            _attr("Soft Flags", uint256(r.softCount).toString(), false),
            ",",
            _attr("Total Flags", uint256(r.totalFlags).toString(), false),
            ",",
            _attr("Amount", r.amount.toString(), false),
            ",",
            _attr("Preview Value", r.previewValue.toString(), false)
        );

        // Unpack flagsPacked bits into individual attributes.
        string memory flagAttrs = _unpackFlags(r.flagsPacked, r.reportType);

        return string.concat(base, flagAttrs.length > 0 ? string.concat(",", flagAttrs) : "");
    }

    function _unpackFlags(uint32 packed, ReportType rt) internal pure returns (string memory out) {
        string[14] memory vaultNames = [
            "VAULT_NOT_WHITELISTED",
            "VAULT_ZERO_SUPPLY",
            "DONATION_ATTACK",
            "SHARE_INFLATION_RISK",
            "VAULT_BALANCE_MISMATCH",
            "EXCHANGE_RATE_ANOMALY",
            "PREVIEW_REVERT",
            "ZERO_SHARES_OUT",
            "ZERO_ASSETS_OUT",
            "DUST_SHARES",
            "DUST_ASSETS",
            "EXCEEDS_MAX_DEPOSIT",
            "EXCEEDS_MAX_REDEEM",
            "PREVIEW_CONVERT_MISMATCH"
        ];

        string[13] memory swapNames = [
            "DEEP_MULTIHOP",
            "DUPLICATE_TOKEN_IN_PATH",
            "POOL_NOT_EXISTS",
            "FACTORY_MISMATCH",
            "ZERO_LIQUIDITY",
            "LOW_LIQUIDITY",
            "LOW_LP_SUPPLY",
            "POOL_TOO_NEW",
            "SEVERE_IMBALANCE",
            "K_INVARIANT_BROKEN",
            "HIGH_SWAP_IMPACT",
            "FLASHLOAN_RISK",
            "PRICE_MANIPULATED"
        ];

        bool isSwap = (rt == ReportType.SWAP);
        uint8 count = isSwap ? 13 : 14;

        for (uint8 i = 0; i < count;) {
            bool flagSet = (packed >> i) & 1 == 1;
            string memory name = isSwap ? swapNames[i] : vaultNames[i];
            string memory entry =
                string.concat('{"trait_type":"', name, '","value":"', flagSet ? "true" : "false", '"}');
            out = i == 0 ? entry : string.concat(out, ",", entry);
            unchecked {
                ++i;
            }
        }
    }

    function _attr(string memory key, string memory val, bool isString) internal pure returns (string memory) {
        if (isString) {
            return string.concat('{"trait_type":"', key, '","value":"', val, '"}');
        }
        return string.concat('{"trait_type":"', key, '","value":', val, "}");
    }

    function _buildDescription(RiskReport memory r) internal pure returns (string memory) {
        return string.concat(
            "PreFlight risk report for ",
            _typeLabel(r.reportType),
            " on ",
            _shortAddr(r.target),
            ". Risk: ",
            _riskLabel(r.riskLevel),
            ". Status: ",
            _statusLabel(r.status),
            ". Block: ",
            r.blockNumber.toString()
        );
    }

    function _riskStyle(RiskLevel level) internal pure returns (string memory color, string memory label) {
        if (level == RiskLevel.SAFE) return ("#3fb950", "SAFE");
        if (level == RiskLevel.WARNING) return ("#d29922", "WARNING");
        return ("#f85149", "CRITICAL");
    }

    function _riskLabel(RiskLevel level) internal pure returns (string memory) {
        if (level == RiskLevel.SAFE) return "SAFE";
        if (level == RiskLevel.WARNING) return "WARNING";
        return "CRITICAL";
    }

    function _statusStyle(Status s) internal pure returns (string memory color, string memory label) {
        if (s == Status.PENDING) return ("#58a6ff", "PENDING");
        if (s == Status.CONSUMED) return ("#3fb950", "CONSUMED");
        return ("#6e7681", "EXPIRED");
    }

    function _statusLabel(Status s) internal pure returns (string memory) {
        if (s == Status.PENDING) return "PENDING";
        if (s == Status.CONSUMED) return "CONSUMED";
        return "EXPIRED";
    }

    function _typeLabel(ReportType rt) internal pure returns (string memory) {
        if (rt == ReportType.VAULT_DEPOSIT) return "VAULT DEPOSIT";
        if (rt == ReportType.VAULT_REDEEM) return "VAULT REDEEM";
        if (rt == ReportType.SWAPV2) return "SWAP V2";
        if (rt == ReportType.SWAPV3) return "SWAP V3";
        return "SWAP V4";
    }

    /// @dev Returns a shortened address like "0x1234...5678"
    function _shortAddr(address addr) internal pure returns (string memory) {
        string memory full = addr.toHexString();
        bytes memory b = bytes(full);
        // full is 42 chars: "0x" + 40 hex chars
        // take first 8 chars (0x + 6) and last 4
        bytes memory out = new bytes(13); // "0x1234...5678"
        for (uint256 i = 0; i < 8; i++) {
            out[i] = b[i];
        }
        out[8] = ".";
        out[9] = ".";
        out[10] = ".";
        out[11] = b[38];
        out[12] = b[39];
        // add last 2 as well - actually let's do 0x + 4 + ... + 4 = 12 chars
        return string(out);
    }

    /// @dev Returns a shortened number like "1.23M" or "45.6K"
    function _shortNum(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        if (n >= 1e18) return string.concat((n / 1e15).toString(), "e15");
        if (n >= 1e9) return string.concat((n / 1e6).toString(), "e6");
        if (n >= 1e6) return string.concat((n / 1e3).toString(), "e3");
        return n.toString();
    }

    function _key(address user, address target) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, target));
    }

    /// @notice Returns the latest tokenId stored for a user+target pair.
    function latestToken(address user, address target) external view returns (uint256 tokenId, bool exists) {
        bytes32 k = _key(user, target);
        tokenId = latestTokenFor[k];
        exists = tokenId != 0 || _ownerOf(tokenId) != address(0);
    }

    function getReport(uint256 tokenId) external view returns (RiskReport memory) {
        require(_ownerOf(tokenId) != address(0), "TOKEN_NOT_EXISTS");
        return reports[tokenId];
    }

    function isPending(uint256 tokenId) external view returns (bool) {
        return reports[tokenId].status == Status.PENDING;
    }

    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        require(minter != address(0), "ZERO_ADDRESS");
        authorizedMinters[minter] = authorized;
        emit MinterSet(minter, authorized);
    }

    modifier onlyAuthorized() {
        require(authorizedMinters[msg.sender], "NOT_AUTHORIZED_MINTER");
        _;
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
