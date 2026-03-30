// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {SVGRenderer} from "../../src/SVGRenderer.sol";
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
        SVGRenderer.RenderContext memory context = SVGRenderer.RenderContext({
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

        SVGRenderer.RenderContext memory vaultContext = SVGRenderer.RenderContext({
            packedReport: vaultPacked,
            owner: address(0x1),
            sourceMinter: address(0x2),
            mintedAt: 10,
            mintedBlock: 20
        });
        SVGRenderer.RenderContext memory swapContext = SVGRenderer.RenderContext({
            packedReport: swapPacked,
            owner: address(0x1),
            sourceMinter: address(0x2),
            mintedAt: 10,
            mintedBlock: 20
        });

        string memory vaultUri = harness.build(1, vaultContext);
        string memory swapUri = harness.build(1, swapContext);

        assertTrue(bytes(vaultUri).length > 100);
        assertTrue(bytes(swapUri).length > 100);
        assertFalse(keccak256(bytes(vaultUri)) == keccak256(bytes(swapUri)));
    }

    function test_buildTokenUriChangesWhenContextChanges() public view {
        uint256 packed = erc4626Policy.evaluate("", _baseVaultGuardResult(), VaultOpType.MINT);

        SVGRenderer.RenderContext memory first = SVGRenderer.RenderContext({
            packedReport: packed,
            owner: address(0x1),
            sourceMinter: address(0x2),
            mintedAt: 100,
            mintedBlock: 200
        });
        SVGRenderer.RenderContext memory second = SVGRenderer.RenderContext({
            packedReport: packed,
            owner: address(0x3),
            sourceMinter: address(0x4),
            mintedAt: 300,
            mintedBlock: 400
        });

        string memory firstUri = harness.build(11, first);
        string memory secondUri = harness.build(11, second);

        assertFalse(keccak256(bytes(firstUri)) == keccak256(bytes(secondUri)));
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
