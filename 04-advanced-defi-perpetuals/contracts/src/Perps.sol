// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @dev In this contract the collateral is a dollar-pegged stablecoin (here USDC).
/// We _could_ assume it is indeed always pegged to the dollar at a 1:1 ratio, but we
/// might as well use Chainlink data feeds to get its most accurate price.

/// @dev This contract is voluntarily simplified and does not include many functionnalities
/// that will be added in the next mission.
/// @dev Is it also missing many getters and setters (e.g. price feeds).

/* -------------------------------------------------------------------------- */
/*                                    STEPS                                   */
/* -------------------------------------------------------------------------- */

// [x] 1. ERC20 interface, the only allowed token to use as collateral
// [x] 2. Indexed asset, oracle price feed
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

import {ERC4626} from "solady/tokens/ERC4626.sol";

import {Keys} from "./libraries/Keys.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {Utils} from "./libraries/Utils.sol";

import {IERC20} from "./interfaces/IERC20.sol";

contract Perps is ERC4626 {
    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                                   STRUCT                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev An asset (token) used as collateral
    /// @param token The address of the asset
    /// @param priceFeed The address of the Chainlink price feed (token/USD)
    /// @param decimals The number of decimals of the asset
    struct Asset {
        address token;
        address priceFeed;
        uint8 decimals;
    }

    // struct Position {}
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
    uint256 constant MAX_EXPOSURE = Keys.MAX_EXPOSURE;

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */
    /* ----------------------------- STATE VARIABLES ---------------------------- */

    /// @dev The ERC20 token used as collateral
    /// @dev Here USDC
    Asset public collateralAsset;

    /// @dev The ERC20 token used as the indexed asset
    /// @dev Here BTC
    /// Note: We actually just need the price feed, so the address & decimals will be left empty
    /// It just makes it more consistent with the collateral asset
    Asset public indexedToken;

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

    /**
     * @dev Initialize the contract with the collateral asset and the indexed asset
     * @param collateral The token used as collateral (address, price feed & decimals)
     * @param indexedPriceFeed The price feed of the indexed asset (token/USD)
     */

    constructor(Asset memory collateral, address indexedPriceFeed) {
        collateralAsset = collateral;
        indexedToken.priceFeed = indexedPriceFeed; // The token & decimals can stay empty
    }

    /* -------------------------------------------------------------------------- */
    /*                             EXTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
    /* --------------------------- LIQUIDITY PROVIDERS -------------------------- */

    /**
     * @dev Deposit liquidity in the contract
     * @dev The ERC4626 Vault `deposit` function will basically take care of everything, including:
     * - Transfering the collateral to the contract
     *   - The amount needs to be approved beforehand
     *   - The transaction will revert if the transfer fails, meaning that it won't fail silently
     * - Minting the corresponding amount of shares to the caller
     * - Emitting a `Deposit` event, which will include the following:
     *   - address indexed by,
     *   - address indexed to,
     *   - uint256 assets,
     *   - uint256 shares.
     * @dev The total liquidity will be updated in the `_afterDeposit` hook
     * @param amount The amount of collateral (collateralAsset) to deposit
     */
    function depositLiquidity(uint256 amount) external {
        // Check that the amount is not 0 - this will revert if it's the case
        Utils.assembly_checkValueNotZero(amount);
        // Call the ERC4626 Vault `deposit` function
        deposit(amount, msg.sender);
    }

    function withdrawLiquidity(uint256 amount) external {}

    /* --------------------------------- TRADERS -------------------------------- */

    function openLong(uint256 size, uint256 collateral) external {}

    function openShort(uint256 size, uint256 collateral) external {}

    function increaseSize(uint256 positionId, uint256 size) external {}

    function increaseCollateral(uint256 positionId, uint256 collateral) external {}

    /* --------------------------------- GETTERS -------------------------------- */

    function getCollateralPrice() external view returns (int256) {
        return _assetPrice(collateralAsset.priceFeed);
    }

    function getIndexedPrice() external view returns (int256) {
        return _assetPrice(indexedToken.priceFeed);
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
    /* --------------------------------- TRADERS -------------------------------- */

    function _setPosition(uint256 size, uint256 collateral, uint256 direction) internal {
        // size or collateral 0 (idk) -> close position
        // Limit the position to the configured percentage of the deposited liquidity
    }

    function _setOpenInterest() internal view /* Position memory position */ returns (uint256) {
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

    function _calculateTotalPnL() internal view returns (uint256 totalPnL) {}

    function _calculateNetValue() internal view returns (uint256 netValue) {}

    function _calculateAvailableLiquidity() internal view returns (uint256 availableLiquidity) {
        // See liquidity reserve restrictions
    }

    /* ---------------------------------- ASSET --------------------------------- */

    /**
     * @dev Get the price of the asset from the Chainlink price feed
     * @dev This will revert if the price is stale (see Keys.MAX_ORACLE_RESPONSE_TIMEOUT)
     * @param priceFeed The address of the price feed (token/USD)
     * @return price The price of the asset with 8 decimals
     */

    function _assetPrice(address priceFeed) internal view returns (int256 price) {
        (, price,,,) = OracleLib.staleCheckLatestRoundData(priceFeed);
    }

    /* -------------------------------------------------------------------------- */
    /*                              ERC4626 OVERRIDES                             */
    /* -------------------------------------------------------------------------- */
    /* ------------------------------- ACCOUNTING ------------------------------- */

    function totalAssets() public view override returns (uint256) {
        // return _calculateNetValue(); but maybe with additional decimals now?? don't think so
        return 0;
    }

    /* -------------------------------- CONSTANTS ------------------------------- */

    /// @dev Return the address of the underlying asset (here USDC)
    function asset() public view override returns (address) {
        return collateralAsset.token;
    }

    /// @dev Return the number of decimals of the underlying asset (here USDC)
    function _underlyingDecimals() internal view override returns (uint8) {
        return collateralAsset.decimals;
    }

    /// @dev Return an offset value to increase precision
    /// @dev It will also significantly reduce the risk of an inflation attack
    /// @dev Here we have 12 decimals added to the original 6 decimals of USDC
    /// which makes it being handled as a 18 decimals token in the vault
    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }

    /* ---------------------------------- HOOKS --------------------------------- */

    /// @dev Hook that is called before any withdrawal or redemption.
    function _beforeWithdraw(uint256 assets, uint256 shares) internal override {}

    /**
     * @dev Hook that is called after any deposit or mint.
     * @param assets The amount of collateral deposited
     */

    function _afterDeposit(uint256 assets, uint256 /* shares */ ) internal override {
        // Update the total liquidity
        totalLiquidity = totalLiquidity + assets;
    }

    /* ---------------------------- METADATA (ERC20) ---------------------------- */

    function name() public view virtual override returns (string memory) {
        return "Perps Vault";
    }

    function symbol() public view virtual override returns (string memory) {
        return "PV";
    }
}
