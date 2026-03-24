// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {ILiquidityV2GuardRouter, LiquidityV2GuardCheckResult} from "../RouterDependencies.sol";
import {IUniswapV2Factory, IUniswapV2Router} from "../interfaces/IUniswapV2Interface.sol";
import {
    LiquidityV2RiskPolicy,
    LiquidityV2GuardRiskInput,
    LiquidityV2DecodedRiskReport
} from "../../riskpolicies/LiquidityV2RiskPolicy.sol";
import {LiquidityOpType} from "../../types/OffChainTypes.sol";

contract LiquidityV2Router is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidRecipient();
    error InvalidEthValue();
    error PairNotFound();

    struct LiquidityPreview {
        LiquidityV2GuardCheckResult guardResult;
        uint256 packedRiskReport;
        LiquidityV2DecodedRiskReport decodedRiskReport;
    }

    struct AddLiquidityParams {
        address ammRouter;
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address lpRecipient;
        address refundRecipient;
        uint256 deadline;
    }

    struct AddLiquidityETHParams {
        address ammRouter;
        address token;
        uint256 amountTokenDesired;
        uint256 amountTokenMin;
        uint256 amountETHMin;
        address lpRecipient;
        address refundRecipient;
        uint256 deadline;
    }

    struct RemoveLiquidityParams {
        address ammRouter;
        address tokenA;
        address tokenB;
        uint256 lpAmountToBurn;
        uint256 amountAMin;
        uint256 amountBMin;
        address tokenRecipient;
        uint256 deadline;
    }

    struct RemoveLiquidityETHParams {
        address ammRouter;
        address token;
        uint256 lpAmountToBurn;
        uint256 amountTokenMin;
        uint256 amountETHMin;
        address recipient;
        uint256 deadline;
    }

    ILiquidityV2GuardRouter public liquidityGuard;
    LiquidityV2RiskPolicy public riskPolicy;

    event LiquidityGuardUpdated(address indexed newGuard);
    event RiskPolicyUpdated(address indexed newRiskPolicy);
    event LiquidityCheckStored(
        address indexed user,
        address indexed ammRouter,
        LiquidityOpType indexed operation,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    );
    event GuardedLiquidityExecuted(
        address indexed user,
        address indexed ammRouter,
        LiquidityOpType indexed operation,
        uint256 packedRiskReport
    );

    constructor(address liquidityGuard_, address riskPolicy_) {
        if (liquidityGuard_ == address(0) || riskPolicy_ == address(0)) {
            revert ZeroAddress();
        }

        liquidityGuard = ILiquidityV2GuardRouter(liquidityGuard_);
        riskPolicy = LiquidityV2RiskPolicy(riskPolicy_);
    }

    receive() external payable {}

    function setLiquidityGuard(address newGuard) external onlyOwner {
        if (newGuard == address(0)) {
            revert ZeroAddress();
        }
        liquidityGuard = ILiquidityV2GuardRouter(newGuard);
        emit LiquidityGuardUpdated(newGuard);
    }

    function setRiskPolicy(address newRiskPolicy) external onlyOwner {
        if (newRiskPolicy == address(0)) {
            revert ZeroAddress();
        }
        riskPolicy = LiquidityV2RiskPolicy(newRiskPolicy);
        emit RiskPolicyUpdated(newRiskPolicy);
    }

    function previewAddLiquidity(
        address ammRouter,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        bytes calldata offChainData
    ) external returns (LiquidityPreview memory preview) {
        return _previewLiquidity(
            ammRouter,
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            LiquidityOpType.ADD,
            offChainData
        );
    }

    function previewAddLiquidityETH(
        address ammRouter,
        address token,
        uint256 amountTokenDesired,
        uint256 amountETHDesired,
        bytes calldata offChainData
    ) external returns (LiquidityPreview memory preview) {
        return _previewLiquidity(
            ammRouter,
            token,
            address(0),
            amountTokenDesired,
            amountETHDesired,
            LiquidityOpType.ADD_ETH,
            offChainData
        );
    }

    function previewRemoveLiquidity(
        address ammRouter,
        address tokenA,
        address tokenB,
        uint256 lpAmountToBurn,
        bytes calldata offChainData
    ) external returns (LiquidityPreview memory preview) {
        return _previewLiquidity(
            ammRouter, tokenA, tokenB, lpAmountToBurn, 0, LiquidityOpType.REMOVE, offChainData
        );
    }

    function previewRemoveLiquidityETH(
        address ammRouter,
        address token,
        uint256 lpAmountToBurn,
        bytes calldata offChainData
    ) external returns (LiquidityPreview memory preview) {
        return _previewLiquidity(
            ammRouter, token, address(0), lpAmountToBurn, 0, LiquidityOpType.REMOVE_ETH, offChainData
        );
    }

    function storeAddLiquidityCheck(
        address ammRouter,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external returns (LiquidityV2GuardCheckResult memory guardResult) {
        guardResult = liquidityGuard.storeCheck(
            ammRouter, tokenA, tokenB, amountADesired, amountBDesired, msg.sender, LiquidityOpType.ADD
        );
        emit LiquidityCheckStored(
            msg.sender, ammRouter, LiquidityOpType.ADD, tokenA, tokenB, amountADesired, amountBDesired
        );
    }

    function storeAddLiquidityETHCheck(address ammRouter, address token, uint256 amountTokenDesired, uint256 amountETHDesired)
        external
        returns (LiquidityV2GuardCheckResult memory guardResult)
    {
        guardResult = liquidityGuard.storeCheck(
            ammRouter, token, address(0), amountTokenDesired, amountETHDesired, msg.sender, LiquidityOpType.ADD_ETH
        );
        emit LiquidityCheckStored(
            msg.sender, ammRouter, LiquidityOpType.ADD_ETH, token, address(0), amountTokenDesired, amountETHDesired
        );
    }

    function storeRemoveLiquidityCheck(address ammRouter, address tokenA, address tokenB, uint256 lpAmountToBurn)
        external
        returns (LiquidityV2GuardCheckResult memory guardResult)
    {
        guardResult =
            liquidityGuard.storeCheck(ammRouter, tokenA, tokenB, lpAmountToBurn, 0, msg.sender, LiquidityOpType.REMOVE);
        emit LiquidityCheckStored(msg.sender, ammRouter, LiquidityOpType.REMOVE, tokenA, tokenB, lpAmountToBurn, 0);
    }

    function storeRemoveLiquidityETHCheck(address ammRouter, address token, uint256 lpAmountToBurn)
        external
        returns (LiquidityV2GuardCheckResult memory guardResult)
    {
        guardResult = liquidityGuard.storeCheck(
            ammRouter, token, address(0), lpAmountToBurn, 0, msg.sender, LiquidityOpType.REMOVE_ETH
        );
        emit LiquidityCheckStored(
            msg.sender, ammRouter, LiquidityOpType.REMOVE_ETH, token, address(0), lpAmountToBurn, 0
        );
    }

    function guardedAddLiquidity(AddLiquidityParams calldata params, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256 amountAUsed, uint256 amountBUsed, uint256 liquidity, uint256 packedRiskReport)
    {
        _validateRecipient(params.lpRecipient);
        _validateRecipient(params.refundRecipient);

        packedRiskReport = _validateAndPackLiquidity(
            offChainData,
            params.ammRouter,
            params.tokenA,
            params.tokenB,
            params.amountADesired,
            params.amountBDesired,
            LiquidityOpType.ADD
        );

        IERC20(params.tokenA).safeTransferFrom(msg.sender, address(this), params.amountADesired);
        IERC20(params.tokenB).safeTransferFrom(msg.sender, address(this), params.amountBDesired);
        IERC20(params.tokenA).forceApprove(params.ammRouter, params.amountADesired);
        IERC20(params.tokenB).forceApprove(params.ammRouter, params.amountBDesired);

        (amountAUsed, amountBUsed, liquidity) = IUniswapV2Router(params.ammRouter).addLiquidity(
            params.tokenA,
            params.tokenB,
            params.amountADesired,
            params.amountBDesired,
            params.amountAMin,
            params.amountBMin,
            params.lpRecipient,
            params.deadline
        );

        IERC20(params.tokenA).forceApprove(params.ammRouter, 0);
        IERC20(params.tokenB).forceApprove(params.ammRouter, 0);

        if (params.amountADesired > amountAUsed) {
            IERC20(params.tokenA).safeTransfer(params.refundRecipient, params.amountADesired - amountAUsed);
        }
        if (params.amountBDesired > amountBUsed) {
            IERC20(params.tokenB).safeTransfer(params.refundRecipient, params.amountBDesired - amountBUsed);
        }

        emit GuardedLiquidityExecuted(msg.sender, params.ammRouter, LiquidityOpType.ADD, packedRiskReport);
    }

    function guardedAddLiquidityETH(AddLiquidityETHParams calldata params, bytes calldata offChainData)
        external
        payable
        nonReentrant
        returns (uint256 tokenUsed, uint256 ethUsed, uint256 liquidity, uint256 packedRiskReport)
    {
        _validateRecipient(params.lpRecipient);
        _validateRecipient(params.refundRecipient);

        if (msg.value == 0) {
            revert InvalidEthValue();
        }

        uint256 balanceBefore = address(this).balance - msg.value;

        packedRiskReport = _validateAndPackLiquidity(
            offChainData,
            params.ammRouter,
            params.token,
            address(0),
            params.amountTokenDesired,
            msg.value,
            LiquidityOpType.ADD_ETH
        );

        IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.amountTokenDesired);
        IERC20(params.token).forceApprove(params.ammRouter, params.amountTokenDesired);

        (tokenUsed, ethUsed, liquidity) = IUniswapV2Router(params.ammRouter).addLiquidityETH{value: msg.value}(
            params.token,
            params.amountTokenDesired,
            params.amountTokenMin,
            params.amountETHMin,
            params.lpRecipient,
            params.deadline
        );

        IERC20(params.token).forceApprove(params.ammRouter, 0);

        if (params.amountTokenDesired > tokenUsed) {
            IERC20(params.token).safeTransfer(params.refundRecipient, params.amountTokenDesired - tokenUsed);
        }

        uint256 ethRefund = address(this).balance - balanceBefore;
        if (ethRefund > 0) {
            (bool success,) = payable(params.refundRecipient).call{value: ethRefund}("");
            require(success, "ETH_REFUND_FAILED");
        }

        emit GuardedLiquidityExecuted(msg.sender, params.ammRouter, LiquidityOpType.ADD_ETH, packedRiskReport);
    }

    function guardedRemoveLiquidity(RemoveLiquidityParams calldata params, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256 amountAOut, uint256 amountBOut, uint256 packedRiskReport)
    {
        _validateRecipient(params.tokenRecipient);

        packedRiskReport = _validateAndPackLiquidity(
            offChainData,
            params.ammRouter,
            params.tokenA,
            params.tokenB,
            params.lpAmountToBurn,
            0,
            LiquidityOpType.REMOVE
        );

        address pair = _getPair(params.ammRouter, params.tokenA, params.tokenB);

        IERC20(pair).safeTransferFrom(msg.sender, address(this), params.lpAmountToBurn);
        IERC20(pair).forceApprove(params.ammRouter, params.lpAmountToBurn);

        (amountAOut, amountBOut) = IUniswapV2Router(params.ammRouter).removeLiquidity(
            params.tokenA,
            params.tokenB,
            params.lpAmountToBurn,
            params.amountAMin,
            params.amountBMin,
            params.tokenRecipient,
            params.deadline
        );

        IERC20(pair).forceApprove(params.ammRouter, 0);

        emit GuardedLiquidityExecuted(msg.sender, params.ammRouter, LiquidityOpType.REMOVE, packedRiskReport);
    }

    function guardedRemoveLiquidityETH(RemoveLiquidityETHParams calldata params, bytes calldata offChainData)
        external
        nonReentrant
        returns (uint256 tokenOut, uint256 ethOut, uint256 packedRiskReport)
    {
        _validateRecipient(params.recipient);

        packedRiskReport = _validateAndPackLiquidity(
            offChainData,
            params.ammRouter,
            params.token,
            address(0),
            params.lpAmountToBurn,
            0,
            LiquidityOpType.REMOVE_ETH
        );

        address weth = IUniswapV2Router(params.ammRouter).WETH();
        address pair = _getPair(params.ammRouter, params.token, weth);

        IERC20(pair).safeTransferFrom(msg.sender, address(this), params.lpAmountToBurn);
        IERC20(pair).forceApprove(params.ammRouter, params.lpAmountToBurn);

        (tokenOut, ethOut) = IUniswapV2Router(params.ammRouter).removeLiquidityETH(
            params.token,
            params.lpAmountToBurn,
            params.amountTokenMin,
            params.amountETHMin,
            params.recipient,
            params.deadline
        );

        IERC20(pair).forceApprove(params.ammRouter, 0);

        emit GuardedLiquidityExecuted(msg.sender, params.ammRouter, LiquidityOpType.REMOVE_ETH, packedRiskReport);
    }

    function decodePackedRisk(uint256 packedRiskReport)
        external
        view
        returns (LiquidityV2DecodedRiskReport memory report)
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

    function _previewLiquidity(
        address ammRouter,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        LiquidityOpType operation,
        bytes calldata offChainData
    ) internal returns (LiquidityPreview memory preview) {
        LiquidityV2GuardCheckResult memory guardResult =
            liquidityGuard.checkLiquidity(msg.sender, ammRouter, tokenA, tokenB, amountA, amountB, operation);
        uint256 packedRiskReport =
            riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), operation);

        preview.guardResult = guardResult;
        preview.packedRiskReport = packedRiskReport;
        preview.decodedRiskReport = riskPolicy.decode(packedRiskReport);
    }

    function _toRiskInput(LiquidityV2GuardCheckResult memory guardResult)
        internal
        pure
        returns (LiquidityV2GuardRiskInput memory riskInput)
    {
        riskInput = LiquidityV2GuardRiskInput({
            ROUTER_NOT_TRUSTED: guardResult.ROUTER_NOT_TRUSTED,
            PAIR_NOT_EXISTS: guardResult.PAIR_NOT_EXISTS,
            ZERO_LIQUIDITY: guardResult.ZERO_LIQUIDITY,
            LOW_LIQUIDITY: guardResult.LOW_LIQUIDITY,
            LOW_LP_SUPPLY: guardResult.LOW_LP_SUPPLY,
            FIRST_DEPOSITOR_RISK: guardResult.FIRST_DEPOSITOR_RISK,
            SEVERE_IMBALANCE: guardResult.SEVERE_IMBALANCE,
            K_INVARIANT_BROKEN: guardResult.K_INVARIANT_BROKEN,
            POOL_TOO_NEW: guardResult.POOL_TOO_NEW,
            AMOUNT_RATIO_DEVIATION: guardResult.AMOUNT_RATIO_DEVIATION,
            HIGH_LP_IMPACT: guardResult.HIGH_LP_IMPACT,
            FLASHLOAN_RISK: guardResult.FLASHLOAN_RISK,
            ZERO_LP_OUT: guardResult.ZERO_LP_OUT,
            ZERO_AMOUNTS_OUT: guardResult.ZERO_AMOUNTS_OUT,
            DUST_LP: guardResult.DUST_LP
        });
    }

    function _validateRecipient(address recipient) internal pure {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }
    }

    function _validateAndPackLiquidity(
        bytes calldata offChainData,
        address ammRouter,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        LiquidityOpType operation
    ) internal returns (uint256 packedRiskReport) {
        liquidityGuard.validateCheck(ammRouter, tokenA, tokenB, amountA, amountB, msg.sender, operation);

        LiquidityV2GuardCheckResult memory guardResult =
            liquidityGuard.checkLiquidity(msg.sender, ammRouter, tokenA, tokenB, amountA, amountB, operation);

        packedRiskReport = riskPolicy.evaluate(offChainData, _toRiskInput(guardResult), operation);
    }

    function _getPair(address ammRouter, address tokenA, address tokenB) internal view returns (address pair) {
        pair = IUniswapV2Factory(IUniswapV2Router(ammRouter).factory()).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            revert PairNotFound();
        }
    }
}
