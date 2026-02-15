// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IUniswapV2Router,IUniswapV2Pair} from "../interfaces/ICamelot.sol";
import {IUniswapV3Factory,IUniswapV3Pool} from "../interfaces/ICamelot.sol";

contract SwapGuard is IGuard, UUPSUpgradeable, OwnableUpgradeable, AutomationCompatibleInterface {

    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct GuardResultV2 {
        bool DEEP_MULTHOP_SWAP;
        bool POOL_NOT_EXISTS;
        bool FACTORY_MISMATCH_WITH_POOL;
        bool ZERO_LIQUIDITY;
        bool LOW_LIQUIDITY;
        bool LOW_TOKEN_SUPPLY;
        bool V2_LOW_CUMULATIVE_PRICE;
        bool FLASHLOAN_ATTACK_POSSIBLE;
        bool PRICE_MANIPULATED;
    }

     struct PriceSnapshot {
        uint256 cumulative0;
        uint256 cumulative1;
        uint32 timestamp;
        uint256 lastBlock;
    }

    /*//////////////////////////////////////////////////////////////
                            CONFIG
    //////////////////////////////////////////////////////////////*/

    address public v2Router;
    address public v3Factory;
    address public v2Factory;

    uint256 public constant PRICE_DEVIATION_THRESHOLD = 500; // 5% BPS
    uint256 public constant MINIMUM_THRESHOLD_RESERVE = 1e6;
    uint256 public constant THRESHOLD_SUPPLY = 1e6;
    uint256 public constant THRESHOLD_CUMULATIVE_PRICE = 1;
    uint256 public constant MAX_DEVIATION_BPS = 200; // 2%

    /*//////////////////////////////////////////////////////////////
                        SNAPSHOT STORAGE (BLOCK BASED)
    //////////////////////////////////////////////////////////////*/

    mapping(address => PriceSnapshot) public snapshots;
    address[] public trackedPools;
    uint256 public snapshotBlockInterval = 1; // every blocks

    /*//////////////////////////////////////////////////////////////
                            INIT
    //////////////////////////////////////////////////////////////*/

    constructor() { _disableInitializers(); }

    function initialize(
        address _v2Router,
        address _v2Factory,
        address _v3Factory
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        v2Router = _v2Router;
        v2Factory = _v2Factory;
        v3Factory = _v3Factory;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL CHECK (V2)
    //////////////////////////////////////////////////////////////*/

    function swapCheckV2Pool(
        address[] calldata path,
        uint256 amountIn,
        uint256 amountOut
    ) external view returns (GuardResultV2 memory result) {

        bool isExactIn = amountIn != 0;
        result = checkV2pool(path, isExactIn);
    }

    /*//////////////////////////////////////////////////////////////
                        CORE V2 CHECK LOGIC
    //////////////////////////////////////////////////////////////*/

    function checkV2pool(
        address[] memory path,
        bool isExactIn
    ) public view returns (GuardResultV2 memory result) {

        uint256 pathLength = path.length;

        if (pathLength > 5) {
            result.DEEP_MULTHOP_SWAP = true;
        }

        for (uint256 i = 0; i < pathLength - 1; i++) {

            address pair = _getV2Pair(path[i], path[i+1]);

            if (pair == address(0)) {
                result.POOL_NOT_EXISTS = true;
                continue;
            }

            if (IUniswapV2Pair(pair).factory() != v2Factory) {
                result.FACTORY_MISMATCH_WITH_POOL = true;
            }

            (uint112 reserve0, uint112 reserve1, uint32 lastTimestamp) =
                IUniswapV2Pair(pair).getReserves();

            if (reserve0 == 0 || reserve1 == 0) {
                result.ZERO_LIQUIDITY = true;
                continue;
            }

            if (reserve0 <= MINIMUM_THRESHOLD_RESERVE ||
                reserve1 <= MINIMUM_THRESHOLD_RESERVE) {
                result.LOW_LIQUIDITY = true;
            }

            uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
            if (totalSupply <= THRESHOLD_SUPPLY) {
                result.LOW_TOKEN_SUPPLY = true;
            }

            uint256 cumPrice0 = IUniswapV2Pair(pair).price0CumulativeLast();
            if (cumPrice0 <= THRESHOLD_CUMULATIVE_PRICE) {
                result.V2_LOW_CUMULATIVE_PRICE = true;
            }

            if (_flashloanAttack(pair, reserve0, reserve1, lastTimestamp)) {
                result.FLASHLOAN_ATTACK_POSSIBLE = true;
            }

            if (_twapDeviation(pair, reserve0, reserve1)) {
                result.PRICE_MANIPULATED = true;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    FLASHLOAN / INTRA BLOCK CHECK
    //////////////////////////////////////////////////////////////*/

    function _flashloanAttack(
        address pair,
        uint112 reserve0,
        uint112 reserve1,
        uint32 lastTimestamp
    ) internal view returns (bool) {

        // Intra-block update detection
        if (lastTimestamp == uint32(block.timestamp)) {
            return true;
        }

        return false;
    }

    /*//////////////////////////////////////////////////////////////
                    TWAP DEVIATION CHECK
    //////////////////////////////////////////////////////////////*/

    function _twapDeviation(
        address pair,
        uint112 reserve0,
        uint112 reserve1
    ) internal view returns (bool) {

        PriceSnapshot memory snap = snapshots[pair];
        if (snap.blockNumber == 0) return false;

        uint256 fairPrice = getFairPrice(
            pair,
            
        );

        if (fairPrice == 0) return false;

        uint256 spotPrice = (uint256(reserve1) * 1e18) / reserve0;       // ToDo decimals and v2 fees must be taken into account ..

        return !_checkDeviation(spotPrice, fairPrice);
    }

    /*//////////////////////////////////////////////////////////////
                BLOCK-BASED CHAINLINK AUTOMATION
    //////////////////////////////////////////////////////////////*/

    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        for (uint256 i = 0; i < trackedPools.length; i++) {
            address pool = trackedPools[i];
            if (block.number - snapshots[pool].lastBlock >= snapshotBlockInterval) {
                return (true, abi.encode(pool));
            }
        }
        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external override {
        address pool = abi.decode(performData, (address));

        if (block.number - snapshots[pool].lastBlock >= snapshotBlockInterval) {
            _recordSnapshot(pool);
        }
    }

    /**
     * @dev RECORDS: Both price0 and price1 for a complete TWAP profile.
     */
    function _recordSnapshot(address pair) internal {
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        
        snapshots[pair] = PriceSnapshot({
            cumulative0: pairContract.price0CumulativeLast(),
            cumulative1: pairContract.price1CumulativeLast(),
            timestamp: uint32(block.timestamp),
            lastBlock: block.number
        });
    }

    /*//////////////////////////////////////////////////////////////
                    FAIR PRICE CALCULATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev CALCULATE: Derive the TWAP for the specific token being swapped.
     * @param tokenIn The token the user is selling.
     */
    function getFairPrice(address pair, address tokenIn) public view returns (uint224) {
        PriceSnapshot memory snap = snapshots[pair];
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        
        uint32 timeElapsed = uint32(block.timestamp) - snap.timestamp;
        if (timeElapsed == 0) return 0; // Should handle in logic

        // Identify which cumulative to use
        bool isToken0 = tokenIn == pairContract.token0();
        uint256 currentCumulative = isToken0 ? 
            pairContract.price0CumulativeLast() : 
            pairContract.price1CumulativeLast();
            
        uint256 snapCumulative = isToken0 ? snap.cumulative0 : snap.cumulative1;

        // TWAP Formula: (C2 - C1) / (T2 - T1)
        // Result is in UQ112x112
        return uint224((currentCumulative - snapCumulative) / timeElapsed);
    }
    /*//////////////////////////////////////////////////////////////
                    BPS DEVIATION CHECK
    //////////////////////////////////////////////////////////////*/

    function _checkDeviation(
        uint256 spot,
        uint256 twap
    ) internal pure returns (bool) {

        if (twap == 0) return true;

        uint256 diff = spot > twap ? spot - twap : twap - spot;

        return (diff * 10000) / twap < MAX_DEVIATION_BPS;
    }

    /*//////////////////////////////////////////////////////////////
                        PAIR LOOKUP
    //////////////////////////////////////////////////////////////*/

    function _getV2Pair(address tokenA, address tokenB)
        internal
        view
        returns (address pair)
    {
        (bool success, bytes memory data) =
            v2Factory.staticcall(
                abi.encodeWithSignature("getPair(address,address)", tokenA, tokenB)
            );

        if (!success || data.length < 32) return address(0);
        pair = abi.decode(data, (address));
    }



    /*//////////////////////////////////////////////////////////////
                        ADMIN
    //////////////////////////////////////////////////////////////*/

    function addTrackedPool(address pool) external onlyOwner {
        trackedPools.push(pool);
        _recordSnapshot(pool);
    }

    function setSnapshotBlockInterval(uint256 blocks_) external onlyOwner {
        snapshotBlockInterval = blocks_;
    }
}





























    /**
     * @dev Deep V3 Security: SquareRootPrice vs. TWAP vs. Path Integrity
     */
    function _checkV3Deep(bytes memory path, uint256 amountIn) internal view returns (GuardResult memory) {
        // Decode first hop
        (address tokenA, address tokenB, uint24 fee) = _decodeFirstV3Hop(path);
        address pool = IUniswapV3Factory(v3Factory).getPool(tokenA, tokenB, fee);
        if (pool == address(0)) return _block("V3_POOL_NOT_EXIST");

        IUniswapV3Pool v3Pool = IUniswapV3Pool(pool);
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = v3Pool.slot0();

        // 1. Check current Spot Price vs TWAP (10 min window)
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 600; secondsAgos[1] = 0;
        
        try v3Pool.observe(secondsAgos) returns (int56[] memory tickCumulatives, uint160[] memory) {
            int24 twapTick = int24((tickCumulatives[1] - tickCumulatives[0]) / 600);
            if (_abs(currentTick - twapTick) > 200) return _warn("V3_TWAP_DIVERGENCE");
        } catch { return _warn("V3_NO_ORACLE_DATA"); }

        // 2. Liquidity depth check
        uint128 liquidity = v3Pool.liquidity();
        if (liquidity < 1e10) return _warn("V3_DANGEROUSLY_LOW_LIQUIDITY");

        return _safe();
    }
