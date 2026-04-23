// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {BaseDeployScript} from "./BaseDeployScript.s.sol";

import {
    BASE_ERC_4626_ROUTER,
    BASE_SWAP_V2_ROUTER,
    BASE_LIQUIDITY_V2_ROUTER,
    BASE_RISK_REPORT_NFT_ADDRESS,
    BASE_SWAP_V2_GUARD_ADDRESS,
    BASE_LIQUIDITY_V2_GUARD_ADDRESS,
    BASE_ERC4626_VAULT_GUARD_ADDRESS
} from "./constants.s.sol";

interface IRiskReportNFT {
    function setAuthorizedMinter(address minter, bool authorized) external;
}

interface ISwapV2Guard {
    function setPreflightCaller(address caller, bool authorized) external;
}

interface ILiquidityV2Guard {
    function setTrustedCaller(address caller, bool authorized) external;
}

interface IERC4626VaultGuard {
    function setAuthorizedRouter(address router, bool authorized) external;
}

contract Config is BaseDeployScript {
    function run() external {
        vm.startBroadcast(_privateKey());

        IRiskReportNFT riskNFT = IRiskReportNFT(BASE_RISK_REPORT_NFT_ADDRESS);
        riskNFT.setAuthorizedMinter(BASE_ERC_4626_ROUTER, true);
        riskNFT.setAuthorizedMinter(BASE_SWAP_V2_ROUTER, true);
        riskNFT.setAuthorizedMinter(BASE_LIQUIDITY_V2_ROUTER, true);

        ISwapV2Guard swapGuard = ISwapV2Guard(BASE_SWAP_V2_GUARD_ADDRESS);
        swapGuard.setPreflightCaller(BASE_SWAP_V2_ROUTER, true);

        ILiquidityV2Guard liquidityGuard = ILiquidityV2Guard(BASE_LIQUIDITY_V2_GUARD_ADDRESS);
        liquidityGuard.setTrustedCaller(BASE_LIQUIDITY_V2_ROUTER, true);

        IERC4626VaultGuard vaultGuard = IERC4626VaultGuard(BASE_ERC4626_VAULT_GUARD_ADDRESS);
        vaultGuard.setAuthorizedRouter(BASE_ERC_4626_ROUTER, true);

        vm.stopBroadcast();
    }
}
