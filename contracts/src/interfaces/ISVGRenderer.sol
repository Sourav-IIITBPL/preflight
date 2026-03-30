// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Runtime metadata used when rendering a report NFT.
    struct RenderContext {
        /// @notice Packed risk report being rendered.
        uint256 packedReport;
        /// @notice Current NFT owner.
        address owner;
        /// @notice Contract that originally minted the NFT.
        address sourceMinter;
        /// @notice Mint timestamp for the NFT.
        uint64 mintedAt;
        /// @notice Mint block number for the NFT.
        uint64 mintedBlock;
    }
interface ISVGRenderer {
    
    /**
     * @notice Builds the complete token metadata URI for a risk report NFT.
     * @param tokenId NFT identifier being rendered.
     * @param context Rendering context containing the packed report and mint metadata.
     * @return Base64-encoded JSON metadata URI.
     */
    function buildTokenURI(uint256 tokenId, RenderContext memory context) external pure returns (string memory);

}