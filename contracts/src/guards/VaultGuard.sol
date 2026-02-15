// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

abstract contract BaseGuard {
    enum RiskLevel {
        SAFE,      // 0
        WARNING,   // 1
        BLOCK      // 2
    }

    struct GuardResult {
        RiskLevel level;
        bytes32[] reasons;
    }

    function _single(
        RiskLevel level,
        bytes32 reason
    ) internal pure returns (GuardResult memory r) {
        r.level = level;
        r.reasons = new bytes32;
        r.reasons[0] = reason;
    }

    function _safe() internal pure returns (GuardResult memory r) {
        r.level = RiskLevel.SAFE;
        r.reasons = new bytes32;
    }
}

contract VaultGuard is BaseGuard {
    /*//////////////////////////////////////////////////////////////
                                REASONS
    //////////////////////////////////////////////////////////////*/

    bytes32 internal constant VAULT_ZERO_SUPPLY_INFLATION =
        keccak256("VAULT_ZERO_SUPPLY_INFLATION");

    bytes32 internal constant VAULT_BALANCE_MISMATCH =
        keccak256("VAULT_BALANCE_MISMATCH");

    bytes32 internal constant VAULT_EXCHANGE_RATE_SPIKE =
        keccak256("VAULT_EXCHANGE_RATE_SPIKE");

    bytes32 internal constant VAULT_DUST_SHARE_RISK =
        keccak256("VAULT_DUST_SHARE_RISK");

    /*//////////////////////////////////////////////////////////////
                             CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @dev 2% = warning, 10% = block
    uint256 internal constant WARNING_BPS = 200; // 2%
    uint256 internal constant BLOCK_BPS   = 1000; // 10%
    uint256 internal constant BPS_DENOM   = 10_000;

    /// @dev Minimum shares minted to avoid dust rounding exploits
    uint256 internal constant MIN_SHARES = 1e6;

    /*//////////////////////////////////////////////////////////////
                              MAIN CHECK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks vault state safety for deposit/withdraw
     * @param vault ERC4626 vault address
     * @param assets Amount of assets user intends to deposit/withdraw
     */
    function checkVault(
        address vault,
        uint256 assets
    ) external view returns (GuardResult memory) {
        IERC4626 v = IERC4626(vault);
        IERC20 asset = IERC20(v.asset());

        uint256 totalAssets = v.totalAssets();
        uint256 totalSupply = v.totalSupply();

        /*//////////////////////////////////////////////////////////////
            1. Zero-supply inflation (classic donation attack)
        //////////////////////////////////////////////////////////////*/

        if (totalSupply == 0 && totalAssets > 0) {
            return _single(
                RiskLevel.BLOCK,
                VAULT_ZERO_SUPPLY_INFLATION
            );
        }

        /*//////////////////////////////////////////////////////////////
            2. Balance mismatch (unaccounted donation)
        //////////////////////////////////////////////////////////////*/

        uint256 realBalance = asset.balanceOf(vault);

        if (realBalance > totalAssets) {
            return _single(
                RiskLevel.BLOCK,
                VAULT_BALANCE_MISMATCH
            );
        }

        /*//////////////////////////////////////////////////////////////
            3. Exchange rate spike detection
        //////////////////////////////////////////////////////////////*/

        if (totalSupply > 0 && totalAssets > 0) {
            uint256 exchangeRate = (totalAssets * 1e18) / totalSupply;

            // Simulate small deposit to infer rate stability
            uint256 previewShares = v.previewDeposit(assets);

            if (previewShares == 0 && assets > 0) {
                return _single(
                    RiskLevel.WARNING,
                    VAULT_DUST_SHARE_RISK
                );
            }

            uint256 impliedRate =
                (assets * 1e18) / previewShares;

            uint256 deltaBps = _bpsDelta(exchangeRate, impliedRate);

            if (deltaBps > BLOCK_BPS) {
                return _single(
                    RiskLevel.BLOCK,
                    VAULT_EXCHANGE_RATE_SPIKE
                );
            }

            if (deltaBps > WARNING_BPS) {
                return _single(
                    RiskLevel.WARNING,
                    VAULT_EXCHANGE_RATE_SPIKE
                );
            }
        }

        /*//////////////////////////////////////////////////////////////
            4. Dust share mint risk
        //////////////////////////////////////////////////////////////*/

        if (assets > 0) {
            uint256 sharesOut = v.previewDeposit(assets);

            if (sharesOut < MIN_SHARES) {
                return _single(
                    RiskLevel.WARNING,
                    VAULT_DUST_SHARE_RISK
                );
            }
        }

        return _safe();
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL MATH
    //////////////////////////////////////////////////////////////*/

    function _bpsDelta(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        if (a > b) {
            return ((a - b) * BPS_DENOM) / a;
        } else {
            return ((b - a) * BPS_DENOM) / b;
        }
    }
}
