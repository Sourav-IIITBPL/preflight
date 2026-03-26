// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

import {ILiquidityV2Guard} from "../interfaces/IGuards.sol";
import {IUniswapV2Factory, IUniswapV2Router} from "../interfaces/IUniswapV2Interface.sol";
import {LiquidityV2GuardResult, LiquidityOperationType} from "../../types/OnChainTypes.sol";
import {ILiquidityV2RiskPolicy, IRiskReportNFT} from "../interfaces/IRiskPolicy.sol";
import {LiquidityOpType} from "../../types/OffChainTypes.sol";
import {LiquidityV2DecodedRiskReport} from "../../riskpolicies/LiquidityV2RiskPolicy.sol";

//  @author Sourav-IITBPL

contract LiquidityV2Router is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidRecipient();
    error InvalidEthValue();
    error PairNotFound();

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

    ILiquidityV2Guard public liquidityGuard;
    ILiquidityV2RiskPolicy public riskPolicy;
    IRiskReportNFT public riskReportNFT;

    event LiquidityGuardUpdated(address indexed newGuard);
    event RiskPolicyUpdated(address indexed newRiskPolicy);
    event RiskReportNFTUpdated(address indexed newRiskReportNFT);
    event LiquidityCheckStored(
        address indexed user,
        address indexed ammRouter,
        LiquidityOperationType operation,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 packedRiskReport
    );
    event GuardedLiquidityExecuted(
        address indexed user, address indexed ammRouter, address indexed recipient, LiquidityOperationType operation
    );

    constructor(address liquidityGuard_, address riskPolicy_, address riskReportNFT_) {
        if (liquidityGuard_ == address(0) || riskPolicy_ == address(0) || riskReportNFT_ == address(0)) {
            revert ZeroAddress();
        }

        liquidityGuard = ILiquidityV2Guard(liquidityGuard_);
        riskPolicy = ILiquidityV2RiskPolicy(riskPolicy_);
        riskReportNFT = IRiskReportNFT(riskReportNFT_);
    }

    receive() external payable {}

    function setLiquidityGuard(address newGuard) external onlyOwner {
        if (newGuard == address(0)) {
            revert ZeroAddress();
        }
        liquidityGuard = ILiquidityV2Guard(newGuard);
        emit LiquidityGuardUpdated(newGuard);
    }

    function setRiskPolicy(address newRiskPolicy) external onlyOwner {
        if (newRiskPolicy == address(0)) {
            revert ZeroAddress();
        }
        riskPolicy = ILiquidityV2RiskPolicy(newRiskPolicy);
        emit RiskPolicyUpdated(newRiskPolicy);
    }

    function setRiskReportNFT(address newRiskReportNFT) external onlyOwner {
        if (newRiskReportNFT == address(0)) {
            revert ZeroAddress();
        }
        riskReportNFT = IRiskReportNFT(newRiskReportNFT);
        emit RiskReportNFTUpdated(newRiskReportNFT);
    }

    function previewGuardedAddLiquidity(
        address ammRouter,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external returns (LiquidityV2GuardResult memory result) {
        result = liquidityGuard.checkLiquidity(
            msg.sender, ammRouter, tokenA, tokenB, amountADesired, amountBDesired, LiquidityOperationType.ADD
        );
    }

    function previewGuardedAddLiquidityETH(
        address ammRouter,
        address token,
        uint256 amountTokenDesired,
        uint256 amountETHDesired
    ) external returns (LiquidityV2GuardResult memory result) {
        result = liquidityGuard.checkLiquidity(
            msg.sender,
            ammRouter,
            token,
            address(0),
            amountTokenDesired,
            amountETHDesired,
            LiquidityOperationType.ADD_ETH
        );
    }

    function previewGuardedRemoveLiquidity(address ammRouter, address tokenA, address tokenB, uint256 lpAmountToBurn)
        external
        returns (LiquidityV2GuardResult memory result)
    {
        result = liquidityGuard.checkLiquidity(
            msg.sender, ammRouter, tokenA, tokenB, lpAmountToBurn, 0, LiquidityOperationType.REMOVE
        );
    }

    function previewGuardedRemoveLiquidityETH(address ammRouter, address token, uint256 lpAmountToBurn)
        external
        returns (LiquidityV2GuardResult memory result)
    {
        result = liquidityGuard.checkLiquidity(
            msg.sender, ammRouter, token, address(0), lpAmountToBurn, 0, LiquidityOperationType.REMOVE_ETH
        );
    }

    function storeAndMintAddLiquidityCheck(
        address ammRouter,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 packedRiskReport) {
        LiquidityV2GuardResult memory result = liquidityGuard.storeCheck(
            ammRouter, tokenA, tokenB, amountADesired, amountBDesired, msg.sender, LiquidityOperationType.ADD
        );
        packedRiskReport = riskPolicy.evaluate(offChainData, result, LiquidityOpType.ADD);
        riskReportNFT.mint(packedRiskReport);

        emit LiquidityCheckStored(
            msg.sender,
            ammRouter,
            LiquidityOperationType.ADD,
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            packedRiskReport
        );
    }

    function storeAndMintAddLiquidityETHCheck(
        address ammRouter,
        address token,
        uint256 amountTokenDesired,
        uint256 amountETHDesired,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 packedRiskReport) {
        LiquidityV2GuardResult memory result = liquidityGuard.storeCheck(
            ammRouter,
            token,
            address(0),
            amountTokenDesired,
            amountETHDesired,
            msg.sender,
            LiquidityOperationType.ADD_ETH
        );
        packedRiskReport = riskPolicy.evaluate(offChainData, result, LiquidityOpType.ADD_ETH);
        riskReportNFT.mint(packedRiskReport);

        emit LiquidityCheckStored(
            msg.sender,
            ammRouter,
            LiquidityOperationType.ADD_ETH,
            token,
            address(0),
            amountTokenDesired,
            amountETHDesired,
            packedRiskReport
        );
    }

    function storeAndMintRemoveLiquidityCheck(
        address ammRouter,
        address tokenA,
        address tokenB,
        uint256 lpAmountToBurn,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 packedRiskReport) {
        LiquidityV2GuardResult memory result = liquidityGuard.storeCheck(
            ammRouter, tokenA, tokenB, lpAmountToBurn, 0, msg.sender, LiquidityOperationType.REMOVE
        );
        packedRiskReport = riskPolicy.evaluate(offChainData, result, LiquidityOpType.REMOVE);
        riskReportNFT.mint(packedRiskReport);

        emit LiquidityCheckStored(
            msg.sender, ammRouter, LiquidityOperationType.REMOVE, tokenA, tokenB, lpAmountToBurn, 0, packedRiskReport
        );
    }

    function storeAndMintRemoveLiquidityETHCheck(
        address ammRouter,
        address token,
        uint256 lpAmountToBurn,
        bytes calldata offChainData
    ) external nonReentrant returns (uint256 packedRiskReport) {
        LiquidityV2GuardResult memory result = liquidityGuard.storeCheck(
            ammRouter, token, address(0), lpAmountToBurn, 0, msg.sender, LiquidityOperationType.REMOVE_ETH
        );
        packedRiskReport = riskPolicy.evaluate(offChainData, result, LiquidityOpType.REMOVE_ETH);
        riskReportNFT.mint(packedRiskReport);

        emit LiquidityCheckStored(
            msg.sender,
            ammRouter,
            LiquidityOperationType.REMOVE_ETH,
            token,
            address(0),
            lpAmountToBurn,
            0,
            packedRiskReport
        );
    }

    function guardedAddLiquidity(AddLiquidityParams calldata params)
        external
        nonReentrant
        returns (uint256 amountAUsed, uint256 amountBUsed, uint256 liquidity)
    {
        _validateRecipient(params.lpRecipient);
        _validateRecipient(params.refundRecipient);

        liquidityGuard.validateCheck(
            params.ammRouter,
            params.tokenA,
            params.tokenB,
            params.amountADesired,
            params.amountBDesired,
            msg.sender,
            LiquidityOperationType.ADD
        );

        IERC20(params.tokenA).safeTransferFrom(msg.sender, address(this), params.amountADesired);
        IERC20(params.tokenB).safeTransferFrom(msg.sender, address(this), params.amountBDesired);
        IERC20(params.tokenA).forceApprove(params.ammRouter, params.amountADesired);
        IERC20(params.tokenB).forceApprove(params.ammRouter, params.amountBDesired);

        (amountAUsed, amountBUsed, liquidity) = IUniswapV2Router(params.ammRouter)
            .addLiquidity(
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

        emit GuardedLiquidityExecuted(msg.sender, params.ammRouter, params.lpRecipient, LiquidityOperationType.ADD);
    }

    function guardedAddLiquidityETH(AddLiquidityETHParams calldata params)
        external
        payable
        nonReentrant
        returns (uint256 tokenUsed, uint256 ethUsed, uint256 liquidity)
    {
        _validateRecipient(params.lpRecipient);
        _validateRecipient(params.refundRecipient);

        if (msg.value == 0) {
            revert InvalidEthValue();
        }

        uint256 balanceBefore = address(this).balance - msg.value;

        liquidityGuard.validateCheck(
            params.ammRouter,
            params.token,
            address(0),
            params.amountTokenDesired,
            msg.value,
            msg.sender,
            LiquidityOperationType.ADD_ETH
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

        emit GuardedLiquidityExecuted(msg.sender, params.ammRouter, params.lpRecipient, LiquidityOperationType.ADD_ETH);
    }

    function guardedRemoveLiquidity(RemoveLiquidityParams calldata params)
        external
        nonReentrant
        returns (uint256 amountAOut, uint256 amountBOut, uint256 packedRiskReport)
    {
        _validateRecipient(params.tokenRecipient);

        liquidityGuard.validateCheck(
            params.ammRouter,
            params.tokenA,
            params.tokenB,
            params.lpAmountToBurn,
            0,
            msg.sender,
            LiquidityOperationType.REMOVE
        );

        address pair = _getPair(params.ammRouter, params.tokenA, params.tokenB);

        IERC20(pair).safeTransferFrom(msg.sender, address(this), params.lpAmountToBurn);
        IERC20(pair).forceApprove(params.ammRouter, params.lpAmountToBurn);

        (amountAOut, amountBOut) = IUniswapV2Router(params.ammRouter)
            .removeLiquidity(
                params.tokenA,
                params.tokenB,
                params.lpAmountToBurn,
                params.amountAMin,
                params.amountBMin,
                params.tokenRecipient,
                params.deadline
            );

        IERC20(pair).forceApprove(params.ammRouter, 0);

        emit GuardedLiquidityExecuted(
            msg.sender, params.ammRouter, params.tokenRecipient, LiquidityOperationType.REMOVE
        );
    }

    function guardedRemoveLiquidityETH(RemoveLiquidityETHParams calldata params)
        external
        nonReentrant
        returns (uint256 tokenOut, uint256 ethOut, uint256 packedRiskReport)
    {
        _validateRecipient(params.recipient);

        liquidityGuard.validateCheck(
            params.ammRouter,
            params.token,
            address(0),
            params.lpAmountToBurn,
            0,
            msg.sender,
            LiquidityOperationType.REMOVE_ETH
        );

        address weth = IUniswapV2Router(params.ammRouter).WETH();
        address pair = _getPair(params.ammRouter, params.token, weth);

        IERC20(pair).safeTransferFrom(msg.sender, address(this), params.lpAmountToBurn);
        IERC20(pair).forceApprove(params.ammRouter, params.lpAmountToBurn);

        (tokenOut, ethOut) = IUniswapV2Router(params.ammRouter)
            .removeLiquidityETH(
                params.token,
                params.lpAmountToBurn,
                params.amountTokenMin,
                params.amountETHMin,
                params.recipient,
                params.deadline
            );

        IERC20(pair).forceApprove(params.ammRouter, 0);

        emit GuardedLiquidityExecuted(msg.sender, params.ammRouter, params.recipient, LiquidityOperationType.REMOVE_ETH);
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

    function _validateRecipient(address recipient) internal pure {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }
    }

    function _getPair(address ammRouter, address tokenA, address tokenB) internal view returns (address pair) {
        pair = IUniswapV2Factory(IUniswapV2Router(ammRouter).factory()).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            revert PairNotFound();
        }
    }
}
