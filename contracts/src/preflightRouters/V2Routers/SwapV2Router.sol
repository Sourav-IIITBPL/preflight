// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {ISwapV2Guard} from "../interfaces/IGuards.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Interface.sol";
import {SwapV2GuardResult} from "../../types/OnChainTypes.sol";
import {ISwapV2RiskPolicy, IRiskReportNFT} from "../interfaces/IRiskPolicy.sol";
import {SwapV2DecodedRiskReport} from "../../riskpolicies/SwapV2RiskPolicy.sol";
import {SwapOpType} from "../../types/OffChainTypes.sol";

/**
 * @author Sourav-IITBPL
 * @notice Router for guarded Uniswap V2-style swap flows with risk report minting.
 */
contract SwapV2Router is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Raised when a required contract or recipient address is zero.
    error ZeroAddress();
    /// @notice Raised when a swap path is too short to represent a valid route.
    error InvalidPath();
    /// @notice Raised when a swap receiver or refund recipient is invalid.
    error InvalidReceiver();
    /// @notice Raised when an ETH route does not start or end with the router's WETH token as required.
    error InvalidWethPath();
    /// @notice Raised when an ETH-based swap flow is called without the required native value.
    error InvalidEthValue();

    ISwapV2Guard public swapGuard;
    ISwapV2RiskPolicy public riskPolicy;
    IRiskReportNFT public riskReportNFT;

    /// @notice Emitted when the router updates its swap guard dependency.
    event SwapGuardUpdated(address indexed newGuard);
    /// @notice Emitted when the router updates its swap risk policy dependency.
    event RiskPolicyUpdated(address indexed newRiskPolicy);
    /// @notice Emitted when the router updates the NFT contract used for report minting.
    event RiskReportNFTUpdated(address indexed newRiskReportNFT);
    /// @notice Emitted when a swap check is stored and evaluated into a packed report.
    event SwapCheckStored(
        address indexed user,
        address indexed ammRouter,
        SwapOpType operation,
        bytes32 indexed pathHash,
        uint256 amountForCheck,
        uint256 packedRiskReport
    );
    /// @notice Emitted after a guarded swap executes successfully.
    event GuardedSwapExecuted(
        address indexed user,
        address indexed ammRouter,
        address indexed receiver,
        SwapOpType operation,
        bytes32 pathHash,
        uint256 packedRiskReport
    );

    /**
     * @notice Deploys the router with the swap guard, risk policy, and report NFT.
     * @param swapGuard_ Address of the swap guard contract.
     * @param riskPolicy_ Address of the swap risk policy contract.
     * @param riskReportNFT_ Address of the risk report NFT contract.
     */
    constructor(address swapGuard_, address riskPolicy_, address riskReportNFT_) {
        if (swapGuard_ == address(0) || riskPolicy_ == address(0) || riskReportNFT_ == address(0)) {
            revert ZeroAddress();
        }

        swapGuard = ISwapV2Guard(swapGuard_);
        riskPolicy = ISwapV2RiskPolicy(riskPolicy_);
        riskReportNFT = IRiskReportNFT(riskReportNFT_);
    }

    /// @notice Accepts ETH refunds from router calls.
    receive() external payable {}

    /**
     * @notice Updates the swap guard used by the router.
     * @param newGuard Address of the new swap guard.
     */
    function setSwapGuard(address newGuard) external onlyOwner {
        if (newGuard == address(0)) {
            revert ZeroAddress();
        }
        swapGuard = ISwapV2Guard(newGuard);
        emit SwapGuardUpdated(newGuard);
    }

    /**
     * @notice Updates the risk policy used to evaluate swap checks.
     * @param newRiskPolicy Address of the new swap risk policy contract.
     */
    function setRiskPolicy(address newRiskPolicy) external onlyOwner {
        if (newRiskPolicy == address(0)) {
            revert ZeroAddress();
        }
        riskPolicy = ISwapV2RiskPolicy(newRiskPolicy);
        emit RiskPolicyUpdated(newRiskPolicy);
    }

    /**
     * @notice Updates the NFT contract used to mint swap risk reports.
     * @param newRiskReportNFT Address of the new risk report NFT contract.
     */
    function setRiskReportNFT(address newRiskReportNFT) external onlyOwner {
        if (newRiskReportNFT == address(0)) {
            revert ZeroAddress();
        }
        riskReportNFT = IRiskReportNFT(newRiskReportNFT);
        emit RiskReportNFTUpdated(newRiskReportNFT);
    }

    /**
     * @notice Previews a guarded swap quote for the provided path and swap mode.
     * @param ammRouter Address of the AMM router.
     * @param path Swap path.
     * @param isExactTokenIn Whether the preview should use exact-input quoting.
     * @param amountIn Amount supplied to the guard as the quote input.
     * @return result Guard result for the swap.
     * @return amountOut Final quote amount returned from the guard-backed router query.
     */
    function guardedPreview(address ammRouter, address[] calldata path, bool isExactTokenIn, uint256 amountIn)
        external
        returns (SwapV2GuardResult memory result, uint256 amountOut)
    {
        uint256[] memory amountsOut;
        (result, amountsOut) = swapGuard.swapCheckV2(ammRouter, path, amountIn, isExactTokenIn);
        if (isExactTokenIn) {
            amountOut = amountsOut[amountsOut.length - 1];
        } else {
            amountOut = amountsOut[0];
        }
    }

    /**
     * @notice Stores and mints the risk report for an exact-input token-to-token swap check.
     * @param ammRouter Address of the AMM router.
     * @param path Swap path.
     * @param amount Amount used for the swap check.
     * @param operationType Swap operation type.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return packedRiskReport Packed risk report for the swap.
     */
    function storeAndMintSwapCheck(
        address ammRouter,
        address[] calldata path,
        uint256 amount,
        SwapOpType operationType,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 packedRiskReport) {
        return _storeAndMintSwapCheck(ammRouter, path, amount, offChainData, operationType);
    }

    /**
     * @notice Executes a guarded exact-input token-to-token swap.
     * @param ammRouter Address of the AMM router.
     * @param amountIn Exact token input amount.
     * @param amountOutMin Minimum acceptable output amount.
     * @param path Swap path.
     * @param receiver Recipient of the output tokens.
     * @param deadline Swap deadline timestamp.
     * @return amounts Router output amounts per hop.
     * @return packedRiskReport Packed risk report for the swap.
     */
    function guardedSwapExactTokensForTokens(
        address ammRouter,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address receiver,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validateReceiver(receiver);

        swapGuard.validateSwapCheck(ammRouter, path, amountIn, true, msg.sender);

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).forceApprove(ammRouter, amountIn);
        amounts = IUniswapV2Router(ammRouter).swapExactTokensForTokens(amountIn, amountOutMin, path, receiver, deadline);
        IERC20(path[0]).forceApprove(ammRouter, 0);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert("INSUFFICIENT_OUTPUT_AMOUNT");
        }

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, receiver, SwapOpType.EXACT_TOKENS_IN, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    /**
     * @notice Executes a guarded exact-output token-to-token swap.
     * @param ammRouter Address of the AMM router.
     * @param amountOut Exact output amount requested.
     * @param amountInMax Maximum token input amount.
     * @param path Swap path.
     * @param receiver Recipient of the output tokens.
     * @param refundRecipient Recipient of any unused input tokens.
     * @param deadline Swap deadline timestamp.
     * @return amounts Router output amounts per hop.
     * @return packedRiskReport Packed risk report for the swap.
     */
    function guardedSwapTokensForExactTokens(
        address ammRouter,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address receiver,
        address refundRecipient,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validateReceiver(receiver);
        _validateReceiver(refundRecipient);

        swapGuard.validateSwapCheck(ammRouter, path, amountInMax, false, msg.sender);

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountInMax);
        IERC20(path[0]).forceApprove(ammRouter, amountInMax);
        amounts = IUniswapV2Router(ammRouter).swapTokensForExactTokens(amountOut, amountInMax, path, receiver, deadline);
        IERC20(path[0]).forceApprove(ammRouter, 0);

        if (amountInMax > amounts[0]) {
            IERC20(path[0]).safeTransfer(refundRecipient, amountInMax - amounts[0]);
        }

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, receiver, SwapOpType.EXACT_TOKENS_OUT, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    /**
     * @notice Executes a guarded exact-input ETH-to-token swap.
     * @param ammRouter Address of the AMM router.
     * @param amountOutMin Minimum acceptable token output.
     * @param path Swap path.
     * @param receiver Recipient of the output tokens.
     * @param deadline Swap deadline timestamp.
     * @return amounts Router output amounts per hop.
     * @return packedRiskReport Packed risk report for the swap.
     */
    function guardedSwapExactETHForTokens(
        address ammRouter,
        uint256 amountOutMin,
        address[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validateReceiver(receiver);
        _requireStartsWithWeth(ammRouter, path);

        if (msg.value == 0) {
            revert InvalidEthValue();
        }

        swapGuard.validateSwapCheck(ammRouter, path, msg.value, true, msg.sender);

        amounts =
            IUniswapV2Router(ammRouter).swapExactETHForTokens{value: msg.value}(amountOutMin, path, receiver, deadline);

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, receiver, SwapOpType.EXACT_ETH_IN, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    /**
     * @notice Executes a guarded exact-output ETH-to-token swap.
     * @param ammRouter Address of the AMM router.
     * @param amountOut Exact token output requested.
     * @param path Swap path.
     * @param receiver Recipient of the output tokens.
     * @param refundRecipient Recipient of refunded ETH.
     * @param deadline Swap deadline timestamp.
     * @return amounts Router output amounts per hop.
     * @return packedRiskReport Packed risk report for the swap.
     */
    function guardedSwapETHForExactTokens(
        address ammRouter,
        uint256 amountOut,
        address[] calldata path,
        address receiver,
        address refundRecipient,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validateReceiver(receiver);
        _validateReceiver(refundRecipient);
        _requireStartsWithWeth(ammRouter, path);

        if (msg.value == 0) {
            revert InvalidEthValue();
        }

        uint256 balanceBefore = address(this).balance - msg.value;

        swapGuard.validateSwapCheck(ammRouter, path, msg.value, false, msg.sender);

        amounts =
            IUniswapV2Router(ammRouter).swapETHForExactTokens{value: msg.value}(amountOut, path, receiver, deadline);

        uint256 refundAmount = address(this).balance - balanceBefore;
        if (refundAmount > 0) {
            (bool success,) = payable(refundRecipient).call{value: refundAmount}("");
            require(success, "ETH_REFUND_FAILED");
        }

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, receiver, SwapOpType.EXACT_ETH_OUT, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    /**
     * @notice Executes a guarded exact-input token-to-ETH swap.
     * @param ammRouter Address of the AMM router.
     * @param amountIn Exact token input amount.
     * @param amountOutMin Minimum acceptable ETH output.
     * @param path Swap path.
     * @param receiver Recipient of the ETH output.
     * @param deadline Swap deadline timestamp.
     * @return amounts Router output amounts per hop.
     * @return packedRiskReport Packed risk report for the swap.
     */
    function guardedSwapExactTokensForETH(
        address ammRouter,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address receiver,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validateReceiver(receiver);
        _requireEndsWithWeth(ammRouter, path);

        swapGuard.validateSwapCheck(ammRouter, path, amountIn, true, msg.sender);

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).forceApprove(ammRouter, amountIn);
        amounts = IUniswapV2Router(ammRouter).swapExactTokensForETH(amountIn, amountOutMin, path, receiver, deadline);
        IERC20(path[0]).forceApprove(ammRouter, 0);

        if (amountOutMin > amounts[amounts.length - 1]) {
            revert("INSUFFICIENT_OUTPUT_AMOUNT");
        }

        emit GuardedSwapExecuted(
            msg.sender,
            ammRouter,
            receiver,
            SwapOpType.EXACT_TOKENS_FOR_ETH,
            keccak256(abi.encode(path)),
            packedRiskReport
        );
    }

    /**
     * @notice Executes a guarded exact-output token-to-ETH swap.
     * @param ammRouter Address of the AMM router.
     * @param amountOut Exact ETH output requested.
     * @param amountInMax Maximum token input amount.
     * @param path Swap path.
     * @param receiver Recipient of the ETH output.
     * @param refundRecipient Recipient of any unused input tokens.
     * @param deadline Swap deadline timestamp.
     * @return amounts Router output amounts per hop.
     * @return packedRiskReport Packed risk report for the swap.
     */
    function guardedSwapTokensForExactETH(
        address ammRouter,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address receiver,
        address refundRecipient,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validateReceiver(receiver);
        _validateReceiver(refundRecipient);
        _requireEndsWithWeth(ammRouter, path);

        swapGuard.validateSwapCheck(ammRouter, path, amountInMax, false, msg.sender);

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountInMax);
        IERC20(path[0]).forceApprove(ammRouter, amountInMax);
        amounts = IUniswapV2Router(ammRouter).swapTokensForExactETH(amountOut, amountInMax, path, receiver, deadline);
        IERC20(path[0]).forceApprove(ammRouter, 0);

        if (amountInMax > amounts[0]) {
            IERC20(path[0]).safeTransfer(refundRecipient, amountInMax - amounts[0]);
        }

        emit GuardedSwapExecuted(
            msg.sender,
            ammRouter,
            receiver,
            SwapOpType.TOKENS_FOR_EXACT_ETH,
            keccak256(abi.encode(path)),
            packedRiskReport
        );
    }

    /**
     * @notice Decodes a packed swap risk report.
     * @param packedRiskReport Packed risk report value.
     * @return report Decoded swap risk report.
     */
    function decodePackedRisk(uint256 packedRiskReport) external view returns (SwapV2DecodedRiskReport memory report) {
        return riskPolicy.decode(packedRiskReport);
    }

    /**
     * @notice Rescues ERC-20 tokens held by the router.
     * @param token Address of the token to rescue.
     * @param to Recipient of the rescued tokens.
     * @param amount Amount of tokens to transfer.
     */
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Rescues ETH held by the router.
     * @param to Recipient of the rescued ETH.
     * @param amount Amount of ETH to transfer.
     */
    function rescueETH(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        (bool success,) = to.call{value: amount}("");
        require(success, "ETH_RESCUE_FAILED");
    }

    /// @dev Stores a swap check, evaluates the packed policy report, and mints the corresponding NFT.
    /// @param ammRouter Address of the AMM router.
    /// @param path Swap path used for the check.
    /// @param amountForCheck Amount submitted to the swap guard.
    /// @param offChainData ABI-encoded off-chain simulation data.
    /// @param operation Swap operation being evaluated.
    /// @return packedRiskReport Packed risk report produced by the policy.
    function _storeAndMintSwapCheck(
        address ammRouter,
        address[] calldata path,
        uint256 amountForCheck,
        bytes calldata offChainData,
        SwapOpType operation
    ) internal returns (uint256 packedRiskReport) {
        _validatePath(path);

        SwapV2GuardResult memory result =
            swapGuard.storeSwapCheck(ammRouter, path, amountForCheck, _isExactTokenIn(operation), msg.sender);
        packedRiskReport = riskPolicy.evaluate(offChainData, result, operation);
        riskReportNFT.mint(packedRiskReport, msg.sender);

        emit SwapCheckStored(
            msg.sender, ammRouter, operation, keccak256(abi.encode(path)), amountForCheck, packedRiskReport
        );
    }

    /// @dev Returns whether a swap operation uses exact-input semantics for guard quoting.
    /// @param operation Swap operation to classify.
    /// @return True when the operation is exact-input based.
    function _isExactTokenIn(SwapOpType operation) internal pure returns (bool) {
        return operation == SwapOpType.EXACT_TOKENS_IN || operation == SwapOpType.EXACT_ETH_IN
            || operation == SwapOpType.EXACT_TOKENS_FOR_ETH;
    }

    /// @dev Reverts when a path does not contain at least two assets.
    /// @param path Swap path to validate.
    function _validatePath(address[] calldata path) internal pure {
        if (path.length < 2) {
            revert InvalidPath();
        }
    }

    /// @dev Reverts when a receiver-like address is zero.
    /// @param receiver Address to validate.
    function _validateReceiver(address receiver) internal pure {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }
    }

    /// @dev Reverts unless the first path token matches the router's wrapped native token.
    /// @param ammRouter Address of the AMM router.
    /// @param path Swap path to validate.
    function _requireStartsWithWeth(address ammRouter, address[] calldata path) internal view {
        _validatePath(path);
        if (path[0] != IUniswapV2Router(ammRouter).WETH()) {
            revert InvalidWethPath();
        }
    }

    /// @dev Reverts unless the final path token matches the router's wrapped native token.
    /// @param ammRouter Address of the AMM router.
    /// @param path Swap path to validate.
    function _requireEndsWithWeth(address ammRouter, address[] calldata path) internal view {
        _validatePath(path);
        if (path[path.length - 1] != IUniswapV2Router(ammRouter).WETH()) {
            revert InvalidWethPath();
        }
    }
}
