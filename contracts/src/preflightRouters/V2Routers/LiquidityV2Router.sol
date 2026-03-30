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

/**
 * @author Sourav-IITBPL
 * @notice Router for guarded Uniswap V2-style liquidity operations with risk report minting.
 */
contract LiquidityV2Router is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Raised when a required contract or recipient address is zero.
    error ZeroAddress();
    /// @notice Raised when a liquidity recipient or refund recipient is invalid.
    error InvalidRecipient();
    /// @notice Raised when an ETH-based liquidity flow is called without the required native value.
    error InvalidEthValue();
    /// @notice Raised when the router factory does not expose a pair for the requested tokens.
    error PairNotFound();

    /// @notice Parameters for a guarded ERC-20/ERC-20 add-liquidity flow.
    struct AddLiquidityParams {
        /// @notice AMM router that executes the liquidity addition.
        address ammRouter;
        /// @notice First token of the pair.
        address tokenA;
        /// @notice Second token of the pair.
        address tokenB;
        /// @notice Desired amount of token A to supply.
        uint256 amountADesired;
        /// @notice Desired amount of token B to supply.
        uint256 amountBDesired;
        /// @notice Minimum acceptable amount of token A that must be consumed.
        uint256 amountAMin;
        /// @notice Minimum acceptable amount of token B that must be consumed.
        uint256 amountBMin;
        /// @notice Recipient of the minted LP tokens.
        address lpRecipient;
        /// @notice Recipient of any unused input token refunds.
        address refundRecipient;
        /// @notice Deadline passed through to the underlying router call.
        uint256 deadline;
    }

    /// @notice Parameters for a guarded ERC-20/ETH add-liquidity flow.
    struct AddLiquidityETHParams {
        /// @notice AMM router that executes the liquidity addition.
        address ammRouter;
        /// @notice ERC-20 token paired against ETH.
        address token;
        /// @notice Desired amount of the ERC-20 token to supply.
        uint256 amountTokenDesired;
        /// @notice Minimum acceptable token amount consumed by the router.
        uint256 amountTokenMin;
        /// @notice Minimum acceptable ETH amount consumed by the router.
        uint256 amountETHMin;
        /// @notice Recipient of the minted LP tokens.
        address lpRecipient;
        /// @notice Recipient of any leftover token or ETH refunds.
        address refundRecipient;
        /// @notice Deadline passed through to the underlying router call.
        uint256 deadline;
    }

    /// @notice Parameters for a guarded ERC-20/ERC-20 remove-liquidity flow.
    struct RemoveLiquidityParams {
        /// @notice AMM router that executes the liquidity removal.
        address ammRouter;
        /// @notice First token of the pair.
        address tokenA;
        /// @notice Second token of the pair.
        address tokenB;
        /// @notice LP token amount to burn.
        uint256 lpAmountToBurn;
        /// @notice Minimum acceptable amount of token A to receive.
        uint256 amountAMin;
        /// @notice Minimum acceptable amount of token B to receive.
        uint256 amountBMin;
        /// @notice Recipient of the withdrawn underlying tokens.
        address tokenRecipient;
        /// @notice Deadline passed through to the underlying router call.
        uint256 deadline;
    }

    /// @notice Parameters for a guarded ERC-20/ETH remove-liquidity flow.
    struct RemoveLiquidityETHParams {
        /// @notice AMM router that executes the liquidity removal.
        address ammRouter;
        /// @notice ERC-20 token paired against ETH.
        address token;
        /// @notice LP token amount to burn.
        uint256 lpAmountToBurn;
        /// @notice Minimum acceptable token amount to receive.
        uint256 amountTokenMin;
        /// @notice Minimum acceptable ETH amount to receive.
        uint256 amountETHMin;
        /// @notice Recipient of the withdrawn token and ETH proceeds.
        address recipient;
        /// @notice Deadline passed through to the underlying router call.
        uint256 deadline;
    }

    ILiquidityV2Guard public liquidityGuard;
    ILiquidityV2RiskPolicy public riskPolicy;
    IRiskReportNFT public riskReportNFT;

    /// @notice Emitted when the router updates its liquidity guard dependency.
    event LiquidityGuardUpdated(address indexed newGuard);
    /// @notice Emitted when the router updates its liquidity risk policy dependency.
    event RiskPolicyUpdated(address indexed newRiskPolicy);
    /// @notice Emitted when the router updates the NFT contract used for report minting.
    event RiskReportNFTUpdated(address indexed newRiskReportNFT);
    /// @notice Emitted when a liquidity check is stored and evaluated into a packed report.
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
    /// @notice Emitted after a guarded liquidity operation executes successfully.
    event GuardedLiquidityExecuted(
        address indexed user, address indexed ammRouter, address indexed recipient, LiquidityOperationType operation
    );

    /**
     * @notice Deploys the router with the liquidity guard, risk policy, and report NFT.
     * @param liquidityGuard_ Address of the liquidity guard contract.
     * @param riskPolicy_ Address of the liquidity risk policy contract.
     * @param riskReportNFT_ Address of the risk report NFT contract.
     */
    constructor(address liquidityGuard_, address riskPolicy_, address riskReportNFT_) {
        if (liquidityGuard_ == address(0) || riskPolicy_ == address(0) || riskReportNFT_ == address(0)) {
            revert ZeroAddress();
        }

        liquidityGuard = ILiquidityV2Guard(liquidityGuard_);
        riskPolicy = ILiquidityV2RiskPolicy(riskPolicy_);
        riskReportNFT = IRiskReportNFT(riskReportNFT_);
    }

    /// @notice Accepts ETH refunds from router calls.
    receive() external payable {}

    /**
     * @notice Updates the liquidity guard used by the router.
     * @param newGuard Address of the new liquidity guard.
     */
    function setLiquidityGuard(address newGuard) external onlyOwner {
        if (newGuard == address(0)) {
            revert ZeroAddress();
        }
        liquidityGuard = ILiquidityV2Guard(newGuard);
        emit LiquidityGuardUpdated(newGuard);
    }

    /**
     * @notice Updates the risk policy used to evaluate stored liquidity checks.
     * @param newRiskPolicy Address of the new liquidity risk policy contract.
     */
    function setRiskPolicy(address newRiskPolicy) external onlyOwner {
        if (newRiskPolicy == address(0)) {
            revert ZeroAddress();
        }
        riskPolicy = ILiquidityV2RiskPolicy(newRiskPolicy);
        emit RiskPolicyUpdated(newRiskPolicy);
    }

    /**
     * @notice Updates the NFT contract used to mint liquidity risk reports.
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
     * @notice Previews a guarded add-liquidity check for an ERC-20/ERC-20 pair.
     * @param ammRouter Address of the AMM router.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B.
     * @param amountADesired Desired amount of token A.
     * @param amountBDesired Desired amount of token B.
     * @return result Guard result for the requested add-liquidity flow.
     */
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

    /**
     * @notice Previews a guarded add-liquidity check for a token/ETH pair.
     * @param ammRouter Address of the AMM router.
     * @param token Address of the ERC-20 token.
     * @param amountTokenDesired Desired token amount.
     * @param amountETHDesired Desired ETH amount.
     * @return result Guard result for the requested add-liquidity flow.
     */
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

    /**
     * @notice Previews a guarded remove-liquidity check for an ERC-20/ERC-20 pair.
     * @param ammRouter Address of the AMM router.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B.
     * @param lpAmountToBurn LP token amount to burn.
     * @return result Guard result for the requested remove-liquidity flow.
     */
    function previewGuardedRemoveLiquidity(address ammRouter, address tokenA, address tokenB, uint256 lpAmountToBurn)
        external
        returns (LiquidityV2GuardResult memory result)
    {
        result = liquidityGuard.checkLiquidity(
            msg.sender, ammRouter, tokenA, tokenB, lpAmountToBurn, 0, LiquidityOperationType.REMOVE
        );
    }

    /**
     * @notice Previews a guarded remove-liquidity check for a token/ETH pair.
     * @param ammRouter Address of the AMM router.
     * @param token Address of the ERC-20 token.
     * @param lpAmountToBurn LP token amount to burn.
     * @return result Guard result for the requested remove-liquidity flow.
     */
    function previewGuardedRemoveLiquidityETH(address ammRouter, address token, uint256 lpAmountToBurn)
        external
        returns (LiquidityV2GuardResult memory result)
    {
        result = liquidityGuard.checkLiquidity(
            msg.sender, ammRouter, token, address(0), lpAmountToBurn, 0, LiquidityOperationType.REMOVE_ETH
        );
    }

    /**
     * @notice Stores an add-liquidity check, evaluates risk, and mints the report NFT.
     * @param ammRouter Address of the AMM router.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B.
     * @param amountADesired Desired amount of token A.
     * @param amountBDesired Desired amount of token B.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return packedRiskReport Packed risk report for the operation.
     */
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
        riskReportNFT.mint(packedRiskReport, msg.sender);

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

    /**
     * @notice Stores an add-liquidity-ETH check, evaluates risk, and mints the report NFT.
     * @param ammRouter Address of the AMM router.
     * @param token Address of the ERC-20 token.
     * @param amountTokenDesired Desired token amount.
     * @param amountETHDesired Desired ETH amount.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return packedRiskReport Packed risk report for the operation.
     */
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
        riskReportNFT.mint(packedRiskReport, msg.sender);

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

    /**
     * @notice Stores a remove-liquidity check, evaluates risk, and mints the report NFT.
     * @param ammRouter Address of the AMM router.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B.
     * @param lpAmountToBurn LP token amount to burn.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return packedRiskReport Packed risk report for the operation.
     */
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
        riskReportNFT.mint(packedRiskReport,msg.sender);

        emit LiquidityCheckStored(
            msg.sender, ammRouter, LiquidityOperationType.REMOVE, tokenA, tokenB, lpAmountToBurn, 0, packedRiskReport
        );
    }

    /**
     * @notice Stores a remove-liquidity-ETH check, evaluates risk, and mints the report NFT.
     * @param ammRouter Address of the AMM router.
     * @param token Address of the ERC-20 token.
     * @param lpAmountToBurn LP token amount to burn.
     * @param offChainData ABI-encoded off-chain simulation data.
     * @return packedRiskReport Packed risk report for the operation.
     */
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
        riskReportNFT.mint(packedRiskReport,msg.sender);

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

    /**
     * @notice Executes a guarded add-liquidity operation for an ERC-20/ERC-20 pair.
     * @param params Encoded add-liquidity parameters.
     * @return amountAUsed Amount of token A consumed by the AMM.
     * @return amountBUsed Amount of token B consumed by the AMM.
     * @return liquidity LP tokens minted by the AMM.
     */
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

    /**
     * @notice Executes a guarded add-liquidity operation for a token/ETH pair.
     * @param params Encoded add-liquidity-ETH parameters.
     * @return tokenUsed Amount of tokens consumed by the AMM.
     * @return ethUsed Amount of ETH consumed by the AMM.
     * @return liquidity LP tokens minted by the AMM.
     */
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

    /**
     * @notice Executes a guarded remove-liquidity operation for an ERC-20/ERC-20 pair.
     * @param params Encoded remove-liquidity parameters.
     * @return amountAOut Amount of token A received.
     * @return amountBOut Amount of token B received.
     * @return packedRiskReport Packed risk report placeholder returned by the function signature.
     */
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

    /**
     * @notice Executes a guarded remove-liquidity operation for a token/ETH pair.
     * @param params Encoded remove-liquidity-ETH parameters.
     * @return tokenOut Amount of tokens received.
     * @return ethOut Amount of ETH received.
     * @return packedRiskReport Packed risk report placeholder returned by the function signature.
     */
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

    /**
     * @notice Decodes a packed liquidity risk report.
     * @param packedRiskReport Packed risk report value.
     * @return report Decoded liquidity risk report.
     */
    function decodePackedRisk(uint256 packedRiskReport)
        external
        view
        returns (LiquidityV2DecodedRiskReport memory report)
    {
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

    /// @dev Reverts when a recipient-like address is zero.
    function _validateRecipient(address recipient) internal pure {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }
    }

    /// @dev Resolves the pair address for the provided tokens and reverts when it does not exist.
    /// @param ammRouter Router whose factory is queried.
    /// @param tokenA First token of the pair.
    /// @param tokenB Second token of the pair.
    /// @return pair Pair address created by the router's factory.
    function _getPair(address ammRouter, address tokenA, address tokenB) internal view returns (address pair) {
        pair = IUniswapV2Factory(IUniswapV2Router(ammRouter).factory()).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            revert PairNotFound();
        }
    }
}
