// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    PolicyKind,
    TokenGuardResult,
    VaultGuardResult,
    SwapV2GuardResult,
    LiquidityV2GuardResult
} from "../../src/types/OnChainTypes.sol";
import {VaultOpType, SwapOpType, LiquidityOpType} from "../../src/types/OffChainTypes.sol";
import {IUniswapV2Factory} from "../../src/preflightRouters/interfaces/IUniswapV2Interface.sol";
import {ERC4626DecodedRiskReport} from "../../src/riskpolicies/ERC4626RiskPolicy.sol";
import {SwapV2DecodedRiskReport} from "../../src/riskpolicies/SwapV2RiskPolicy.sol";
import {LiquidityV2DecodedRiskReport} from "../../src/riskpolicies/LiquidityV2RiskPolicy.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ERC20: insufficient allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "ERC20: burn exceeds balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "ERC20: zero recipient");
        require(balanceOf[from] >= amount, "ERC20: transfer exceeds balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract MockERC4626RouterVault is MockERC20 {
    address public immutable assetToken;
    uint256 public depositReturnShares;
    uint256 public mintReturnAssets;
    uint256 public redeemReturnAssets;
    uint256 public withdrawReturnShares;

    constructor(address asset_) MockERC20("Mock Vault Share", "MVS", 18) {
        assetToken = asset_;
    }

    function asset() external view returns (address) {
        return assetToken;
    }

    function setOperationReturns(
        uint256 depositShares_,
        uint256 mintAssets_,
        uint256 redeemAssets_,
        uint256 withdrawShares_
    ) external {
        depositReturnShares = depositShares_;
        mintReturnAssets = mintAssets_;
        redeemReturnAssets = redeemAssets_;
        withdrawReturnShares = withdrawShares_;
    }

    function deposit(uint256 assetAmount, address receiver) external returns (uint256 sharesOut) {
        sharesOut = depositReturnShares;
        if (assetAmount > 0) {
            MockERC20(assetToken).transferFrom(msg.sender, address(this), assetAmount);
        }
        if (sharesOut > 0) {
            balanceOf[receiver] += sharesOut;
            totalSupply += sharesOut;
        }
    }

    function mint(uint256 shareAmount, address receiver) external returns (uint256 assetsOut) {
        assetsOut = mintReturnAssets;
        if (assetsOut > 0) {
            MockERC20(assetToken).transferFrom(msg.sender, address(this), assetsOut);
        }
        if (shareAmount > 0) {
            balanceOf[receiver] += shareAmount;
            totalSupply += shareAmount;
        }
    }

    function redeem(uint256 shareAmount, address receiver, address owner) external returns (uint256 assetsOut) {
        assetsOut = redeemReturnAssets;
        _spendShares(owner, shareAmount, msg.sender);
        if (assetsOut > 0) {
            MockERC20(assetToken).transfer(receiver, assetsOut);
        }
    }

    function withdraw(uint256 assetAmount, address receiver, address owner) external returns (uint256 sharesOut) {
        sharesOut = withdrawReturnShares;
        _spendShares(owner, sharesOut, msg.sender);
        if (assetAmount > 0) {
            MockERC20(assetToken).transfer(receiver, assetAmount);
        }
    }

    function _spendShares(address owner, uint256 shares, address spender) internal {
        if (spender != owner) {
            uint256 allowed = allowance[owner][spender];
            if (allowed != type(uint256).max) {
                require(allowed >= shares, "ERC20: insufficient allowance");
                allowance[owner][spender] = allowed - shares;
            }
        }
        require(balanceOf[owner] >= shares, "ERC20: transfer exceeds balance");
        balanceOf[owner] -= shares;
        totalSupply -= shares;
    }
}

contract MockERC4626Guard {
    VaultGuardResult internal _configuredResult;
    uint256 public configuredPreviewShares;
    uint256 public configuredPreviewAssets;
    uint256 public storedBlockNumber;
    bool public validateShouldRevert;

    address public lastVault;
    address public lastUser;
    uint256 public lastAmount;
    VaultOpType public lastOperation;

    function setConfiguredResult(VaultGuardResult calldata result_, uint256 previewShares_, uint256 previewAssets_)
        external
    {
        _configuredResult = result_;
        configuredPreviewShares = previewShares_;
        configuredPreviewAssets = previewAssets_;
        storedBlockNumber = block.number;
    }

    function setValidateShouldRevert(bool shouldRevert) external {
        validateShouldRevert = shouldRevert;
    }

    function checkVault(address vault, uint256 amount, VaultOpType opType)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        lastVault = vault;
        lastAmount = amount;
        lastOperation = opType;
        return (_configuredResult, configuredPreviewShares, configuredPreviewAssets);
    }

    function storeCheck(address vault, address user, uint256 amount, VaultOpType opType)
        external
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets)
    {
        lastVault = vault;
        lastUser = user;
        lastAmount = amount;
        lastOperation = opType;
        storedBlockNumber = block.number;
        return (_configuredResult, configuredPreviewShares, configuredPreviewAssets);
    }

    function validate(address vault, address user, uint256 amount, VaultOpType opType) external view {
        vault;
        user;
        amount;
        opType;
        if (validateShouldRevert) {
            revert("VALIDATE_REVERTED");
        }
    }

    function getLastCheck(address vault, address user)
        external
        view
        returns (VaultGuardResult memory result, uint256 previewShares, uint256 previewAssets, uint256 blockNumber)
    {
        vault;
        user;
        return (_configuredResult, configuredPreviewShares, configuredPreviewAssets, storedBlockNumber);
    }
}

contract MockERC4626RiskPolicy {
    uint256 public evaluateReturn = 111;
    uint8 public decodeOperation;
    uint8 public decodeScore = 77;

    function setEvaluateReturn(uint256 newValue) external {
        evaluateReturn = newValue;
    }

    function setDecodeFields(uint8 operation_, uint8 score_) external {
        decodeOperation = operation_;
        decodeScore = score_;
    }

    function evaluate(bytes calldata offChainData, VaultGuardResult memory onChainData, VaultOpType operation)
        external
        view
        returns (uint256 packedReport)
    {
        offChainData;
        onChainData;
        operation;
        return evaluateReturn;
    }

    function decode(uint256) external view returns (ERC4626DecodedRiskReport memory report) {
        report.core.kind = PolicyKind.ERC4626;
        report.core.operation = decodeOperation;
        report.core.compositeScore = decodeScore;
        report.operation = VaultOpType(decodeOperation);
    }
}

contract MockRiskReportNFT {
    uint256 public mintCount;
    uint256 public lastPackedRiskReport;
    address public lastRecipient;

    function mint(uint256 packedRiskReport, address recipient) external returns (uint256 tokenId) {
        mintCount += 1;
        lastPackedRiskReport = packedRiskReport;
        lastRecipient = recipient;
        tokenId = mintCount;
    }
}

contract MockSwapV2Guard {
    SwapV2GuardResult internal _configuredResult;
    uint256[] internal _configuredAmounts;
    bool public validateShouldRevert;

    address public lastRouter;
    uint256 public lastAmount;
    bool public lastIsExactTokenIn;
    address public lastUser;
    uint256 public lastPathLength;

    function setQuote(uint256[] calldata amounts_) external {
        delete _configuredAmounts;
        for (uint256 i = 0; i < amounts_.length; ++i) {
            _configuredAmounts.push(amounts_[i]);
        }
    }

    function setValidateShouldRevert(bool shouldRevert) external {
        validateShouldRevert = shouldRevert;
    }

    function swapCheckV2(address router, address[] calldata path, uint256 amount, bool isExactTokenIn)
        external
        returns (SwapV2GuardResult memory result, uint256[] memory amountsOut)
    {
        lastRouter = router;
        lastAmount = amount;
        lastIsExactTokenIn = isExactTokenIn;
        lastPathLength = path.length;
        return (_configuredResult, _configuredAmounts);
    }

    function storeSwapCheck(address router, address[] calldata path, uint256 amount, bool isExactTokenIn, address user)
        external
        returns (SwapV2GuardResult memory)
    {
        lastRouter = router;
        lastAmount = amount;
        lastIsExactTokenIn = isExactTokenIn;
        lastUser = user;
        lastPathLength = path.length;
        return _configuredResult;
    }

    function validateSwapCheck(
        address router,
        address[] calldata path,
        uint256 amount,
        bool isExactTokenIn,
        address user
    ) external view {
        router;
        path;
        amount;
        isExactTokenIn;
        user;
        if (validateShouldRevert) {
            revert("VALIDATE_REVERTED");
        }
    }
}

contract MockSwapV2RiskPolicy {
    uint256 public evaluateReturn = 222;
    uint8 public decodeOperation;
    uint8 public decodeScore = 66;

    function setEvaluateReturn(uint256 newValue) external {
        evaluateReturn = newValue;
    }

    function setDecodeFields(uint8 operation_, uint8 score_) external {
        decodeOperation = operation_;
        decodeScore = score_;
    }

    function evaluate(bytes calldata offChainData, SwapV2GuardResult memory onChainData, SwapOpType operation)
        external
        view
        returns (uint256 packedReport)
    {
        onChainData;
        offChainData;
        operation;
        return evaluateReturn;
    }

    function decode(uint256) external view returns (SwapV2DecodedRiskReport memory report) {
        report.core.kind = PolicyKind.SWAP_V2;
        report.core.operation = decodeOperation;
        report.core.compositeScore = decodeScore;
        report.operation = SwapOpType(decodeOperation);
    }
}

contract MockLiquidityV2Guard {
    LiquidityV2GuardResult internal _configuredResult;
    bool public validateShouldRevert;

    address public lastRouter;
    address public lastTokenA;
    address public lastTokenB;
    uint256 public lastAmountA;
    uint256 public lastAmountB;
    address public lastUser;
    LiquidityOpType public lastOperationType;

    function setValidateShouldRevert(bool shouldRevert) external {
        validateShouldRevert = shouldRevert;
    }

    function checkLiquidity(
        address user,
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        LiquidityOpType operationType
    ) external returns (LiquidityV2GuardResult memory result) {
        lastUser = user;
        lastRouter = router;
        lastTokenA = tokenA;
        lastTokenB = tokenB;
        lastAmountA = amountADesired;
        lastAmountB = amountBDesired;
        lastOperationType = operationType;
        return _configuredResult;
    }

    function storeCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOpType operationType
    ) external returns (LiquidityV2GuardResult memory result) {
        lastUser = user;
        lastRouter = router;
        lastTokenA = tokenA;
        lastTokenB = tokenB;
        lastAmountA = amountADesired;
        lastAmountB = amountBDesired;
        lastOperationType = operationType;
        return _configuredResult;
    }

    function validateCheck(
        address router,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address user,
        LiquidityOpType operationType
    ) external view {
        router;
        tokenA;
        tokenB;
        amountADesired;
        amountBDesired;
        user;
        operationType;
        if (validateShouldRevert) {
            revert("VALIDATE_REVERTED");
        }
    }
}

contract MockLiquidityV2RiskPolicy {
    uint256 public evaluateReturn = 333;
    uint8 public decodeOperation;
    uint8 public decodeScore = 55;

    function setEvaluateReturn(uint256 newValue) external {
        evaluateReturn = newValue;
    }

    function setDecodeFields(uint8 operation_, uint8 score_) external {
        decodeOperation = operation_;
        decodeScore = score_;
    }

    function evaluate(bytes calldata offChainData, LiquidityV2GuardResult memory onChainData, LiquidityOpType operation)
        external
        view
        returns (uint256 packedReport)
    {
        onChainData;
        offChainData;
        operation;
        return evaluateReturn;
    }

    function decode(uint256) external view returns (LiquidityV2DecodedRiskReport memory report) {
        report.core.kind = PolicyKind.LIQUIDITY_V2;
        report.core.operation = decodeOperation;
        report.core.compositeScore = decodeScore;
        report.operation = LiquidityOpType(decodeOperation);
    }
}

contract MockV2PairToken is MockERC20 {
    address public token0;
    address public token1;
    address public factory;
    uint112 internal _reserve0;
    uint112 internal _reserve1;
    uint32 internal _blockTimestampLast;
    uint256 internal _price0CumulativeLast;
    uint256 internal _price1CumulativeLast;
    uint256 internal _kLast;

    constructor(address token0_, address token1_, address factory_) MockERC20("Mock LP", "MLP", 18) {
        token0 = token0_;
        token1 = token1_;
        factory = factory_;
    }

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function price0CumulativeLast() external view returns (uint256) {
        return _price0CumulativeLast;
    }

    function price1CumulativeLast() external view returns (uint256) {
        return _price1CumulativeLast;
    }

    function kLast() external view returns (uint256) {
        return _kLast;
    }

    function setReserves(uint112 reserve0_, uint112 reserve1_, uint32 blockTimestampLast_) external {
        _reserve0 = reserve0_;
        _reserve1 = reserve1_;
        _blockTimestampLast = blockTimestampLast_;
    }
}

contract MockExecutableV2Router {
    address public factory;
    address public WETH;

    uint256[] internal _swapResult;
    uint256 public addAmountAUsed;
    uint256 public addAmountBUsed;
    uint256 public addLiquidityMinted;
    uint256 public addLiquidityTokenUsed;
    uint256 public addLiquidityEthUsed;
    uint256 public addLiquidityEthMinted;
    uint256 public removeAmountAOut;
    uint256 public removeAmountBOut;
    uint256 public removeAmountTokenOut;
    uint256 public removeAmountEthOut;
    uint256 public ethRefund;

    constructor(address factory_, address weth_) {
        factory = factory_;
        WETH = weth_;
    }

    receive() external payable {}

    function setSwapResult(uint256[] calldata values, uint256 ethRefund_) external {
        delete _swapResult;
        for (uint256 i = 0; i < values.length; ++i) {
            _swapResult.push(values[i]);
        }
        ethRefund = ethRefund_;
    }

    function setAddLiquidityResult(uint256 amountAUsed_, uint256 amountBUsed_, uint256 liquidity_) external {
        addAmountAUsed = amountAUsed_;
        addAmountBUsed = amountBUsed_;
        addLiquidityMinted = liquidity_;
    }

    function setAddLiquidityEthResult(uint256 tokenUsed_, uint256 ethUsed_, uint256 liquidity_, uint256 ethRefund_)
        external
    {
        addLiquidityTokenUsed = tokenUsed_;
        addLiquidityEthUsed = ethUsed_;
        addLiquidityEthMinted = liquidity_;
        ethRefund = ethRefund_;
    }

    function setRemoveLiquidityResult(uint256 amountAOut_, uint256 amountBOut_) external {
        removeAmountAOut = amountAOut_;
        removeAmountBOut = amountBOut_;
    }

    function setRemoveLiquidityEthResult(uint256 amountTokenOut_, uint256 amountEthOut_) external {
        removeAmountTokenOut = amountTokenOut_;
        removeAmountEthOut = amountEthOut_;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        amountOutMin;
        deadline;
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        MockERC20(path[path.length - 1]).mint(to, _swapResult[_swapResult.length - 1]);
        return _swapResult;
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        amountOut;
        amountInMax;
        deadline;
        MockERC20(path[0]).transferFrom(msg.sender, address(this), _swapResult[0]);
        MockERC20(path[path.length - 1]).mint(to, _swapResult[_swapResult.length - 1]);
        return _swapResult;
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts)
    {
        amountOutMin;
        deadline;
        MockERC20(path[path.length - 1]).mint(to, _swapResult[_swapResult.length - 1]);
        return _swapResult;
    }

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts)
    {
        amountOut;
        deadline;
        MockERC20(path[path.length - 1]).mint(to, _swapResult[_swapResult.length - 1]);
        if (ethRefund > 0) {
            (bool success,) = payable(msg.sender).call{value: ethRefund}("");
            require(success, "ETH_REFUND_FAILED");
        }
        return _swapResult;
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        amountOutMin;
        deadline;
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        (bool success,) = payable(to).call{value: _swapResult[_swapResult.length - 1]}("");
        require(success, "ETH_SEND_FAILED");
        return _swapResult;
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        amountOut;
        amountInMax;
        deadline;
        MockERC20(path[0]).transferFrom(msg.sender, address(this), _swapResult[0]);
        (bool success,) = payable(to).call{value: _swapResult[_swapResult.length - 1]}("");
        require(success, "ETH_SEND_FAILED");
        return _swapResult;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        amountADesired;
        amountBDesired;
        amountAMin;
        amountBMin;
        deadline;
        MockERC20(tokenA).transferFrom(msg.sender, address(this), addAmountAUsed);
        MockERC20(tokenB).transferFrom(msg.sender, address(this), addAmountBUsed);
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair != address(0)) {
            MockERC20(pair).mint(to, addLiquidityMinted);
        }
        return (addAmountAUsed, addAmountBUsed, addLiquidityMinted);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        amountTokenDesired;
        amountTokenMin;
        amountETHMin;
        deadline;
        MockERC20(token).transferFrom(msg.sender, address(this), addLiquidityTokenUsed);
        address pair = IUniswapV2Factory(factory).getPair(token, WETH);
        if (pair != address(0)) {
            MockERC20(pair).mint(to, addLiquidityEthMinted);
        }
        if (ethRefund > 0) {
            (bool success,) = payable(msg.sender).call{value: ethRefund}("");
            require(success, "ETH_REFUND_FAILED");
        }
        return (addLiquidityTokenUsed, addLiquidityEthUsed, addLiquidityEthMinted);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        amountAMin;
        amountBMin;
        deadline;
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        MockERC20(pair).transferFrom(msg.sender, address(this), liquidity);
        MockERC20(tokenA).mint(to, removeAmountAOut);
        MockERC20(tokenB).mint(to, removeAmountBOut);
        return (removeAmountAOut, removeAmountBOut);
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH) {
        amountTokenMin;
        amountETHMin;
        deadline;
        address pair = IUniswapV2Factory(factory).getPair(token, WETH);
        MockERC20(pair).transferFrom(msg.sender, address(this), liquidity);
        MockERC20(token).mint(to, removeAmountTokenOut);
        (bool success,) = payable(to).call{value: removeAmountEthOut}("");
        require(success, "ETH_SEND_FAILED");
        return (removeAmountTokenOut, removeAmountEthOut);
    }
}
