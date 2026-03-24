// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {ISwapV2GuardRouter, SwapV2GuardCheckResult} from "../RouterDependencies.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Interface.sol";
import {
    SwapV2RiskPolicy,
    SwapV2GuardRiskInput,
    SwapV2DecodedRiskReport
} from "../../riskpolicies/SwapV2RiskPolicy.sol";
import {SwapOpType} from "../../types/OffChainTypes.sol";

contract SwapV2Router is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidPath();
    error InvalidReceiver();
    error InvalidWethPath();
    error InsufficientEthValue();

    struct SwapPreview {
        SwapV2GuardCheckResult guardResult;
        uint256 packedRiskReport;
        SwapV2DecodedRiskReport decodedRiskReport;
    }

    ISwapV2GuardRouter public swapGuard;
    SwapV2RiskPolicy public riskPolicy;

    event SwapGuardUpdated(address indexed newGuard);
    event RiskPolicyUpdated(address indexed newRiskPolicy);
    event SwapCheckStored(
        address indexed user,
        address indexed ammRouter,
        bytes32 indexed pathHash,
        uint256 checkAmountIn
    );
    event GuardedSwapExecuted(
        address indexed user,
        address indexed ammRouter,
        SwapOpType operation,
        bytes32 indexed pathHash,
        uint256 packedRiskReport
    );

    constructor(address swapGuard_, address riskPolicy_) {
        if (swapGuard_ == address(0) || riskPolicy_ == address(0)) {
            revert ZeroAddress();
        }

        swapGuard = ISwapV2GuardRouter(swapGuard_);
        riskPolicy = SwapV2RiskPolicy(riskPolicy_);
    }

    receive() external payable {}

    function setSwapGuard(address newGuard) external onlyOwner {
        if (newGuard == address(0)) {
            revert ZeroAddress();
        }
        swapGuard = ISwapV2GuardRouter(newGuard);
        emit SwapGuardUpdated(newGuard);
    }

    function setRiskPolicy(address newRiskPolicy) external onlyOwner {
        if (newRiskPolicy == address(0)) {
            revert ZeroAddress();
        }
        riskPolicy = SwapV2RiskPolicy(newRiskPolicy);
        emit RiskPolicyUpdated(newRiskPolicy);
    }

    function previewSwapRisk(
        address ammRouter,
        address[] calldata path,
        uint256 checkAmountIn,
        bytes calldata offChainData,
        SwapOpType operation
    ) external returns (SwapPreview memory preview) {
        _validatePath(path);

        SwapV2GuardCheckResult memory guardResult = swapGuard.swapCheckV2(ammRouter, path, checkAmountIn);
        uint256 packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), operation);

        preview.guardResult = guardResult;
        preview.packedRiskReport = packedRiskReport;
        preview.decodedRiskReport = riskPolicy.decode(packedRiskReport);
    }

    function storeSwapCheck(address ammRouter, address[] calldata path, uint256 checkAmountIn)
        external
        returns (SwapV2GuardCheckResult memory guardResult)
    {
        _validatePath(path);
        guardResult = swapGuard.storeSwapCheck(ammRouter, path, checkAmountIn, msg.sender);
        emit SwapCheckStored(msg.sender, ammRouter, keccak256(abi.encode(path)), checkAmountIn);
    }

    function guardedSwapExactTokensForTokens(
        address ammRouter,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address receiver,
        uint256 deadline,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validatePath(path);
        _validateReceiver(receiver);

        swapGuard.validateSwapCheck(ammRouter, path, amountIn, msg.sender);
        SwapV2GuardCheckResult memory guardResult = swapGuard.swapCheckV2(ammRouter, path, amountIn);
        packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), SwapOpType.EXACT_TOKENS_IN);

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).forceApprove(ammRouter, amountIn);
        amounts = IUniswapV2Router(ammRouter).swapExactTokensForTokens(
            amountIn, amountOutMin, path, receiver, deadline
        );
        IERC20(path[0]).forceApprove(ammRouter, 0);

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, SwapOpType.EXACT_TOKENS_IN, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    function guardedSwapTokensForExactTokens(
        address ammRouter,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address receiver,
        address refundRecipient,
        uint256 deadline,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validatePath(path);
        _validateReceiver(receiver);
        _validateReceiver(refundRecipient);

        swapGuard.validateSwapCheck(ammRouter, path, amountInMax, msg.sender);
        SwapV2GuardCheckResult memory guardResult = swapGuard.swapCheckV2(ammRouter, path, amountInMax);
        packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), SwapOpType.EXACT_TOKENS_OUT);

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountInMax);
        IERC20(path[0]).forceApprove(ammRouter, amountInMax);
        amounts = IUniswapV2Router(ammRouter).swapTokensForExactTokens(
            amountOut, amountInMax, path, receiver, deadline
        );
        IERC20(path[0]).forceApprove(ammRouter, 0);

        uint256 refundAmount = amountInMax - amounts[0];
        if (refundAmount > 0) {
            IERC20(path[0]).safeTransfer(refundRecipient, refundAmount);
        }

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, SwapOpType.EXACT_TOKENS_OUT, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    function guardedSwapExactETHForTokens(
        address ammRouter,
        uint256 amountOutMin,
        address[] calldata path,
        address receiver,
        uint256 deadline,
        bytes calldata offChainData
    ) external payable nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validatePath(path);
        _validateReceiver(receiver);
        _requireStartsWithWeth(ammRouter, path);

        swapGuard.validateSwapCheck(ammRouter, path, msg.value, msg.sender);
        SwapV2GuardCheckResult memory guardResult = swapGuard.swapCheckV2(ammRouter, path, msg.value);
        packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), SwapOpType.EXACT_ETH_IN);

        amounts = IUniswapV2Router(ammRouter).swapExactETHForTokens{value: msg.value}(
            amountOutMin, path, receiver, deadline
        );

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, SwapOpType.EXACT_ETH_IN, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    function guardedSwapETHForExactTokens(
        address ammRouter,
        uint256 amountOut,
        address[] calldata path,
        address receiver,
        address refundRecipient,
        uint256 deadline,
        bytes calldata offChainData
    ) external payable nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validatePath(path);
        _validateReceiver(receiver);
        _validateReceiver(refundRecipient);
        _requireStartsWithWeth(ammRouter, path);

        if (msg.value == 0) {
            revert InsufficientEthValue();
        }

        uint256 balanceBefore = address(this).balance - msg.value;

        swapGuard.validateSwapCheck(ammRouter, path, msg.value, msg.sender);
        SwapV2GuardCheckResult memory guardResult = swapGuard.swapCheckV2(ammRouter, path, msg.value);
        packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), SwapOpType.EXACT_ETH_OUT);

        amounts = IUniswapV2Router(ammRouter).swapETHForExactTokens{value: msg.value}(
            amountOut, path, receiver, deadline
        );

        uint256 refundAmount = address(this).balance - balanceBefore;
        if (refundAmount > 0) {
            (bool success,) = payable(refundRecipient).call{value: refundAmount}("");
            require(success, "ETH_REFUND_FAILED");
        }

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, SwapOpType.EXACT_ETH_OUT, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    function guardedSwapExactTokensForETH(
        address ammRouter,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address receiver,
        uint256 deadline,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validatePath(path);
        _validateReceiver(receiver);
        _requireEndsWithWeth(ammRouter, path);

        swapGuard.validateSwapCheck(ammRouter, path, amountIn, msg.sender);
        SwapV2GuardCheckResult memory guardResult = swapGuard.swapCheckV2(ammRouter, path, amountIn);
        packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), SwapOpType.EXACT_TOKENS_FOR_ETH);

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(path[0]).forceApprove(ammRouter, amountIn);
        amounts = IUniswapV2Router(ammRouter).swapExactTokensForETH(
            amountIn, amountOutMin, path, receiver, deadline
        );
        IERC20(path[0]).forceApprove(ammRouter, 0);

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, SwapOpType.EXACT_TOKENS_FOR_ETH, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    function guardedSwapTokensForExactETH(
        address ammRouter,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address receiver,
        address refundRecipient,
        uint256 deadline,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256[] memory amounts, uint256 packedRiskReport) {
        _validatePath(path);
        _validateReceiver(receiver);
        _validateReceiver(refundRecipient);
        _requireEndsWithWeth(ammRouter, path);

        swapGuard.validateSwapCheck(ammRouter, path, amountInMax, msg.sender);
        SwapV2GuardCheckResult memory guardResult = swapGuard.swapCheckV2(ammRouter, path, amountInMax);
        packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), SwapOpType.TOKENS_FOR_EXACT_ETH);

        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountInMax);
        IERC20(path[0]).forceApprove(ammRouter, amountInMax);
        amounts = IUniswapV2Router(ammRouter).swapTokensForExactETH(
            amountOut, amountInMax, path, receiver, deadline
        );
        IERC20(path[0]).forceApprove(ammRouter, 0);

        uint256 refundAmount = amountInMax - amounts[0];
        if (refundAmount > 0) {
            IERC20(path[0]).safeTransfer(refundRecipient, refundAmount);
        }

        emit GuardedSwapExecuted(
            msg.sender, ammRouter, SwapOpType.TOKENS_FOR_EXACT_ETH, keccak256(abi.encode(path)), packedRiskReport
        );
    }

    function decodePackedRisk(uint256 packedRiskReport)
        external
        view
        returns (SwapV2DecodedRiskReport memory report)
    {
        return riskPolicy.decode(packedRiskReport);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        IERC20(token).safeTransfer(to, amount);
    }

    function rescueETH(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        (bool success,) = to.call{value: amount}("");
        require(success, "ETH_RESCUE_FAILED");
    }

    function _toRiskInput(SwapV2GuardCheckResult memory guardResult)
        internal
        pure
        returns (SwapV2GuardRiskInput memory riskInput)
    {
        riskInput = SwapV2GuardRiskInput({
            ROUTER_NOT_TRUSTED: guardResult.ROUTER_NOT_TRUSTED,
            FACTORY_NOT_TRUSTED: guardResult.FACTORY_NOT_TRUSTED,
            DEEP_MULTIHOP: guardResult.DEEP_MULTIHOP,
            DUPLICATE_TOKEN_IN_PATH: guardResult.DUPLICATE_TOKEN_IN_PATH,
            POOL_NOT_EXISTS: guardResult.POOL_NOT_EXISTS,
            FACTORY_MISMATCH: guardResult.FACTORY_MISMATCH,
            ZERO_LIQUIDITY: guardResult.ZERO_LIQUIDITY,
            LOW_LIQUIDITY: guardResult.LOW_LIQUIDITY,
            LOW_LP_SUPPLY: guardResult.LOW_LP_SUPPLY,
            POOL_TOO_NEW: guardResult.POOL_TOO_NEW,
            SEVERE_IMBALANCE: guardResult.SEVERE_IMBALANCE,
            K_INVARIANT_BROKEN: guardResult.K_INVARIANT_BROKEN,
            HIGH_SWAP_IMPACT: guardResult.HIGH_SWAP_IMPACT,
            FLASHLOAN_RISK: guardResult.FLASHLOAN_RISK,
            PRICE_MANIPULATED: guardResult.PRICE_MANIPULATED
        });
    }

    function _validatePath(address[] calldata path) internal pure {
        if (path.length < 2) {
            revert InvalidPath();
        }
    }

    function _validateReceiver(address receiver) internal pure {
        if (receiver == address(0)) {
            revert InvalidReceiver();
        }
    }

    function _requireStartsWithWeth(address ammRouter, address[] calldata path) internal view {
        if (path[0] != IUniswapV2Router(ammRouter).WETH()) {
            revert InvalidWethPath();
        }
    }

    function _requireEndsWithWeth(address ammRouter, address[] calldata path) internal view {
        if (path[path.length - 1] != IUniswapV2Router(ammRouter).WETH()) {
            revert InvalidWethPath();
        }
    }
}
