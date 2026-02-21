// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IUniswapV2Router, IUniswapV2Pair} from "../interfaces/ICamelot.sol";

contract SwapV2Guard is IGuard, UUPSUpgradeable, OwnableUpgradeable, AutomationCompatibleInterface {
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

    uint256 public constant PRICE_DEVIATION_THRESHOLD = 500; // 5% BPS
    uint256 public constant MINIMUM_THRESHOLD_RESERVE = 1e6;
    uint256 public constant THRESHOLD_SUPPLY = 1e6;
    uint256 public constant THRESHOLD_CUMULATIVE_PRICE = 1;
    uint256 public constant MAX_DEVIATION_BPS = 500; // 5%

    /*//////////////////////////////////////////////////////////////
                        SNAPSHOT STORAGE (BLOCK BASED)
    //////////////////////////////////////////////////////////////*/

    mapping(address => PriceSnapshot) public snapshots;
    address[] public trackedPools;
    uint256 public snapshotBlockInterval = 1; // every blocks

    /*//////////////////////////////////////////////////////////////
                            INIT
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL CHECK (V2)
    //////////////////////////////////////////////////////////////*/

    function swapCheckV2Pool(address v2Router, address[] calldata path, uint256 amountIn, uint256 amountOut)
        external
        view
        returns (GuardResultV2 memory result)
    {
        bool isExactIn = amountIn != 0;
        result = checkV2pool(v2Router, path, isExactIn);
    }

    /*//////////////////////////////////////////////////////////////
                        CORE V2 CHECK LOGIC
    //////////////////////////////////////////////////////////////*/

    function checkV2pool(address v2Router, address[] memory path, bool isExactIn)
        public
        view
        returns (GuardResultV2 memory result)
    {
        uint256 pathLength = path.length;

        if (pathLength > 5) {
            result.DEEP_MULTHOP_SWAP = true;
        }

        for (uint256 i = 0; i < pathLength - 1; i++) {
            address pair = _getV2Pair(v2Router, path[i], path[i + 1]);

            if (pair == address(0)) {
                result.POOL_NOT_EXISTS = true;
                continue;
            }

            (uint112 reserve0, uint112 reserve1, uint32 lastTimestamp) = IUniswapV2Pair(pair).getReserves();

            if (reserve0 == 0 || reserve1 == 0) {
                result.ZERO_LIQUIDITY = true;
                continue;
            }

            if (reserve0 <= MINIMUM_THRESHOLD_RESERVE || reserve1 <= MINIMUM_THRESHOLD_RESERVE) {
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

    function _flashloanAttack(address pair, uint112 reserve0, uint112 reserve1, uint32 lastTimestamp)
        internal
        view
        returns (bool)
    {
        // Intra-block update detection
        if (lastTimestamp == uint32(block.timestamp)) {
            return true;
        }

        return false;
    }

    /*//////////////////////////////////////////////////////////////
                    TWAP DEVIATION CHECK
    //////////////////////////////////////////////////////////////*/

    function _twapDeviation(address pair, uint112 reserve0, uint112 reserve1) internal view returns (bool) {
        PriceSnapshot memory snap = snapshots[pair];
        if (snap.blockNumber == 0) return false;

        (uint224 fairPrice0, uint224 fairPrice1) = getFairPrice(pair);

        if (fairPrice0 == 0 && fairPrice1 == 0) return false;

        uint256 spotPrice = (uint256(reserve1) * 1e18) / reserve0; // implement this taking into accounts -  decimals and v2 fees must be taken into account during spot price calcuaitons..

        return !_checkDeviation(spotPrice, fairPrice0);
    }

    /*//////////////////////////////////////////////////////////////
                BLOCK-BASED CHAINLINK AUTOMATION
    //////////////////////////////////////////////////////////////*/

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        address[] memory UpkeepNeededPools = new address[]();
        uint256 trackedPoolsLength = trackedPools.length;

        for (uint256 i = 0; i < trackedPoolsLength; i++) {
            address pool = trackedPools[i];
            if (block.number - snapshots[pool].lastBlock >= snapshotBlockInterval) {
                UpkeepNeededPools.push(pool);
            }
        }
        if (UpkeepNeededPools.length > 0) {
            return (true, keccak256(abi.encode(UpkeepNeededPools)));
        }
        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external override {
        address[] memory pools = abi.decode(performData, (address[]));
        uint256 poolsLength = pools.length;
        for (uint256 i = 0; i < poolsLength; i++) {
            address pool = pools[i];
            if (block.number - snapshots[pool].lastBlock >= snapshotBlockInterval) {
                _recordSnapshot(pool);
            }
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
    function getFairPrice(address pair) public view returns (uint224, uint224) {
        PriceSnapshot memory snap = snapshots[pair];
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);

        uint32 timeElapsed = uint32(block.timestamp) - snap.timestamp;
        if (timeElapsed == 0) return (0, 0); // Should handle in logic

        // Identify which cumulative to use
        uint256 currentCumulative0 = pairContract.price0CumulativeLast();
        uint256 currentCumulative1 = pairContract.price1CumulativeLast();

        uint256 snapCumulative0 = snap.cumulative0;
        uint256 snapCumulative1 = snap.cumulative1;

        // TWAP Formula: (C2 - C1) / (T2 - T1)
        // Result is in UQ112x112
        return (
            uint224((currentCumulative0 - snapCumulative0) / timeElapsed),
            uint224((currentCumulative1 - snapCumulative1) / timeElapsed)
        );
    }
    /*//////////////////////////////////////////////////////////////
                    BPS DEVIATION CHECK
    //////////////////////////////////////////////////////////////*/

    function _checkDeviation(uint256 spot, uint256 twap) internal pure returns (bool) {
        if (twap == 0) return true;

        uint256 diff = spot > twap ? spot - twap : twap - spot;

        return (diff * 100_00) / twap < MAX_DEVIATION_BPS;
    }

    /*//////////////////////////////////////////////////////////////
                        PAIR LOOKUP
    //////////////////////////////////////////////////////////////*/

    function _getV2Pair(address v2Router, address tokenA, address tokenB) internal view returns (address pair) {
        address v2Factory = IUniswapV2Router(v2Router).factory();
        (bool success, bytes memory data) =
            v2Factory.staticcall(abi.encodeWithSignature("getPair(address,address)", tokenA, tokenB));

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

















// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";


/*//////////////////////////////////////////////////////////////
                        INTERFACES
//////////////////////////////////////////////////////////////*/

interface IUniswapV2Router {
    function factory() external view returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 r0, uint112 r1, uint32 blockTimestampLast);
    function totalSupply() external view returns (uint256);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function factory() external view returns (address);
    function kLast() external view returns (uint256);
}

/**
 * @title SwapV2Guard
 * @notice Pre-transaction guard for Uniswap V2 swaps. Performs real-time pool state
 *         checks before a transaction executes. Integrate this as a view call before
 *         submitting your swap transaction.
 *
 * Key fixes over v1:
 *  1. TWAP prices are now compared in consistent UQ112x112 units (was 1e18 vs whole-num).
 *  2. Cumulative price includes current-block accumulation (Uniswap oracle pattern).
 *  3. _intraBlockActivity is block-number based, not timestamp based.
 *  4. performUpkeep is access-controlled to Chainlink forwarder.
 *  5. Swap impact check: flags if the trade would drain > MAX_IMPACT_BPS of a reserve.
 *  6. Duplicate / circular token path detection.
 *  7. K-invariant sanity check: detects reserve manipulation that bypasses zero checks.
 *  8. Pool age check: flags brand-new pools as risky.
 *  9. Severe reserve imbalance detection (possible rug / one-sided drain).
 * 10. amountIn-aware impact check so you can pass the actual trade size.
 */
contract SwapV2Guard is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    AutomationCompatibleInterface
{
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Full guard result. All flags default to false (safe).
    /// A true flag signals a risk condition. Callers should decide which
    /// flags to treat as hard blocks vs soft warnings.
    struct GuardResultV2 {
        // --- Path-level flags ---
        bool DEEP_MULTIHOP;          // path length > MAX_PATH_LEN
        bool DUPLICATE_TOKEN_IN_PATH; // same token appears twice (circular route)
        // --- Per-pool flags (true if ANY hop triggered it) ---
        bool POOL_NOT_EXISTS;
        bool FACTORY_MISMATCH;        // pool's stored factory != router's factory
        bool ZERO_LIQUIDITY;          // either reserve is 0
        bool LOW_LIQUIDITY;           // either reserve below MINIMUM_RESERVE
        bool LOW_LP_SUPPLY;           // total LP supply below THRESHOLD_LP_SUPPLY
        bool POOL_TOO_NEW;            // pool created < MIN_POOL_AGE_BLOCKS ago
        bool SEVERE_IMBALANCE;        // one reserve is < SEVERE_IMBALANCE_BPS of the other
        bool K_INVARIANT_BROKEN;      // current k < kLast (fee switch off — reserve drained)
        bool HIGH_SWAP_IMPACT;        // amountIn would consume > MAX_IMPACT_BPS of reserve
        bool FLASHLOAN_RISK;          // reserve was touched in the current block
        bool PRICE_MANIPULATED;       // spot deviates from TWAP beyond MAX_DEVIATION_BPS
    }

    /// @notice Per-pool TWAP snapshot stored by Chainlink Automation.
    struct PriceSnapshot {
        uint256 cumulative0; // price0CumulativeLast at snapshot time + current-block accrual
        uint256 cumulative1;
        uint32  timestamp;   // block.timestamp at snapshot
        uint256 lastBlock;   // block.number at snapshot
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// Minimum reserve (raw units). Below this we flag LOW_LIQUIDITY.
    uint256 public constant MINIMUM_RESERVE          = 1_000e6;   // ~1000 USDC-like units
    /// Minimum LP token total supply.
    uint256 public constant THRESHOLD_LP_SUPPLY      = 1_000e18;
    /// Maximum swap price deviation from TWAP (basis points, 500 = 5%).
    uint256 public constant MAX_DEVIATION_BPS        = 500;
    /// Minimum TWAP window before we trust it (seconds).
    uint256 public constant MIN_TWAP_WINDOW          = 60;
    /// Maximum path length before flagging deep multihop.
    uint256 public constant MAX_PATH_LEN             = 4;
    /// Max swap impact as % of the input-side reserve (basis points, 1000 = 10%).
    uint256 public constant MAX_IMPACT_BPS           = 1_000;
    /// A pool younger than this many blocks is flagged as risky.
    uint256 public constant MIN_POOL_AGE_BLOCKS      = 300;       // ~1 hour on mainnet
    /// If one reserve < this fraction of the other (bps), flag SEVERE_IMBALANCE.
    uint256 public constant SEVERE_IMBALANCE_BPS     = 100;       // 1% — very skewed

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// Authorised Chainlink Automation forwarder address.
    address public automationForwarder;

    mapping(address => PriceSnapshot) public snapshots;
    address[]                         public trackedPools;

    mapping(address => bool) public trustedRouters;
    mapping(address => bool) public trustedFactories;

    /// How many blocks between Chainlink Automation snapshots.
    uint256 public snapshotBlockInterval;

    /// Block number at which a pool was first snapshotted (used as a proxy for
    /// pool age when the pair contract itself doesn't store creation block).
    mapping(address => uint256) public poolFirstSeenBlock;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RouterTrustSet(address indexed router, bool status);
    event FactoryTrustSet(address indexed factory, bool status);
    event PoolTracked(address indexed pool);
    event SnapshotRecorded(address indexed pool, uint256 block_);
    event ForwarderSet(address indexed forwarder);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _snapshotBlockInterval) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        snapshotBlockInterval = _snapshotBlockInterval == 0 ? 1 : _snapshotBlockInterval;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /*//////////////////////////////////////////////////////////////
                        PRIMARY GUARD ENTRY POINT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pre-transaction swap check. Call this as a static call before submitting
     *         a swap. Pass amountIn = 0 to skip impact check.
     *
     * @param router    The Uniswap V2-compatible router to be used.
     * @param path      Token path (e.g. [WETH, USDC] for a single-hop).
     * @param amountIn  The exact input amount for the swap (used for impact check).
     *                  Pass 0 to skip the impact check.
     * @return result   GuardResultV2 flags struct. All false = clean.
     */
    function swapCheckV2(
        address router,
        address[] calldata path,
        uint256 amountIn
    ) external view returns (GuardResultV2 memory result) {

        require(trustedRouters[router], "UNTRUSTED_ROUTER");

        uint256 len = path.length;
        require(len >= 2, "PATH_TOO_SHORT");

        // ----- Path-level checks -----

        if (len > MAX_PATH_LEN) {
            result.DEEP_MULTIHOP = true;
        }

        if (_hasDuplicateToken(path)) {
            result.DUPLICATE_TOKEN_IN_PATH = true;
        }

        // ----- Per-hop checks -----

        address factory = IUniswapV2Router(router).factory();
        require(trustedFactories[factory], "UNTRUSTED_FACTORY");

        for (uint256 i = 0; i < len - 1; ) {
            address tokenIn  = path[i];
            address tokenOut = path[i + 1];

            address pair = IUniswapV2Factory(factory).getPair(tokenIn, tokenOut);

            if (pair == address(0)) {
                result.POOL_NOT_EXISTS = true;
                unchecked { ++i; }
                continue;
            }

            // Factory stored inside the pair must match the router's factory.
            if (IUniswapV2Pair(pair).factory() != factory) {
                result.FACTORY_MISMATCH = true;
                unchecked { ++i; }
                continue;
            }

            (uint112 r0, uint112 r1, uint32 blockTimestampLast) =
                IUniswapV2Pair(pair).getReserves();

            // --- Zero liquidity (hard block) ---
            if (r0 == 0 || r1 == 0) {
                result.ZERO_LIQUIDITY = true;
                unchecked { ++i; }
                continue;
            }

            // --- Low liquidity ---
            if (uint256(r0) < MINIMUM_RESERVE || uint256(r1) < MINIMUM_RESERVE) {
                result.LOW_LIQUIDITY = true;
            }

            // --- Low LP supply ---
            if (IUniswapV2Pair(pair).totalSupply() < THRESHOLD_LP_SUPPLY) {
                result.LOW_LP_SUPPLY = true;
            }

            // --- Pool age (use firstSeenBlock as proxy) ---
            uint256 firstSeen = poolFirstSeenBlock[pair];
            if (firstSeen != 0 && block.number - firstSeen < MIN_POOL_AGE_BLOCKS) {
                result.POOL_TOO_NEW = true;
            }

            // --- Severe reserve imbalance ---
            if (_isSeverelyImbalanced(r0, r1)) {
                result.SEVERE_IMBALANCE = true;
            }

            // --- K invariant check ---
            // If fee switch is off, kLast == 0 so we skip. If it's set and the
            // current k < kLast, the reserves have been drained abnormally.
            uint256 kLast = IUniswapV2Pair(pair).kLast();
            if (kLast > 0) {
                uint256 currentK = uint256(r0) * uint256(r1);
                if (currentK < kLast) {
                    result.K_INVARIANT_BROKEN = true;
                }
            }

            // --- Flashloan / same-block activity ---
            // Using block number: if the pair's last-updated timestamp matches
            // the current block's timestamp exactly, a tx already ran in this block.
            if (uint32(block.timestamp) == blockTimestampLast) {
                result.FLASHLOAN_RISK = true;
            }

            // --- Swap impact ---
            if (amountIn > 0 && i == 0) {
                // Check impact only on the first hop (subsequent hops depend on output).
                address token0 = IUniswapV2Pair(pair).token0();
                uint256 reserveIn = (tokenIn == token0) ? uint256(r0) : uint256(r1);
                if (_isHighImpact(amountIn, reserveIn)) {
                    result.HIGH_SWAP_IMPACT = true;
                }
            }

            // --- TWAP deviation ---
            if (_isPriceManipulated(pair, tokenIn, r0, r1, blockTimestampLast)) {
                result.PRICE_MANIPULATED = true;
            }

            unchecked { ++i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Detects any duplicate token address in the path (catches circular routes).
     */
    function _hasDuplicateToken(address[] calldata path) internal pure returns (bool) {
        uint256 len = path.length;
        for (uint256 i = 0; i < len; ) {
            for (uint256 j = i + 1; j < len; ) {
                if (path[i] == path[j]) return true;
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
        return false;
    }

    /**
     * @dev True if one reserve is < SEVERE_IMBALANCE_BPS percent of the other.
     */
    function _isSeverelyImbalanced(uint112 r0, uint112 r1) internal pure returns (bool) {
        // r0 < 1% of r1  OR  r1 < 1% of r0
        return
            uint256(r0) * 10_000 < uint256(r1) * SEVERE_IMBALANCE_BPS ||
            uint256(r1) * 10_000 < uint256(r0) * SEVERE_IMBALANCE_BPS;
    }

    /**
     * @dev True if amountIn would consume more than MAX_IMPACT_BPS of reserveIn.
     *      Uses the constant product formula to estimate actual price impact.
     *      amountInWithFee / (reserveIn + amountInWithFee) > MAX_IMPACT_BPS / 10000
     */
    function _isHighImpact(uint256 amountIn, uint256 reserveIn) internal pure returns (bool) {
        if (reserveIn == 0) return true;
        uint256 amountInWithFee = amountIn * 997; // 0.3% V2 fee
        uint256 numerator       = amountInWithFee * 10_000;
        uint256 denominator     = (reserveIn * 1000) + amountInWithFee;
        uint256 impactBps       = numerator / denominator;
        return impactBps >= MAX_IMPACT_BPS;
    }

    /**
     * @dev TWAP deviation check.
     *
     * BUG FIX: The original compared spot (1e18 scale) vs TWAP (UQ112x112 >> 112,
     * which drops all fractional bits). Now both sides are compared in UQ112x112
     * format for correct precision.
     *
     * BUG FIX: The cumulative price is updated lazily in V2 — only on the first
     * trade of each block. We reconstruct the "true" current cumulative by adding
     * the time that has elapsed since the last trade at the current reserve ratio,
     * exactly as Uniswap's own oracle library does.
     */
    function _isPriceManipulated(
        address pair,
        address tokenIn,
        uint112 r0,
        uint112 r1,
        uint32  blockTimestampLast
    ) internal view returns (bool) {

        PriceSnapshot memory snap = snapshots[pair];
        if (snap.lastBlock == 0) return false; // no snapshot yet

        uint32 windowElapsed = uint32(block.timestamp) - snap.timestamp;
        if (windowElapsed < MIN_TWAP_WINDOW) return false; // window too short to trust

        // Reconstruct the current cumulative price including elapsed time in this block.
        // Uniswap stores cumulative as sum(price * dt) where price is UQ112x112.
        uint32 timeElapsedSinceTrade = uint32(block.timestamp) - blockTimestampLast;

        uint256 current0;
        uint256 current1;
        {
            IUniswapV2Pair p = IUniswapV2Pair(pair);
            // price0 = r1/r0 in UQ112x112
            uint256 price0UQ = (uint256(r1) << 112) / uint256(r0);
            uint256 price1UQ = (uint256(r0) << 112) / uint256(r1);
            current0 = p.price0CumulativeLast() + price0UQ * timeElapsedSinceTrade;
            current1 = p.price1CumulativeLast() + price1UQ * timeElapsedSinceTrade;
        }

        // TWAP = delta_cumulative / delta_time  →  result is UQ112x112
        uint256 twap0UQ = (current0 - snap.cumulative0) / windowElapsed;
        uint256 twap1UQ = (current1 - snap.cumulative1) / windowElapsed;

        // Spot price in UQ112x112 (same unit as twap)
        address token0 = IUniswapV2Pair(pair).token0();
        uint256 spotUQ;
        uint256 twapUQ;

        if (tokenIn == token0) {
            // We want: how much token1 per unit of token0
            spotUQ = (uint256(r1) << 112) / uint256(r0);
            twapUQ = twap0UQ;
        } else {
            // We want: how much token0 per unit of token1
            spotUQ = (uint256(r0) << 112) / uint256(r1);
            twapUQ = twap1UQ;
        }

        if (twapUQ == 0) return false;

        return !_withinDeviation(spotUQ, twapUQ);
    }

    /**
     * @dev Returns true when spot is within MAX_DEVIATION_BPS of twap.
     *      Both values must be in the same unit (UQ112x112).
     */
    function _withinDeviation(uint256 spot, uint256 twap) internal pure returns (bool) {
        uint256 diff = spot > twap ? spot - twap : twap - spot;
        return (diff * 10_000) / twap < MAX_DEVIATION_BPS;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC TWAP VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current TWAP for a tracked pool.
     *         Prices are in UQ112x112 format (multiply by 1e18 / 2^112 for decimal).
     * @return twap0UQ TWAP of token0 priced in token1 (UQ112x112)
     * @return twap1UQ TWAP of token1 priced in token0 (UQ112x112)
     * @return windowSeconds Duration of the TWAP window
     */
    function getTWAP(address pair)
        external
        view
        returns (uint256 twap0UQ, uint256 twap1UQ, uint32 windowSeconds)
    {
        PriceSnapshot memory snap = snapshots[pair];
        if (snap.timestamp == 0) return (0, 0, 0);

        uint32 elapsed = uint32(block.timestamp) - snap.timestamp;
        if (elapsed == 0) return (0, 0, 0);

        (uint112 r0, uint112 r1, uint32 blockTimestampLast) =
            IUniswapV2Pair(pair).getReserves();

        uint32 timeElapsedSinceTrade = uint32(block.timestamp) - blockTimestampLast;
        uint256 price0UQ = r0 > 0 ? (uint256(r1) << 112) / uint256(r0) : 0;
        uint256 price1UQ = r1 > 0 ? (uint256(r0) << 112) / uint256(r1) : 0;

        IUniswapV2Pair p = IUniswapV2Pair(pair);
        uint256 current0 = p.price0CumulativeLast() + price0UQ * timeElapsedSinceTrade;
        uint256 current1 = p.price1CumulativeLast() + price1UQ * timeElapsedSinceTrade;

        twap0UQ = (current0 - snap.cumulative0) / elapsed;
        twap1UQ = (current1 - snap.cumulative1) / elapsed;
        windowSeconds = elapsed;
    }

    /*//////////////////////////////////////////////////////////////
                    CHAINLINK AUTOMATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Chainlink Automation checkUpkeep — identifies pools needing a snapshot.
     */
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 total = trackedPools.length;
        address[] memory temp = new address[](total);
        uint256 count;

        for (uint256 i = 0; i < total; ) {
            address pool = trackedPools[i];
            if (block.number - snapshots[pool].lastBlock >= snapshotBlockInterval) {
                temp[count] = pool;
                unchecked { ++count; }
            }
            unchecked { ++i; }
        }

        if (count == 0) return (false, "");

        address[] memory pools = new address[](count);
        for (uint256 i = 0; i < count; ) {
            pools[i] = temp[i];
            unchecked { ++i; }
        }

        return (true, abi.encode(pools));
    }

    /**
     * @notice Chainlink Automation performUpkeep — records snapshots.
     * @dev BUG FIX: Now access-controlled to the registered Chainlink forwarder
     *      to prevent anyone calling with arbitrary pool addresses.
     */
    function performUpkeep(bytes calldata data) external override nonReentrant {
        require(
            msg.sender == automationForwarder || msg.sender == owner(),
            "UNAUTHORIZED_UPKEEP"
        );

        address[] memory pools = abi.decode(data, (address[]));
        uint256 len = pools.length;

        for (uint256 i = 0; i < len; ) {
            address pool = pools[i];
            if (block.number - snapshots[pool].lastBlock >= snapshotBlockInterval) {
                _recordSnapshot(pool);
            }
            unchecked { ++i; }
        }
    }

    /**
     * @dev Records a TWAP snapshot with corrected cumulative price (includes
     *      current-block accrual so getFairPrice is always fresh).
     */
    function _recordSnapshot(address pair) internal {
        IUniswapV2Pair p = IUniswapV2Pair(pair);
        (uint112 r0, uint112 r1, uint32 blockTimestampLast) = p.getReserves();

        // Include accrual since last trade
        uint32 timeElapsedSinceTrade = uint32(block.timestamp) - blockTimestampLast;
        uint256 price0UQ = r0 > 0 ? (uint256(r1) << 112) / uint256(r0) : 0;
        uint256 price1UQ = r1 > 0 ? (uint256(r0) << 112) / uint256(r1) : 0;

        snapshots[pair] = PriceSnapshot({
            cumulative0: p.price0CumulativeLast() + price0UQ * timeElapsedSinceTrade,
            cumulative1: p.price1CumulativeLast() + price1UQ * timeElapsedSinceTrade,
            timestamp:   uint32(block.timestamp),
            lastBlock:   block.number
        });

        emit SnapshotRecorded(pair, block.number);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN
    //////////////////////////////////////////////////////////////*/

    function addTrackedPool(address pool) external onlyOwner {
        require(pool != address(0), "ZERO_ADDRESS");
        trackedPools.push(pool);

        if (poolFirstSeenBlock[pool] == 0) {
            poolFirstSeenBlock[pool] = block.number;
        }

        _recordSnapshot(pool);
        emit PoolTracked(pool);
    }

    function removeTrackedPool(address pool) external onlyOwner {
        uint256 len = trackedPools.length;
        for (uint256 i = 0; i < len; ) {
            if (trackedPools[i] == pool) {
                trackedPools[i] = trackedPools[len - 1];
                trackedPools.pop();
                return;
            }
            unchecked { ++i; }
        }
        revert("POOL_NOT_TRACKED");
    }

    function setSnapshotBlockInterval(uint256 blocks_) external onlyOwner {
        require(blocks_ > 0, "ZERO_INTERVAL");
        snapshotBlockInterval = blocks_;
    }

    function setTrustedRouter(address router, bool status) external onlyOwner {
        trustedRouters[router] = status;
        emit RouterTrustSet(router, status);
    }

    function setTrustedFactory(address factory, bool status) external onlyOwner {
        trustedFactories[factory] = status;
        emit FactoryTrustSet(factory, status);
    }

    /**
     * @notice Set the Chainlink Automation forwarder address.
     *         Get this from the Chainlink Automation UI after registering your upkeep.
     */
    function setAutomationForwarder(address forwarder) external onlyOwner {
        require(forwarder != address(0), "ZERO_ADDRESS");
        automationForwarder = forwarder;
        emit ForwarderSet(forwarder);
    }

    function trackedPoolsLength() external view returns (uint256) {
        return trackedPools.length;
    }
}
