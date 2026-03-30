// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {RiskReportNFT} from "../../src/RiskReportNFT.sol";

contract RiskReportNFTTest is Test {
    RiskReportNFT internal nft;

    address internal minter = address(0xA11CE);
    address internal recipient = address(0xB0B);

    function setUp() public {
        nft = new RiskReportNFT();
    }

    function test_setAuthorizedMinterRevertsForZeroAddress() public {
        vm.expectRevert(RiskReportNFT.ZeroAddress.selector);
        nft.setAuthorizedMinter(address(0), true);
    }

    function test_onlyOwnerCanSetAuthorizedMinter() public {
        address nonOwner = address(0xBAD);
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        nft.setAuthorizedMinter(minter, true);
    }

    function test_ownerCanAuthorizeMinter() public {
        vm.expectEmit(true, false, false, true);
        emit RiskReportNFT.AuthorizedMinterSet(minter, true);
        nft.setAuthorizedMinter(minter, true);
        assertTrue(nft.authorizedMinters(minter));
    }

    function test_deauthorizeMinter() public {
        nft.setAuthorizedMinter(minter, true);
        assertTrue(nft.authorizedMinters(minter));

        nft.setAuthorizedMinter(minter, false);
        assertFalse(nft.authorizedMinters(minter));
    }

    function test_unauthorizedMintReverts() public {
        vm.prank(minter);
        vm.expectRevert(RiskReportNFT.NotAuthorizedMinter.selector);
        nft.mint(123, recipient);
    }

    function test_mintRevertsForZeroAddressRecipient() public {
        nft.setAuthorizedMinter(minter, true);
        vm.prank(minter);
        vm.expectRevert(RiskReportNFT.ZeroAddress.selector);
        nft.mint(123, address(0));
    }

    function test_authorizedMintStoresReportAndBuildsTokenUri() public {
        nft.setAuthorizedMinter(minter, true);

        vm.expectEmit(true, true, true, true);
        emit RiskReportNFT.RiskReportMinted(1, recipient, minter, 456);
        vm.prank(minter);
        uint256 tokenId = nft.mint(456, recipient);

        assertEq(tokenId, 1);
        assertEq(nft.totalMinted(), 1);
        assertEq(nft.ownerOf(tokenId), recipient);
        assertEq(nft.packedReportOf(tokenId), 456);

        RiskReportNFT.StoredRiskReport memory report = nft.reportOf(tokenId);
        assertEq(report.packedReport, 456);
        assertEq(report.sourceMinter, minter);
        assertEq(report.mintedBlock, uint64(block.number));
        assertEq(report.mintedAt, uint64(block.timestamp));

        string memory uri = nft.tokenURI(tokenId);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }

    function test_multipleMintsIncrementTokenId() public {
        nft.setAuthorizedMinter(minter, true);

        vm.startPrank(minter);
        uint256 id1 = nft.mint(111, recipient);
        uint256 id2 = nft.mint(222, recipient);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(nft.totalMinted(), 2);
    }

    function test_nonexistentTokenReadsRevert() public {
        vm.expectRevert(RiskReportNFT.TokenDoesNotExist.selector);
        nft.packedReportOf(999);

        vm.expectRevert(RiskReportNFT.TokenDoesNotExist.selector);
        nft.reportOf(999);

        vm.expectRevert(RiskReportNFT.TokenDoesNotExist.selector);
        nft.tokenURI(999);
    }

    function _startsWith(string memory text, string memory prefix) internal pure returns (bool) {
        bytes memory textBytes = bytes(text);
        bytes memory prefixBytes = bytes(prefix);
        if (prefixBytes.length > textBytes.length) return false;

        for (uint256 i = 0; i < prefixBytes.length; ++i) {
            if (textBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }
}
