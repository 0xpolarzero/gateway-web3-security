// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev Aggregate all constants in a single file for easier management.
/// @dev Inspired from GMX V2 Keys library for DataStore values
/// https://github.com/gmx-io/gmx-synthetics/blob/main/contracts/data/Keys.sol

library Keys {
    /* -------------------------------------------------------------------------- */
    /*                                  PROTOCOL                                  */
    /* -------------------------------------------------------------------------- */
    /// @dev The maximum percentage of total liquidity that can be actively used
    uint256 internal constant MAX_EXPOSURE = 70; // 70%

    /* -------------------------------------------------------------------------- */
    /*                                   ORACLE                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev The maximum time allowed for a price update
    uint256 internal constant MAX_ORACLE_RESPONSE_TIMEOUT = 3 hours;
}
