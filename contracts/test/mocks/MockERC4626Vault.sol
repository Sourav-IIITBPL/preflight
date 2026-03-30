// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockERC4626Vault {
    address internal _asset;
    uint8 internal _decimals;
    uint256 internal _totalAssets;
    uint256 internal _totalSupply;

    uint256 internal _maxDeposit;
    uint256 internal _maxMint;
    uint256 internal _maxWithdraw;
    uint256 internal _maxRedeem;

    uint256 internal _previewDeposit;
    uint256 internal _previewMint;
    uint256 internal _previewWithdraw;
    uint256 internal _previewRedeem;

    uint256 internal _convertToShares;
    uint256 internal _convertToAssets;

    bool internal _revertPreviewDeposit;
    bool internal _revertPreviewMint;
    bool internal _revertPreviewWithdraw;
    bool internal _revertPreviewRedeem;
    bool internal _revertConvertToShares;
    bool internal _revertConvertToAssets;

    constructor(address asset_, uint8 decimals_) {
        _asset = asset_;
        _decimals = decimals_;
    }

    function asset() external view returns (address) {
        return _asset;
    }

    function name() external pure returns (string memory) {
        return "Mock Vault";
    }

    function symbol() external pure returns (string memory) {
        return "MVLT";
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function convertToShares(uint256) external view returns (uint256) {
        require(!_revertConvertToShares, "CONVERT_TO_SHARES_REVERT");
        return _convertToShares;
    }

    function convertToAssets(uint256) external view returns (uint256) {
        require(!_revertConvertToAssets, "CONVERT_TO_ASSETS_REVERT");
        return _convertToAssets;
    }

    function maxDeposit(address) external view returns (uint256) {
        return _maxDeposit;
    }

    function previewDeposit(uint256) external view returns (uint256) {
        require(!_revertPreviewDeposit, "PREVIEW_DEPOSIT_REVERT");
        return _previewDeposit;
    }

    function deposit(uint256, address) external pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function maxMint(address) external view returns (uint256) {
        return _maxMint;
    }

    function previewMint(uint256) external view returns (uint256) {
        require(!_revertPreviewMint, "PREVIEW_MINT_REVERT");
        return _previewMint;
    }

    function mint(uint256, address) external pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function maxWithdraw(address) external view returns (uint256) {
        return _maxWithdraw;
    }

    function previewWithdraw(uint256) external view returns (uint256) {
        require(!_revertPreviewWithdraw, "PREVIEW_WITHDRAW_REVERT");
        return _previewWithdraw;
    }

    function withdraw(uint256, address, address) external pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function maxRedeem(address) external view returns (uint256) {
        return _maxRedeem;
    }

    function previewRedeem(uint256) external view returns (uint256) {
        require(!_revertPreviewRedeem, "PREVIEW_REDEEM_REVERT");
        return _previewRedeem;
    }

    function redeem(uint256, address, address) external pure returns (uint256) {
        revert("NOT_IMPLEMENTED");
    }

    function setAccounting(uint256 totalAssets_, uint256 totalSupply_) external {
        _totalAssets = totalAssets_;
        _totalSupply = totalSupply_;
    }

    function setMaxValues(uint256 maxDeposit_, uint256 maxMint_, uint256 maxWithdraw_, uint256 maxRedeem_) external {
        _maxDeposit = maxDeposit_;
        _maxMint = maxMint_;
        _maxWithdraw = maxWithdraw_;
        _maxRedeem = maxRedeem_;
    }

    function setPreviewValues(
        uint256 previewDeposit_,
        uint256 previewMint_,
        uint256 previewWithdraw_,
        uint256 previewRedeem_
    ) external {
        _previewDeposit = previewDeposit_;
        _previewMint = previewMint_;
        _previewWithdraw = previewWithdraw_;
        _previewRedeem = previewRedeem_;
    }

    function setConvertValues(uint256 convertToShares_, uint256 convertToAssets_) external {
        _convertToShares = convertToShares_;
        _convertToAssets = convertToAssets_;
    }

    function setPreviewReverts(
        bool previewDepositReverts,
        bool previewMintReverts,
        bool previewWithdrawReverts,
        bool previewRedeemReverts
    ) external {
        _revertPreviewDeposit = previewDepositReverts;
        _revertPreviewMint = previewMintReverts;
        _revertPreviewWithdraw = previewWithdrawReverts;
        _revertPreviewRedeem = previewRedeemReverts;
    }

    function setConvertReverts(bool convertToSharesReverts, bool convertToAssetsReverts) external {
        _revertConvertToShares = convertToSharesReverts;
        _revertConvertToAssets = convertToAssetsReverts;
    }
}
