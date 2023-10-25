// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @dev In this contract the collateral is a dollar-pegged stablecoin (here USDC).
/// We _could_ assume it is indeed always pegged to the dollar at a 1:1 ratio, but we
/// might as well use Chainlink data feeds to get its most accurate price.

/* -------------------------------------------------------------------------- */
/*                                    STEPS                                   */
/* -------------------------------------------------------------------------- */

// [ ] 1. ERC20 interface, the only allowed token to use as collateral
// [ ] 2. Indexed asset, oracle price feed
// [ ] 3. ERC4626 Vault to account for deposits + add deposit functionnality
// [ ] 4. Withdraw functionnality BUT WITH TODO to check if allowed to withdraw
// [ ] 5. Calculation for total open interest + total open interest in tokens
// [ ] 6. Calculation for LP value
// [ ] 7. Calculation for available liquidity to withdraw (see liquidity reserve restrictions)
// -> (shortOpenInterest) + (longOpenInterestInTokens * currentIndexTokenPrice) < (depositedLiquidity * maxUtilizationPercentage)
// [ ] 8. Calculation for PnL (for both long and short)
// [ ] 9. Right now no need to close positions but what happens then? Delete it? Set it to open = false?
// [ ] 10. Open long/short position
// [ ] 11. Increase size
// [ ] 12. Increase collateral
// Stop it here for this mission

/* -------------------------------------------------------------------------- */
/*                                  CONTRACT                                  */
/* -------------------------------------------------------------------------- */

import {IERC20} from "./interfaces/IERC20.sol";

contract Perps {
    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                                   STRUCT                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev A token used either as collateral or as the indexed asset
    /// @param token The address of the token
    /// @param priceFeed The address of the Chainlink price feed (token/USD)
    /// @param decimals The number of decimals of the token
    struct Token {
        address token;
        address priceFeed;
        uint256 decimals;
    }

    struct Position {}
    // size, sizeInToken, collateral, direction, open?, timestamp?, address?

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The type of the position; either LONG (1) or SHORT (2)
    uint256 constant LONG = 1;
    uint256 constant SHORT = 2;

    /// @dev The maximum percentage of total liquidity that can be actively used
    /// @dev Meaning that a withdrawal or a new position cannot be opened if it would
    /// make the total open interest exceed this percentage
    uint256 constant MAX_EXPOSURE = 70; // 70%

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /* ----------------------------- STATE VARIABLES ---------------------------- */

    /// @dev The ERC20 token used as collateral
    /// @dev Here USDC
    Token public collateralToken;

    /// @dev The ERC20 token used as the indexed asset
    /// @dev Here BTC
    Token public indexedToken;

    /// @dev The total open interest in USD (total size of all positions)
    uint256 public totalOpenInterestUsd;

    /// @dev The total open interest indexed-token wise
    /// @dev Here in BTC
    uint256 public totalOpenInterestToken;

    /// @dev The total liquidity deposited in USD
    uint256 public totalLiquidity;

    // Total PnL -> NO; this is calculated at "runtime" when closing a position BUT also depositing/withdrawing liquidity
    // Override totalAssets from ERC4626 to actually use LP Value (total deposited - PnL)

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTRUCTOR                               */
    /* -------------------------------------------------------------------------- */

    constructor() {}

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
    /* --------------------------- LIQUIDITY PROVIDERS -------------------------- */

    function depositLiquidity() external payable {}

    function withdrawLiquidity(uint256 amount) external {}

    /* --------------------------------- TRADERS -------------------------------- */

    function openLong(uint256 size, uint256 collateral) external {}

    function openShort(uint256 size, uint256 collateral) external {}

    function increaseSize(uint256 positionId, uint256 size) external {}

    function increaseCollateral(uint256 positionId, uint256 collateral) external {}

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
    /* --------------------------------- TRADERS -------------------------------- */

    function _setPosition(uint256 size, uint256 collateral, uint256 direction) internal {
        // size or collateral 0 (idk) -> close position

        // Limit the position to the configured percentage of the deposited liquidity
    }

    function _setOpenInterest(Position memory position) internal view returns (uint256) {
        // Called each time a position is opened/increased (and later decreased/closed to decrease the open interest)
        // Update the open interest with the last position
        // Would be nice to use a int256 in the position so we can do it regardless of long/short??
        // Maybe use a different function to actually calculate it, return it and just update it here
        // Maybe also use another function to convert it to tokens??

        // Set the new open interest in USD
        // Set the new open interest in tokens
    }

    /* --------------------------- LIQUIDITY PROVIDERS -------------------------- */

    function _depositLiquidity(uint256 amount) internal {}

    function _withdrawLiquidity(uint256 amount) internal {
        // cannot witdraw liquidity that is reserved for positions
        // -> basically check that the invariants are not broken
        // --> might as well check it before with simple revert but also enfore at after??

        // Also check the liquidity reserve restrictions (see calculation)

        // Probably calculated the net value so might as well emit it
    }

    /* -------------------------------- PROTOCOL -------------------------------- */

    function _validateLiquidityRestrictions() internal {
        // Invariants
        // Basically check again that the new position/liquidity withdrawal does not break the invariants
        // Even thought it's a bit redundant since it's been checked before, it's the
        // most important part of the contract so better safe than sorry
    }

    function _calculateTotalPnL() internal view returns (uint256) {}

    function _calculateNetValue() internal view returns (uint256) {}

    function _calculateAvailableLiquidity() internal view returns (uint256) {
        // See liquidity reserve restrictions
    }

    /* ---------------------------------- ASSET --------------------------------- */

    function _assetPrice() internal pure returns (uint256) {
        // get price from oracle
    }
}
