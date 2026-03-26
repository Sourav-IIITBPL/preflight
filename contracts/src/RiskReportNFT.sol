// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {SVGRenderer} from "./SVGRenderer.sol";

/**
 * @title RiskReportNFT
 * @notice Immutable on-chain audit NFT for packed PreFlight policy reports.
 *         The NFT stores the original 256-bit packed risk report and renders a
 *         fully on-chain SVG/JSON metadata payload at `tokenURI`.
 *
 *         Routers currently mint through `mint(uint256 packedRiskReport)`.
 *         For future integrations that know the end-recipient explicitly,
 *         `mintFor(address,uint256)` is also exposed.
 */
contract RiskReportNFT is ERC721, Ownable {
    error NotAuthorizedMinter();
    error ZeroAddress();
    error TokenDoesNotExist();

    struct StoredRiskReport {
        uint256 packedReport;
        address sourceMinter;
        uint64 mintedAt;
        uint64 mintedBlock;
    }

    uint256 private _nextTokenId;

    mapping(uint256 => StoredRiskReport) private _storedReports;
    mapping(address => bool) public authorizedMinters;

    event AuthorizedMinterSet(address indexed minter, bool authorized);
    event RiskReportMinted(
        uint256 indexed tokenId, address indexed recipient, address indexed sourceMinter, uint256 packedReport
    );

    modifier onlyAuthorizedMinter() {
        if (!authorizedMinters[msg.sender]) revert NotAuthorizedMinter();
        _;
    }

    constructor() ERC721("PreFlight Risk Report", "PFR") {
        _nextTokenId = 1;
    }

    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        if (minter == address(0)) revert ZeroAddress();
        authorizedMinters[minter] = authorized;
        emit AuthorizedMinterSet(minter, authorized);
    }

    /**
     * @notice Compatibility mint used by the current router interface.
     * @dev If a router/contract calls this, the NFT is assigned to `tx.origin`
     *      so the report follows the initiating user instead of the router.
     *      Smart-wallet integrations should migrate to `mintFor`.
     */
    function mint(uint256 packedRiskReport) external onlyAuthorizedMinter returns (uint256 tokenId) {
        address recipient = msg.sender == tx.origin ? msg.sender : tx.origin;
        tokenId = _mintReport(recipient, packedRiskReport);
    }

    function mintFor(address recipient, uint256 packedRiskReport)
        external
        onlyAuthorizedMinter
        returns (uint256 tokenId)
    {
        if (recipient == address(0)) revert ZeroAddress();
        tokenId = _mintReport(recipient, packedRiskReport);
    }

    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function packedReportOf(uint256 tokenId) external view returns (uint256 packedReport) {
        _requireExisting(tokenId);
        return _storedReports[tokenId].packedReport;
    }

    function reportOf(uint256 tokenId) external view returns (StoredRiskReport memory report) {
        _requireExisting(tokenId);
        return _storedReports[tokenId];
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireExisting(tokenId);

        StoredRiskReport memory report = _storedReports[tokenId];
        SVGRenderer.RenderContext memory context = SVGRenderer.RenderContext({
            packedReport: report.packedReport,
            owner: ownerOf(tokenId),
            sourceMinter: report.sourceMinter,
            mintedAt: report.mintedAt,
            mintedBlock: report.mintedBlock
        });

        return SVGRenderer.buildTokenURI(tokenId, context);
    }

    function _mintReport(address recipient, uint256 packedRiskReport) internal returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(recipient, tokenId);

        _storedReports[tokenId] = StoredRiskReport({
            packedReport: packedRiskReport,
            sourceMinter: msg.sender,
            mintedAt: uint64(block.timestamp),
            mintedBlock: uint64(block.number)
        });

        emit RiskReportMinted(tokenId, recipient, msg.sender, packedRiskReport);
    }

    function _requireExisting(uint256 tokenId) internal view {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
    }
}
