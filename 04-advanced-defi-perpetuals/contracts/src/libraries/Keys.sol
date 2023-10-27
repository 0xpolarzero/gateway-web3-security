// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Aggregate all constants in a single file for easier management.
/// @dev Inspired from GMX V2 Keys library for DataStore values
/// https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/data/Keys.sol

library Keys {
    /* -------------------------------------------------------------------------- */
    /*                                  PROTOCOL                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev The direction of a position; either long (1) or short (2)
    uint256 internal constant POSITION_LONG = 0;
    uint256 internal constant POSITION_SHORT = 1;

    /// @dev The status of a position; either open (1) or closed (2)
    uint256 internal constant POSITION_OPEN = 0;
    uint256 internal constant POSITION_CLOSED = 1;

    /// @dev The precision of the collateral token
    uint256 internal constant COLLATERAL_TOKEN_PRECISION = 1e6;
    /// @dev The decimals of the collateral token
    uint8 internal constant COLLATERAL_TOKEN_DECIMALS = 6;
    /// @dev The precision of the index token
    uint256 internal constant INDEX_TOKEN_PRECISION = 1e8;

    /// @dev The additional precision for internal calculations (1e12)
    uint256 internal constant ADDITIONAL_COLLATERAL_PRECISION = 1e18 / COLLATERAL_TOKEN_PRECISION;
    /// @dev The additional precision for internal calculations (1e10)
    uint256 internal constant ADDITIONAL_INDEX_PRECISION = 1e18 / INDEX_TOKEN_PRECISION;

    /// @dev The maximum percentage of total liquidity that can be actively used (actually also - total PnL)
    uint256 internal constant MAX_EXPOSURE = 70; // 70%

    /// @dev The maximum leverage allowed for a position before liquidation
    uint256 internal constant MAX_LEVERAGE = 15 * COLLATERAL_TOKEN_PRECISION; // 15x

    /// @dev The minimum size allowed for a position
    uint256 internal constant MIN_POSITION_SIZE = 5 * COLLATERAL_TOKEN_PRECISION; // 5 USD

    /// @dev The minimum amount of collateral required to open a position
    uint256 internal constant MIN_POSITION_COLLATERAL = 5 * COLLATERAL_TOKEN_PRECISION; // 5 USD

    /* -------------------------------------------------------------------------- */
    /*                                   ORACLE                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev The maximum time allowed for a price update
    uint256 internal constant MAX_ORACLE_RESPONSE_TIMEOUT = 3 hours;

    /// @dev The precision of the price returned by the oracle
    uint256 internal constant PRICE_FEED_PRECISION = 1e8; // 8 decimals

    /* -------------------------------------------------------------------------- */
    /*                                ERC4626 VAULT                               */
    /* -------------------------------------------------------------------------- */

    /// @dev The decimals offset to mitigate floating point precision errors
    uint8 internal constant DECIMALS_OFFSET = 12;
}
