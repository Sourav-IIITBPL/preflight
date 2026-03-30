// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {SVGRenderer} from "./SVGRenderer.sol";

/**
 * @title RiskReportNFT
 * @author Sourav-IITBPL
 * @notice Immutable on-chain audit NFT for packed PreFlight policy reports.
 *         The NFT stores the original 256-bit packed risk report and renders a
 *         fully on-chain SVG/JSON metadata payload at `tokenURI`.
 *
 *         Authorized integrations can mint through `mint(uint256,address)`.
 */
contract RiskReportNFT is ERC721, Ownable {
    /// @notice Raised when an address without minting permission attempts to mint.
    error NotAuthorizedMinter();
    /// @notice Raised when a required address argument is the zero address.
    error ZeroAddress();
    /// @notice Raised when metadata is requested for a token that has not been minted.
    error TokenDoesNotExist();

    /// @notice Immutable report data stored for each minted NFT.
    struct StoredRiskReport {
        /// @notice Packed 256-bit report emitted by a policy contract.
        uint256 packedReport;
        /// @notice Contract that minted the report into the NFT collection.
        address sourceMinter;
        /// @notice Timestamp when the report NFT was minted.
        uint64 mintedAt;
        /// @notice Block number when the report NFT was minted.
        uint64 mintedBlock;
    }

    uint256 private _nextTokenId;

    mapping(uint256 => StoredRiskReport) private _storedReports;
    mapping(address => bool) public authorizedMinters;

    /// @notice Emitted when the owner updates minting permission for an address.
    /// @param minter Address whose minting permission changed.
    /// @param authorized Whether the address is now allowed to mint.
    event AuthorizedMinterSet(address indexed minter, bool authorized);
    /// @notice Emitted when a new risk report NFT is minted.
    /// @param tokenId Newly minted token identifier.
    /// @param recipient Address that received the NFT.
    /// @param sourceMinter Authorized contract that initiated the mint.
    /// @param packedReport Packed risk report stored in the NFT.
    event RiskReportMinted(
        uint256 indexed tokenId, address indexed recipient, address indexed sourceMinter, uint256 packedReport
    );

    /// @dev Restricts mint entrypoints to authorized router or integration contracts.
    modifier onlyAuthorizedMinter() {
        if (!authorizedMinters[msg.sender]) revert NotAuthorizedMinter();
        _;
    }

    constructor() ERC721("PreFlight Risk Report", "PFR") {
        _nextTokenId = 1;
    }

    /**
     * @notice Grants or revokes minting permission for an integration contract.
     * @param minter Address to authorize or deauthorize.
     * @param authorized Whether the address should be allowed to mint.
     */
    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        if (minter == address(0)) revert ZeroAddress();
        authorizedMinters[minter] = authorized;
        emit AuthorizedMinterSet(minter, authorized);
    }

    /**
     * @notice Compatibility mint used by the current router interface.
     * @param packedRiskReport Packed 256-bit policy output to store on-chain.
     * @param recipient Address that should receive the minted NFT.
     * @return tokenId Newly minted NFT identifier.
     */
    function mint(uint256 packedRiskReport,address recipient) external onlyAuthorizedMinter returns (uint256 tokenId) {
        if (recipient == address(0)) revert ZeroAddress();
        tokenId = _mintReport(recipient, packedRiskReport);
    }

    /**
     * @notice Returns the number of report NFTs minted so far.
     * @return Number of minted report NFTs.
     */
    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /**
     * @notice Returns the packed report stored for a token.
     * @param tokenId Token identifier to inspect.
     * @return packedReport Packed risk report associated with the token.
     */
    function packedReportOf(uint256 tokenId) external view returns (uint256 packedReport) {
        _requireExisting(tokenId);
        return _storedReports[tokenId].packedReport;
    }

    /**
     * @notice Returns the full stored report metadata for a token.
     * @param tokenId Token identifier to inspect.
     * @return report Stored report record for the token.
     */
    function reportOf(uint256 tokenId) external view returns (StoredRiskReport memory report) {
        _requireExisting(tokenId);
        return _storedReports[tokenId];
    }

    /**
     * @notice Returns the fully on-chain metadata payload for a report NFT.
     * @param tokenId Token identifier to render.
     * @return Base64-encoded JSON metadata URI containing the SVG image.
     */
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

    /**
     * @dev Mints the ERC-721 token and stores the immutable report payload.
     * @param recipient Address that should receive the newly minted token.
     * @param packedRiskReport Packed risk report to store.
     * @return tokenId Newly minted token identifier.
     */
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

    /**
     * @dev Reverts when the queried token has not been minted yet.
     * @param tokenId Token identifier to validate.
     */
    function _requireExisting(uint256 tokenId) internal view {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
    }
}
