// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {SVGRenderer} from "../../src/nftReport/SVGRenderer.sol";
import {RenderContext} from "../../src/nftReport/interfaces/ISVGRenderer.sol";
import {RiskPolicyStructBuilder} from "../helpers/RiskPolicyStructBuilder.sol";
import {ERC4626RiskPolicy} from "../../src/riskpolicies/ERC4626RiskPolicy.sol";
import {SwapV2RiskPolicy} from "../../src/riskpolicies/SwapV2RiskPolicy.sol";
import {VaultOpType, SwapOpType} from "../../src/types/OffChainTypes.sol";
import {SVGRendererHarness} from "../mocks/SVGRendererHarness.sol";

contract SVGRendererTest is Test, RiskPolicyStructBuilder {
    SVGRendererHarness internal harness;
    ERC4626RiskPolicy internal erc4626Policy;
    SwapV2RiskPolicy internal swapPolicy;

    function setUp() public {
        harness = new SVGRendererHarness();
        erc4626Policy = new ERC4626RiskPolicy();
        swapPolicy = new SwapV2RiskPolicy();
    }

    function test_buildTokenUriProducesDataUriForVaultReport() public view {
        uint256 packed = erc4626Policy.evaluate("", _baseVaultGuardResult(), VaultOpType.DEPOSIT);
        RenderContext memory context = RenderContext({
            packedReport: packed,
            owner: address(0xB0B),
            sourceMinter: address(0xCAFE),
            mintedAt: uint64(block.timestamp),
            mintedBlock: uint64(block.number)
        });

        string memory uri = harness.build(1, context);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }

    function test_buildTokenUriChangesAcrossPolicyKinds() public view {
        uint256 vaultPacked = erc4626Policy.evaluate("", _baseVaultGuardResult(), VaultOpType.DEPOSIT);
        uint256 swapPacked = swapPolicy.evaluate("", _baseSwapGuardResult(), SwapOpType.EXACT_TOKENS_IN);

        RenderContext memory vaultContext = RenderContext({
            packedReport: vaultPacked, owner: address(0x1), sourceMinter: address(0x2), mintedAt: 10, mintedBlock: 20
        });
        RenderContext memory swapContext = RenderContext({
            packedReport: swapPacked, owner: address(0x1), sourceMinter: address(0x2), mintedAt: 10, mintedBlock: 20
        });

        string memory vaultUri = harness.build(1, vaultContext);
        string memory swapUri = harness.build(1, swapContext);

        assertTrue(bytes(vaultUri).length > 100);
        assertTrue(bytes(swapUri).length > 100);
        assertFalse(keccak256(bytes(vaultUri)) == keccak256(bytes(swapUri)));
    }

    function test_buildTokenUriChangesWhenContextChanges() public view {
        uint256 packed = erc4626Policy.evaluate("", _baseVaultGuardResult(), VaultOpType.MINT);

        RenderContext memory first = RenderContext({
            packedReport: packed, owner: address(0x1), sourceMinter: address(0x2), mintedAt: 100, mintedBlock: 200
        });
        RenderContext memory second = RenderContext({
            packedReport: packed, owner: address(0x3), sourceMinter: address(0x4), mintedAt: 300, mintedBlock: 400
        });

        string memory firstUri = harness.build(11, first);
        string memory secondUri = harness.build(11, second);

        assertFalse(keccak256(bytes(firstUri)) == keccak256(bytes(secondUri)));
    }

    function test_renderNoFindings() public view {
        uint256 packed = erc4626Policy.evaluate("", _baseVaultGuardResult(), VaultOpType.DEPOSIT);
        // Clear all findings (onChain, offChain, token)
        // onChain flags are at bit 0, offChain at 32, token at 174
        packed &= ~(uint256(0xFFFFFFFF)); // clear onChain
        packed &= ~(uint256(0xFFFFFFFF) << 32); // clear offChain
        packed &= ~(uint256(0xFFFFFFFF) << 174); // clear token

        RenderContext memory context = RenderContext({
            packedReport: packed,
            owner: address(0x1),
            sourceMinter: address(0x2),
            mintedAt: 10,
            mintedBlock: 20
        });

        string memory uri = harness.build(999, context);
        assertTrue(bytes(uri).length > 100);
    }

    function test_renderManyFindingsToTriggerWrapping() public view {
        uint256 packed = erc4626Policy.evaluate("", _baseVaultGuardResult(), VaultOpType.DEPOSIT);
        // Set all flags to force wrapping
        packed |= (uint256(0xFFFFFFFF));
        packed |= (uint256(0xFFFFFFFF) << 32);
        packed |= (uint256(0xFFFFFFFF) << 174);

        RenderContext memory context = RenderContext({
            packedReport: packed,
            owner: address(0x1),
            sourceMinter: address(0x2),
            mintedAt: 10,
            mintedBlock: 20
        });

        string memory uri = harness.build(888, context);
        assertTrue(bytes(uri).length > 100);
    }

    function test_renderFindingsColors() public view {
        uint256 packed = erc4626Policy.evaluate("", _baseVaultGuardResult(), VaultOpType.DEPOSIT);
        
        // Final category depends on composite score: 0-19 INFO, 20-39 WARNING, 40-69 MEDIUM, 70+ CRITICAL
        // Composite score is bits 64-71
        
        uint256 packedInfo = (packed & ~(uint256(0xFF) << 64)) | (uint256(10) << 64);
        uint256 packedWarn = (packed & ~(uint256(0xFF) << 64)) | (uint256(30) << 64);
        uint256 packedMed = (packed & ~(uint256(0xFF) << 64)) | (uint256(50) << 64);
        
        RenderContext memory ctx = RenderContext({
            packedReport: packedInfo, owner: address(0x1), sourceMinter: address(0x2), mintedAt: 1, mintedBlock: 1
        });
        harness.build(1, ctx);
        
        ctx.packedReport = packedWarn;
        harness.build(2, ctx);
        
        ctx.packedReport = packedMed;
        harness.build(3, ctx);
    }

    function test_renderTiers() public view {
        uint256 packed = erc4626Policy.evaluate("", _baseVaultGuardResult(), VaultOpType.DEPOSIT);
        // Set all tiers to something non-zero
        // SHIFT_ECONOMIC_TIER = 219, etc.
        packed |= (uint256(1) << 219);
        packed |= (uint256(2) << 222);
        packed |= (uint256(3) << 225);
        packed |= (uint256(4) << 228);
        packed |= (uint256(5) << 235);
        
        RenderContext memory context = RenderContext({
            packedReport: packed,
            owner: address(0x1),
            sourceMinter: address(0x2),
            mintedAt: 10,
            mintedBlock: 20
        });

        string memory uri = harness.build(777, context);
        assertTrue(bytes(uri).length > 100);
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
