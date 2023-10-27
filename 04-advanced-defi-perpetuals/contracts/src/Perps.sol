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
/// @dev The following steps are purposely left for documentation

// [x] 1. ERC20 interface, the only allowed token to use as collateral
// [x] 2. Indexed asset, oracle price feed
// [x] 3. ERC4626 Vault to account for deposits + add deposit functionnality
// [x] 4. Withdraw functionnality BUT WITH TODO to check if allowed to withdraw
// [x] 5. Calculation for total open interest + total open interest in tokens
// [x] 6. Calculation for LP value
// [x] 7. Calculation for available liquidity to withdraw (see liquidity reserve restrictions)
// -> (shortOpenInterest) + (longOpenInterestInTokens * currentIndexTokenPrice) < (depositedLiquidity * maxUtilizationPercentage)
// [ ] 8. Calculation for PnL (for both long and short)
// -> WE MIGHT BE ABLE TO FIND IT EASILY:
// -> We have total size in tokens (=open interest) for each type, we just need to compare it to current index price
// -> then combine both and get a PnL
// [x] 9. Open long/short position
// [ ] 10. Increase size
// [ ] 11. Increase collateral
// Stop it here for this mission
// Later to close position, 2 choices
// 1. When opening position, add index of the position in the array
// -> when closing, delete it from the array (replace with last, delete last, update index)
// -> in this case, we can remove OPEN/CLOSED status
// 2. Keep the array as is, but add a status (open/closed)
// -> when closing, set status to closed
// -> but then at some point we might have a lot of closed positions in the array

/* -------------------------------------------------------------------------- */
/*                                  CONTRACT                                  */
/* -------------------------------------------------------------------------- */

import {ERC4626} from "solady/tokens/ERC4626.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {Keys} from "./libraries/Keys.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

import {IERC20} from "./interfaces/IERC20.sol";

contract Perps is ERC4626 {
    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev The value cannot be 0
    error Perps_ZeroValueNotAllowed();

    /// @dev There is not enough liquidity to perform the operation
    error Perps_NotEnoughLiquidity(uint256 availableLiquidity);

    /// @dev The position size is too small
    error Perps_SizeTooSmall(uint256 size, uint256 minSize);

    /// @dev The position does not have enough collateral
    error Perps_NotEnoughCollateral(uint256 collateral, uint256 minCollateral);

    /// @dev The leverage is too high
    error Perps_LeverageTooHigh(uint256 leverage, uint256 maxLeverage);

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when the open interest is updated
    /// @param longUsd The total open interest for longs in USD (6 decimals)
    /// @param longTokens The total open interest for longs in tokens (8 decimals)
    /// @param shortUsd The total open interest for shorts in USD (6 decimals)
    /// @param shortTokens The total open interest for shorts in tokens (8 decimals)
    event Perps_OpenInterestUpdated(uint128 longUsd, uint128 longTokens, uint128 shortUsd, uint128 shortTokens);

    /// @dev Emitted when a position is opened
    /// @param trader The address of the trader
    /// @param size The size of the position in USD (6 decimals)
    /// @param collateral The amount of collateral deposited to back this position (6 decimals)
    /// @param direction The direction of the position (long or short)
    /// @param leverage The initial of the position
    event Perps_PositionOpened(
        address indexed trader, uint256 size, uint256 collateral, uint256 direction, uint256 leverage
    );

    /* -------------------------------------------------------------------------- */
    /*                                   STRUCT                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev An asset (token) used as collateral or index
    /// @param token The address of the asset
    /// @param priceFeed The address of the Chainlink price feed (token/USD)
    /// @param decimals The number of decimals of the asset
    struct Asset {
        address token;
        address priceFeed;
        uint8 decimals;
    }

    /// @dev A total open interest (either long or short)
    /// @param usd The total open interest in USD (6 decimals)
    /// @param tokens The total open interest in tokens (8 decimals)
    struct OpenInterest {
        uint128 usd; // this can go as high as 340 trillion trillion trillion USD
        uint128 tokens; // this can go as high as 3.4 trillion trillion trillion tokens
    }

    /// @dev A position
    /// @dev We don't include the address of the trader here, as we don't need it
    /// @param size The size of the position in USD (6 decimals)
    /// @param collateral The collateral deposited to back the position in collateral tokens (6 decimals)
    /// @param sizeInTokens The size of the position in tokens (8 decimals)
    /// @param owner The address of the trader
    /// @param direction The direction of the position (long or short)
    /// @param status The status of the position (open or closed)
    /// @param timestamp The timestamp of the position creation
    struct Position {
        uint128 size;
        uint128 collateral;
        uint192 sizeInTokens; // might as well finish that second slot
        uint8 direction;
        uint8 status;
        uint48 timestamp;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */
    /* ----------------------------- STATE VARIABLES ---------------------------- */

    /// @dev The ERC20 token used as collateral
    /// @dev Here USDC
    Asset public collateralAsset;

    /// @dev The ERC20 token used as the index asset
    /// @dev Here BTC
    /// Note: We actually just need the price feed, so the address & decimals will be left empty
    /// It just makes it more consistent with the collateral asset
    Asset public indexToken;

    /// @dev The total open interest for shorts (total size of all these positions)
    OpenInterest public shortOpenInterest;

    /// @dev The total open interest for longs (total size of all these positions)
    OpenInterest public longOpenInterest;

    /// @dev The total liquidity deposited in USD
    uint256 public totalLiquidity;

    /// @dev The positions associated to each trader
    mapping(address trader => Position[] positions) public positions;

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTRUCTOR                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Initialize the contract with the collateral asset and the index asset
     * @param collateral The token used as collateral (address, price feed & decimals)
     * @param indexPriceFeed The price feed of the index asset (token/USD)
     */

    constructor(Asset memory collateral, address indexPriceFeed) {
        collateralAsset = collateral;
        indexToken.priceFeed = indexPriceFeed; // The token & decimals can stay empty
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
     *   - address indexed owner,
     *   - uint256 assets,
     *   - uint256 shares.
     * @dev The total liquidity will be updated in the `_afterDeposit` hook
     * @param amount The amount of collateral (collateralAsset) to deposit
     */
    function depositLiquidity(uint256 amount) external {
        if (amount == 0) revert Perps_ZeroValueNotAllowed();
        // Call the ERC4626 Vault `deposit` function
        deposit(amount, msg.sender);
    }

    /**
     * @dev Withdraw liquidity from the contract
     * @dev The ERC4626 Vault `withdraw` function will basically take care of everything, including:
     * - Burning the corresponding amount of shares from the caller
     * - Transfering back the collateral to the provider
     *   - The transaction will revert if the transfer fails, meaning that it won't fail silently
     * - Emitting a `Withdraw` event, which will include the following:
     *   - address indexed by,
     *   - address indexed to,
     *   - address indexed owner,
     *   - uint256 assets,
     *   - uint256 shares.
     * @dev The available liquidity will be checked in the `_beforeWithdraw` hook
     * @dev The total liquidity will be updated in the `_beforeWithdraw` hook
     * @param amount The amount of collateral (collateralAsset) to withdraw
     */
    function withdrawLiquidity(uint256 amount) external {
        if (amount == 0) revert Perps_ZeroValueNotAllowed();
        // Call the ERC4626 Vault `withdraw` function
        // amount, recipient, owner
        withdraw(amount, msg.sender, msg.sender);

        // Verify that the invariants are not broken
        // @audit-info Is this too redundant?
        // Or maybe we can remove the check in the `_beforeWithdraw` hook?
        _validateLiquidityRestrictions();
    }

    /* --------------------------------- TRADERS -------------------------------- */

    /**
     * @dev Create a long position
     * @dev The conditions/overall process are described in the `_openPosition` function
     * @param size The size of the position in USD (6 decimals)
     * @param collateral The amount of collateral deposited to back this position (6 decimals)
     */

    function openLong(uint256 size, uint256 collateral) external {
        _openPosition(size, collateral, Keys.POSITION_LONG);
    }

    /**
     * @dev Create a short position
     * @dev The conditions/overall process are described in the `_openPosition` function
     * @param size The size of the position in USD (6 decimals)
     * @param collateral The amount of collateral deposited to back this position (6 decimals)
     */

    function openShort(uint256 size, uint256 collateral) external {
        _openPosition(size, collateral, Keys.POSITION_SHORT);
    }

    function increaseSize(uint256 positionId, uint256 size) external {}

    function increaseCollateral(uint256 positionId, uint256 collateral) external {}

    /* --------------------------------- GETTERS -------------------------------- */

    function getAvailableLiquidity() external view returns (uint256) {
        return _calculateAvailableLiquidity();
    }

    function getNetValue() external view returns (uint256) {
        return _calculateNetValue();
    }

    function getTotalPnL() external view returns (int256) {
        return _calculateTotalPnL();
    }

    function getPosition(address trader, uint256 index) external view returns (Position memory) {
        return positions[trader][index];
    }

    function getCollateralPrice() public view returns (int256) {
        return _assetPrice(collateralAsset.priceFeed);
    }

    function getIndexedPrice() public view returns (int256) {
        return _assetPrice(indexToken.priceFeed);
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL FUNCTIONS                             */
    /* -------------------------------------------------------------------------- */
    /* --------------------------------- TRADERS -------------------------------- */

    /**
     * @dev Create a position (long or short)
     * @dev Requirements:
     * - The contract has been approved to transfer the collateral from the trader
     * - The size is higher than the minimum allowed (MIN_POSITION_SIZE)
     * - The collateral is higher than the minimum allowed (MIN_POSITION_COLLATERAL)
     * - The collateral is lower than the size
     * - There is enough liquidity to handle the size (see `_calculateAvailableLiquidity`)
     * - The leverage is lower than the maximum allowed (MAX_LEVERAGE)
     * @dev Effects:
     * - Transfer the collateral to the contract
     * - Update the open interest
     * - Create the position
     * @dev Emits a `Perps_PositionOpened` event
     * @param size The size of the position in USD (6 decimals)
     * @param collateral The amount of collateral deposited to back this position (6 decimals)
     * @param direction The direction of the position (long or short)
     */

    function _openPosition(uint256 size, uint256 collateral, uint256 direction) internal {
        // Revert if the size is too small (less than the minimum allowed)
        if (size < Keys.MIN_POSITION_SIZE) revert Perps_SizeTooSmall(size, Keys.MIN_POSITION_SIZE);
        // Same for the collateral
        if (collateral < Keys.MIN_POSITION_COLLATERAL) {
            revert Perps_NotEnoughCollateral(collateral, Keys.MIN_POSITION_COLLATERAL);
        }

        // @audit-info Is this necessary? Should we allow it somehow?
        // Revert if the collateral is higher than the size
        if (collateral > size) revert Perps_SizeTooSmall(size, collateral);

        // Compare the size to the available liquidity
        uint256 availableLiquidity = _calculateAvailableLiquidity();
        if (size > availableLiquidity) revert Perps_NotEnoughLiquidity(availableLiquidity);

        // Convert the collateral to USD to calculate the leverage with similar units
        // (precision: 1e6 * 1e8 = 14 decimals)
        uint256 collateralInUsd = FixedPointMathLib.fullMulDiv(collateral, uint256(getCollateralPrice()), 1);
        // Compare the leverage to the max leverage
        // (precision: (1e6 * 1e14) / (1e14) = 6 decimals)
        uint256 leverage = FixedPointMathLib.fullMulDivUp(size, 1e14, collateralInUsd);
        // both are 6 decimals
        if (leverage > Keys.MAX_LEVERAGE) revert Perps_LeverageTooHigh(leverage, Keys.MAX_LEVERAGE);

        // Transfer the collateral to the contract
        SafeTransferLib.safeTransferFrom(collateralAsset.token, msg.sender, address(this), collateral);

        // Update the open interest
        uint256 sizeInTokens = _updateOpenInterest(size, direction);

        // Create the position
        positions[msg.sender].push(
            Position({
                size: uint128(size),
                collateral: uint128(collateral),
                sizeInTokens: uint192(sizeInTokens),
                direction: uint8(direction),
                status: uint8(Keys.POSITION_OPEN),
                timestamp: uint48(block.timestamp)
            })
        );

        emit Perps_PositionOpened(msg.sender, size, collateral, direction, leverage);
    }

    function _updatePosition() internal {}

    /**
     * @dev Update the open interest (long or short)
     * @dev This is called each time a position is opened/closed or updated
     * @dev The open interest is calculated in USD and in tokens
     * @dev If a position is being updated, the size will be the additional/substracted amount
     * TODO SEE IF IT IS NOT INCONSISTENT AS IT WILL CALCULATE A DIFFERENT PRICE FOR THE INDEX TOKEN
     * @dev Emits a `Perps_OpenInterestUpdated` event
     * @param size The size of the position in USD (6 decimals)
     * @param direction The direction of the position (long or short)
     */

    function _updateOpenInterest(uint256 size, uint256 direction) internal returns (uint256 sizeInTokens) {
        // Called each time a position is opened/increased (and later decreased/closed to decrease the open interest)
        // (precision: 1e6 * 1e8 / 1e6 = 8 decimals)
        sizeInTokens = FixedPointMathLib.fullMulDiv(size, uint256(getIndexedPrice()), 1e6);

        // Update the open interest
        // @audit-info Here casting uint256 to uint128 might seem dangerous, but there is no way anyone could
        // open a position with a size that would make it overflow
        if (direction == Keys.POSITION_LONG) {
            longOpenInterest.usd = longOpenInterest.usd + uint128(size);
            longOpenInterest.tokens = longOpenInterest.tokens + uint128(sizeInTokens);
        } else {
            shortOpenInterest.usd = shortOpenInterest.usd + uint128(size);
            shortOpenInterest.tokens = shortOpenInterest.tokens + uint128(sizeInTokens);
        }

        emit Perps_OpenInterestUpdated(
            longOpenInterest.usd, longOpenInterest.tokens, shortOpenInterest.usd, shortOpenInterest.tokens
        );
    }

    /* -------------------------------- PROTOCOL -------------------------------- */

    /**
     * @dev Calculate the PnL of a position
     * @param size The size of the position in USD (6 decimals)
     * @param sizeInTokens The size of the position in tokens (8 decimals)
     * @param tokenPrice The price of the token (8 decimals)
     * @param direction The direction of the position (long or short)
     * @return pnl The PnL of the position (6 decimals)
     */

    function _calculatePnL(uint128 size, uint128 sizeInTokens, int256 tokenPrice, uint256 direction)
        internal
        pure
        returns (int256 pnl)
    {
        if (direction == Keys.POSITION_LONG) {
            // PnL of a long position is: (sizeInTokens * indexTokenPrice) - size
            // (precision: (1e8 * 1e8 / 1e10) - 1e6 = 6 decimals)
            pnl =
                int256(FixedPointMathLib.fullMulDivUp(sizeInTokens, uint256(tokenPrice), 1e10)) - int256(uint256(size));
        } else {
            // PnL of a short position is: size - (sizeInTokens * indexTokenPrice)
            // (precision: 1e6 - (1e8 * 1e8 / 1e10) = 6 decimals)
            pnl =
                int256(uint256(size)) - int256(FixedPointMathLib.fullMulDivUp(sizeInTokens, uint256(tokenPrice), 1e10));
        }
    }

    /**
     * @dev Return the total PnL of the protocol in collateral tokens
     * @dev Basically, the flow is:
     * - when opening the position, size == sizeInTokens * tokenPrice
     * - now, size is still the original value, but sizeInTokens * tokenPrice will reflect the current value
     * - so we can just compare both to get the PnL
     * @return totalPnL The accumulated PnL of all positions (6 decimals)
     */

    function _calculateTotalPnL() internal view returns (int256 totalPnL) {
        int256 indexTokenPrice = getIndexedPrice();
        // PnL for long can be interpreted as: (openInterestInTokens * indexTokenPrice) - openInterest
        int256 longPnL =
            _calculatePnL(longOpenInterest.usd, longOpenInterest.tokens, indexTokenPrice, Keys.POSITION_LONG);
        // PnL for short can be interpreted as: openInterest - (openInterestInTokens * indexTokenPrice)
        int256 shortPnL =
            _calculatePnL(shortOpenInterest.usd, shortOpenInterest.tokens, indexTokenPrice, Keys.POSITION_SHORT);

        totalPnL = longPnL + shortPnL;
    }

    /**
     * @dev Return the net value of the protocol in collateral tokens
     * @return netValue The net value of the protocol (6 decimals)
     * Note: Basically, it is the total liquidity minus the total PnL
     */

    function _calculateNetValue() internal view returns (uint256 netValue) {
        // If the total PnL were to be higher than the total liquidity, this would revert
        // Hopefully it should never happen as it would mean that the protocol is rekt

        int256 totalPnL = _calculateTotalPnL();
        // If the PnL is negative, ignore it
        // It does not perfectly reflect the net value but it is what we want here
        // @audit-info Still check if it's accurate and not an issue
        return totalLiquidity - (totalPnL < 0 ? 0 : uint256(_calculateTotalPnL()));
    }

    /**
     * @dev Return the available liquidity in USD
     * Note: We need to do it USD-wise to be able to compare it to the open interest (which is in USD)
     * This results in a lot of oracle requests, but it's the price to pay for more accurate calculations
     * @return availableLiquidity The available liquidity in USD (6 decimals)
     */

    function _calculateAvailableLiquidity() internal view returns (uint256 availableLiquidity) {
        // @audit-info Is it overkill to use the net value here instead of deposited liquidity?
        // (meaning we susbstract the PnL as well)...
        // ... since there is already the exposure ratio applied
        // (shortOpenInterest) + (longOpenInterestInTokens * currentIndexTokenPrice) < (netValue * maxUtilizationPercentage)
        int256 collateralPrice = getCollateralPrice();
        int256 indexTokenPrice = getIndexedPrice();

        /// @audit-info This would apply the exposure ratio to the net value
        // uint256 maxAvailable = (_calculateNetValue() * uint256(collateralPrice) * MAX_EXPOSURE) / 100;
        /// Maybe it's better to apply it to the total liquidity and THEN substract the total PnL
        int256 totalPnL = _calculateTotalPnL();
        uint256 totalPnLNormalized = totalPnL < 0 ? 0 : uint256(totalPnL);
        // (precision: (1e6 * 1e2) / 1e2) - 1e6 = 1e6
        uint256 maxAvailable = FixedPointMathLib.fullMulDiv(totalLiquidity, Keys.MAX_EXPOSURE, 100) - totalPnLNormalized;
        // (precision: ((1e8 * 1e8) + (1e8 * 1e8)) / 1e10) = 1e6
        uint256 currentlyUsed = FixedPointMathLib.divUp(
            (shortOpenInterest.tokens * uint256(collateralPrice)) + (longOpenInterest.tokens * uint256(indexTokenPrice)),
            1e10
        );

        if (maxAvailable > currentlyUsed) {
            availableLiquidity = maxAvailable - currentlyUsed;
            // Here as well, this should not happen, since it would mean that the protocol is insolvent
        } else {
            availableLiquidity = 0;
        }
    }

    /**
     * @dev Enforce the liquidity reserve restrictions
     * @dev Basically check that the new position/liquidity withdrawal does not break the invariants
     * which are calculated in `_calculateAvailableLiquidity`
     * Note: It might be a bit redundant to check it here as well since it's been checked before
     * performing the operations, but it's the most important part of the contract so better safe than sorry
     */

    function _validateLiquidityRestrictions() internal view {
        if (_calculateAvailableLiquidity() == 0) revert Perps_NotEnoughLiquidity(0);
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

    /// @dev Return the total assets of the vault (here the net value)
    /// Meaning that we substract the total PnL from the total liquidity
    function totalAssets() public view override returns (uint256) {
        return _calculateNetValue();
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
        return Keys.DECIMALS_OFFSET;
    }

    /* ---------------------------------- HOOKS --------------------------------- */

    /**
     * @dev Hook that is called before any withdrawal.
     * @param assets The amount of collateral to withdraw
     */

    function _beforeWithdraw(uint256 assets, uint256 /* shares */ ) internal override {
        // Check that the amount is not greater than the available liquidity
        uint256 availableLiquidity = _calculateAvailableLiquidity();
        if (assets > availableLiquidity) revert Perps_NotEnoughLiquidity(availableLiquidity);

        // Update the total liquidity
        unchecked {
            totalLiquidity = totalLiquidity - assets;
        }
    }

    /**
     * @dev Hook that is called after any deposit.
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
