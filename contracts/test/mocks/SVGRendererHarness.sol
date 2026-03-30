// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SVGRenderer} from "../../src/SVGRenderer.sol";

contract SVGRendererHarness {
    function build(uint256 tokenId, SVGRenderer.RenderContext memory context) external pure returns (string memory) {
        return SVGRenderer.buildTokenURI(tokenId, context);
    }
}
