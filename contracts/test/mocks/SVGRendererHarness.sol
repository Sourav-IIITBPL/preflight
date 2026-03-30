// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SVGRenderer} from "../../src/nftReport/SVGRenderer.sol";
import {RenderContext} from "../../src/nftReport/interfaces/ISVGRenderer.sol";

contract SVGRendererHarness {
    SVGRenderer public renderer;

    constructor() {
        renderer = new SVGRenderer();
    }

    function build(uint256 tokenId, RenderContext memory context) external view returns (string memory) {
        return renderer.buildTokenURI(tokenId, context);
    }
}
