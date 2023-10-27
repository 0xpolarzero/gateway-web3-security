// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {PerpsDeploy} from "../../script/PerpsDeploy.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {Perps} from "../../src/Perps.sol";
import {Keys} from "../../src/libraries/Keys.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import {IERC20} from "../../src/interfaces/IERC20.sol";

contract PerpsTest is Test {
    Perps private perps;
    HelperConfig private config;
    Perps.Asset private collateralAsset;
    Perps.Asset private indexAsset;

    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev OracleLib
    error OracleLib__StalePrice();
    /// @dev SafeTransferLib
    error TransferFromFailed();
    /// @dev ERC4626
    error WithdrawMoreThanMax();

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Perps
    event Perps_PositionOpened(
        address indexed trader, uint256 size, uint256 collateral, uint256 direction, uint256 leverage
    );

    /// @dev ERC4626
    event Deposit(address indexed by, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed by, address indexed to, address indexed owner, uint256 assets, uint256 shares);

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */
    /* -------------------------------- CONSTANTS ------------------------------- */

    /// @dev Liquidity
    uint256 private constant DEPOSIT_AMOUNT = 1_000e6; // 1,000 USDC

    /// @dev Position
    uint256 private constant POSITION_SIZE = 100e6; // 100 USDC
    uint256 private constant POSITION_COLLATERAL = 10e6; // 10 USDC

    /// @dev Users
    address private constant ALICE = address(1);
    address private constant BOB = address(2);

    /* -------------------------------- VARIABLES ------------------------------- */

    /// @dev Liquidity
    uint256 withdrawnLiquidityAmount;

    /* -------------------------------------------------------------------------- */
    /*                                    SETUP                                   */
    /* -------------------------------------------------------------------------- */

    function setUp() external {
        (perps, config) = new PerpsDeploy().run();
        (collateralAsset, indexAsset,) = config.activeNetworkConfig();
    }

    /* -------------------------------------------------------------------------- */
    /*                              depositLiquidity                              */
    /* -------------------------------------------------------------------------- */

    /// @dev Liquidity was deposited
    modifier depositedLiquidity() {
        MockERC20(address(collateralAsset.token)).mint(address(this), DEPOSIT_AMOUNT);
        IERC20(address(collateralAsset.token)).approve(address(perps), DEPOSIT_AMOUNT);
        perps.depositLiquidity(DEPOSIT_AMOUNT);
        _;
    }

    /* --------------------------------- SUCCESS -------------------------------- */

    /// @dev Transfer the collateral to the contract
    function test_depositLiquidity_transfersCollateralToContract() external depositedLiquidity {
        // Check the balance of the contract
        uint256 balance = IERC20(address(collateralAsset.token)).balanceOf(address(perps));
        assert(balance == DEPOSIT_AMOUNT);
    }

    /// @dev Update the total liquidity
    function test_depositLiquidity_updatesTotalLiquidity() external depositedLiquidity {
        // Check the total liquidity
        uint256 totalLiquidity = perps.totalLiquidity();
        assert(totalLiquidity == DEPOSIT_AMOUNT);
    }

    /// @dev Emit the event with correct parameters
    function test_depositLiquidity_emitsEvent() external {
        MockERC20(address(collateralAsset.token)).mint(address(this), DEPOSIT_AMOUNT);
        IERC20(address(collateralAsset.token)).approve(address(perps), DEPOSIT_AMOUNT);

        uint256 expectedShares = perps.convertToShares(DEPOSIT_AMOUNT);

        // Check the event
        vm.expectEmit();
        // by, owner, assets, shares
        // by & owner are the same address
        // (we could provide a different owner to mint the shares to an arbitrary address)
        emit Deposit(address(this), address(this), DEPOSIT_AMOUNT, expectedShares);
        perps.depositLiquidity(DEPOSIT_AMOUNT);
    }

    /* --------------------------------- REVERT --------------------------------- */

    /// @dev Revert if the amount is zero
    function test_depositLiquidity_revertsIfAmountZero() external {
        vm.expectRevert(Perps.Perps_ZeroValueNotAllowed.selector);
        perps.depositLiquidity(0);
    }

    /// @dev Revert if not enough balance
    function test_depositLiquidity_revertsIfNotEnoughBalance() external {
        IERC20(address(collateralAsset.token)).approve(address(perps), DEPOSIT_AMOUNT);

        // Since the vault is using SafeTransferLib, it will revert with the signature
        // of TransferFromFailed()
        vm.expectRevert(TransferFromFailed.selector);
        perps.depositLiquidity(DEPOSIT_AMOUNT);
    }

    /// @dev Revert if not enough allowance
    function test_depositLiquidity_revertsIfNotEnoughAllowance() external {
        // We're using a mock ERC20 that allows us to mint any amount of tokens
        MockERC20(address(collateralAsset.token)).mint(address(this), DEPOSIT_AMOUNT);
        IERC20(address(collateralAsset.token)).approve(address(perps), DEPOSIT_AMOUNT);

        // Same here, the vault will revert with the signature of TransferFromFailed()
        vm.expectRevert(TransferFromFailed.selector);
        perps.depositLiquidity(DEPOSIT_AMOUNT + 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                              withdrawLiquidity                             */
    /* -------------------------------------------------------------------------- */

    /// @dev Liquidity was withdrawn
    modifier withdrawnLiquidity() {
        // Calculate available liquidity
        uint256 availableLiquidity = perps.getAvailableLiquidity();
        withdrawnLiquidityAmount = availableLiquidity / 2;

        // Withdraw liquidity
        perps.withdrawLiquidity(withdrawnLiquidityAmount);
        _;
    }

    /* --------------------------------- SUCCESS -------------------------------- */

    /// @dev Transfer the collateral back to the provider
    function test_withdrawLiquidity_transfersCollateralBackToProvider()
        external
        depositedLiquidity
        withdrawnLiquidity
    {
        // Check the balance of the provider
        uint256 balance = IERC20(address(collateralAsset.token)).balanceOf(address(this));
        assert(balance == withdrawnLiquidityAmount);
    }

    /// @dev Update the total liquidity
    function test_withdrawLiquidity_updatesTotalLiquidity() external depositedLiquidity withdrawnLiquidity {
        // Check the total liquidity
        uint256 totalLiquidity = perps.totalLiquidity();
        assert(totalLiquidity == DEPOSIT_AMOUNT - withdrawnLiquidityAmount);
    }

    /// @dev Emit the event with correct parameters
    function test_withdrawLiquidity_emitsEvent() external depositedLiquidity withdrawnLiquidity {
        // Shares are the same as the amount withdrawn (since there is only one provider) * decimals offset
        uint256 expectedShares = withdrawnLiquidityAmount * 10 ** Keys.DECIMALS_OFFSET;

        // Check the event
        vm.expectEmit();
        // by, to, owner, assets, shares
        // by, to & owner are the same address
        emit Withdraw(address(this), address(this), address(this), withdrawnLiquidityAmount, expectedShares);
        perps.withdrawLiquidity(withdrawnLiquidityAmount);
    }

    /* --------------------------------- REVERT --------------------------------- */

    /// @dev Revert if the amount is zero
    function test_withdrawLiquidity_revertsIfAmountZero() external depositedLiquidity {
        vm.expectRevert(Perps.Perps_ZeroValueNotAllowed.selector);
        perps.withdrawLiquidity(0);
    }

    /// @dev Revert when trying to withdraw more than available for a provider
    function test_withdrawLiquidity_revertsIfMoreThanShares() external depositedLiquidity {
        // Deposit more liquidity as another provider
        _depositLiquidityAs(ALICE, DEPOSIT_AMOUNT * 10);

        vm.expectRevert(WithdrawMoreThanMax.selector);
        perps.withdrawLiquidity(DEPOSIT_AMOUNT + 1);
    }

    /// @dev Revert if there is not enough available liquidity
    function test_withdrawLiquidity_revertsIfNotEnoughAvailableLiquidity() external depositedLiquidity {
        // Calculate the max amount of liquidity that can be withdrawn
        // Basically: (total liquidity * max exposure percentage) - totalPnL - currently used
        // currently used = total open interest
        uint256 maxAmount = perps.getAvailableLiquidity();

        vm.expectRevert(abi.encodeWithSelector(Perps.Perps_NotEnoughLiquidity.selector, maxAmount));
        perps.withdrawLiquidity(maxAmount + 1);
    }

    /* -------------------------------------------------------------------------- */
    /*                             openLong/openShort                             */
    /* -------------------------------------------------------------------------- */

    /// @dev Collateral was minted and approved
    modifier hasCollateral() {
        MockERC20(address(collateralAsset.token)).mint(address(this), POSITION_COLLATERAL * 2);
        IERC20(address(collateralAsset.token)).approve(address(perps), POSITION_COLLATERAL * 2);
        _;
    }

    /// @dev Long position was opened
    modifier openedLong() {
        // Deposit the right amount of liquidity
        _depositLiquidityAs(ALICE, _calculateRequiredDepositForAvailableLiquidity(POSITION_SIZE));

        // Open the position
        perps.openLong(POSITION_SIZE, POSITION_COLLATERAL);
        _;
    }

    /// @dev Short position was opened
    modifier openedShort() {
        // Deposit the right amount of liquidity
        _depositLiquidityAs(ALICE, _calculateRequiredDepositForAvailableLiquidity(POSITION_SIZE));

        // Open the position
        perps.openShort(POSITION_SIZE, POSITION_COLLATERAL);
        _;
    }

    /* --------------------------------- SUCCESS -------------------------------- */

    /// @dev Transfer the collateral to the contract
    function test_openLong_transfersCollateralToContract() external hasCollateral openedLong {
        // Check the balance of the contract
        uint256 balance = IERC20(address(collateralAsset.token)).balanceOf(address(perps));
        assert(balance == POSITION_COLLATERAL + perps.totalLiquidity());
    }

    /// @dev Update the total open interest
    function test_openLong_updatesTotalOpenInterest() external hasCollateral openedLong openedShort {
        // Check the total open interest
        (uint256 longOpenInterest, uint256 longOpenInterestTokens) = perps.longOpenInterest();
        (uint256 shortOpenInterest, uint256 shortOpenInterestTokens) = perps.shortOpenInterest();
        uint256 sizeInTokens = FixedPointMathLib.fullMulDiv(POSITION_SIZE, uint256(perps.getIndexedPrice()), 1e6);

        assert(longOpenInterest == POSITION_SIZE);
        assert(longOpenInterestTokens == sizeInTokens);

        assert(shortOpenInterest == POSITION_SIZE);
        assert(shortOpenInterestTokens == sizeInTokens);
    }

    /// @dev Add the position to the mapping
    function test_openLong_addsPositionToMappingLong() external hasCollateral openedLong openedShort {
        uint256 sizeInTokens = FixedPointMathLib.fullMulDiv(POSITION_SIZE, uint256(perps.getIndexedPrice()), 1e6);

        Perps.Position[] memory positions = new Perps.Position[](2);
        positions[0] = perps.getPosition(address(this), 0);
        positions[1] = perps.getPosition(address(this), 1);

        assert(positions[0].size == POSITION_SIZE);
        assert(positions[0].collateral == POSITION_COLLATERAL);
        assert(positions[0].sizeInTokens == sizeInTokens);
        assert(positions[0].direction == Keys.POSITION_LONG);
        assert(positions[0].status == Keys.POSITION_OPEN);
        assert(positions[0].timestamp == block.timestamp);

        assert(positions[1].size == POSITION_SIZE);
        assert(positions[1].collateral == POSITION_COLLATERAL);
        assert(positions[1].sizeInTokens == sizeInTokens);
        assert(positions[1].direction == Keys.POSITION_SHORT);
        assert(positions[1].status == Keys.POSITION_OPEN);
        assert(positions[1].timestamp == block.timestamp);
    }

    /// @dev Emit the event with correct parameters
    function test_openLong_emitsEvent() external hasCollateral {
        // Deposit the right amount of liquidity
        _depositLiquidityAs(ALICE, _calculateRequiredDepositForAvailableLiquidity(POSITION_SIZE));

        // Calculate the leverage
        uint256 collateralInUsd =
            FixedPointMathLib.fullMulDiv(POSITION_COLLATERAL, uint256(perps.getCollateralPrice()), 1);
        uint256 leverage = FixedPointMathLib.fullMulDivUp(POSITION_SIZE, 1e14, collateralInUsd);

        // Check the event
        vm.expectEmit();
        // trader, size, collateral, direction, leverage
        emit Perps_PositionOpened(address(this), POSITION_SIZE, POSITION_COLLATERAL, Keys.POSITION_LONG, leverage);
        perps.openLong(POSITION_SIZE, POSITION_COLLATERAL);
    }

    /* --------------------------------- REVERT --------------------------------- */

    /// @dev Revert if not enough collateral balance
    function test_openLong_revertsIfNotEnoughBalance() external depositedLiquidity {
        // Long
        vm.expectRevert(TransferFromFailed.selector);
        perps.openLong(POSITION_SIZE, POSITION_COLLATERAL);

        // Short
        vm.expectRevert(TransferFromFailed.selector);
        perps.openShort(POSITION_SIZE, POSITION_COLLATERAL);
    }

    /// @dev Revert if not enough collateral allowance
    function test_openLong_revertsIfNotEnoughAllowance() external depositedLiquidity {
        MockERC20(address(collateralAsset.token)).mint(address(this), POSITION_COLLATERAL * 2);
        IERC20(address(collateralAsset.token)).approve(address(perps), POSITION_COLLATERAL);

        // Long
        vm.expectRevert(TransferFromFailed.selector);
        perps.openLong(POSITION_SIZE, POSITION_COLLATERAL + 1);

        // Short
        vm.expectRevert(TransferFromFailed.selector);
        perps.openShort(POSITION_SIZE, POSITION_COLLATERAL + 1);
    }

    /// @dev Revert if the size is lower than the minimum allowed
    function test_openLong_revertsIfSizeLowerThanMinimum() external depositedLiquidity hasCollateral {
        bytes memory errorSelector =
            abi.encodeWithSelector(Perps.Perps_SizeTooSmall.selector, 1, Keys.MIN_POSITION_SIZE);
        // Long
        vm.expectRevert(errorSelector);
        perps.openLong(1, POSITION_COLLATERAL);

        // Short
        vm.expectRevert(errorSelector);
        perps.openShort(1, POSITION_COLLATERAL);
    }

    /// @dev Revert if the collateral is lower than the minimum allowed
    function test_openLong_revertsIfCollateralLowerThanMinimum() external depositedLiquidity hasCollateral {
        bytes memory errorSelector =
            abi.encodeWithSelector(Perps.Perps_NotEnoughCollateral.selector, 1, Keys.MIN_POSITION_COLLATERAL);

        // Long
        vm.expectRevert(errorSelector);
        perps.openLong(POSITION_SIZE, 1);

        // Short
        vm.expectRevert(errorSelector);
        perps.openShort(POSITION_SIZE, 1);
    }

    /// @dev Revert if the size is lower than the collateral
    function test_openLong_revertsIfSizeLowerThanCollateral() external depositedLiquidity hasCollateral {
        bytes memory errorSelector = abi.encodeWithSelector(
            Perps.Perps_SizeTooSmall.selector, Keys.MIN_POSITION_SIZE, Keys.MIN_POSITION_SIZE + 1
        );

        // Long
        vm.expectRevert(errorSelector);
        perps.openLong(Keys.MIN_POSITION_SIZE, Keys.MIN_POSITION_SIZE + 1);

        // Short
        vm.expectRevert(errorSelector);
        perps.openShort(Keys.MIN_POSITION_SIZE, Keys.MIN_POSITION_SIZE + 1);
    }

    /// @dev Revert if there is not enough liquidity
    function test_openLong_revertsIfNotEnoughLiquidity() external depositedLiquidity {
        // Calculate the max amount of liquidity that can be withdrawn
        uint256 maxAmount = perps.getAvailableLiquidity();

        // Mint/approve it
        MockERC20(address(collateralAsset.token)).mint(address(this), maxAmount);
        IERC20(address(collateralAsset.token)).approve(address(perps), maxAmount);

        // Long
        vm.expectRevert(abi.encodeWithSelector(Perps.Perps_NotEnoughLiquidity.selector, maxAmount));
        perps.openLong(maxAmount + 1, maxAmount);

        // Short
        vm.expectRevert(abi.encodeWithSelector(Perps.Perps_NotEnoughLiquidity.selector, maxAmount));
        perps.openShort(maxAmount + 1, maxAmount);
    }

    /// @dev Revert if the leverage exceeds the max allowed
    function test_openLong_revertsIfLeverageTooHigh() external {
        // Calculate the size to exceed the max leverage
        uint256 size = POSITION_COLLATERAL * Keys.MAX_LEVERAGE + 1;
        uint256 collateralInUsd =
            FixedPointMathLib.fullMulDiv(POSITION_COLLATERAL, uint256(perps.getCollateralPrice()), 1);
        uint256 leverage = FixedPointMathLib.fullMulDivUp(size, 1e14, collateralInUsd);

        // Deposit the right amount of liquidity
        _depositLiquidityAs(ALICE, _calculateRequiredDepositForAvailableLiquidity(size));

        bytes memory errorSelector =
            abi.encodeWithSelector(Perps.Perps_LeverageTooHigh.selector, leverage, Keys.MAX_LEVERAGE);

        // Long
        vm.expectRevert(errorSelector);
        perps.openLong(size, POSITION_COLLATERAL);

        // Short
        vm.expectRevert(errorSelector);
        perps.openShort(size, POSITION_COLLATERAL);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  OracleLib                                 */
    /* -------------------------------------------------------------------------- */
    /* --------------------------------- SUCCESS -------------------------------- */

    /// @dev Return the correct price from the oracle
    function test_OracleLib_returnsCorrectPrice() external {
        int256 answer = 20_000e8;
        MockV3Aggregator(collateralAsset.priceFeed).updateAnswer(answer);
        int256 price = perps.getCollateralPrice();
        assert(price == answer);
    }

    /* --------------------------------- REVERT --------------------------------- */

    /// @dev Revert if the price is stale (exceeds the max timeout)
    function test_OracleLib_revertsIfStalePrice() external {
        int256 answer = 20_000e8;
        MockV3Aggregator(collateralAsset.priceFeed).updateAnswer(answer);

        vm.warp(block.timestamp + Keys.MAX_ORACLE_RESPONSE_TIMEOUT + 1);
        vm.expectRevert(OracleLib__StalePrice.selector);
        perps.getCollateralPrice();
    }

    /* -------------------------------------------------------------------------- */
    /*                              HELPER FUNCTIONS                              */
    /* -------------------------------------------------------------------------- */

    /// @dev Deposit liquidity with a specified address
    function _depositLiquidityAs(address provider, uint256 amount) private {
        MockERC20(address(collateralAsset.token)).mint(provider, amount);
        vm.startPrank(provider);
        IERC20(address(collateralAsset.token)).approve(address(perps), amount);
        perps.depositLiquidity(amount);
        vm.stopPrank();
    }

    /// @dev Calculate the required deposit to achieve a certain amount of available liquidity
    function _calculateRequiredDepositForAvailableLiquidity(uint256 targetLiquidity)
        internal
        view
        returns (uint256 requiredDeposit)
    {
        int256 collateralPrice = perps.getCollateralPrice();
        int256 indexTokenPrice = perps.getIndexedPrice();
        (, uint256 shortOpenInterestTokens) = perps.shortOpenInterest();
        (, uint256 longOpenInterestTokens) = perps.longOpenInterest();

        int256 totalPnL = perps.getTotalPnL();
        uint256 totalPnLNormalized = totalPnL < 0 ? 0 : uint256(totalPnL);

        // Calculate the total used liquidity
        uint256 currentlyUsed = FixedPointMathLib.divUp(
            (shortOpenInterestTokens * uint256(collateralPrice)) + (longOpenInterestTokens * uint256(indexTokenPrice)),
            1e10
        );

        // We know that availableLiquidity = FixedPointMathLib.fullMulDiv(totalLiquidity, Keys.MAX_EXPOSURE, 100) - totalPnLNormalized - currentlyUsed;
        // availableLiquidity = totalLiquidity * Keys.MAX_EXPOSURE / 100 - totalPnLNormalized - currentlyUsed
        // requiredDeposit = (availableLiquidity + totalPnLNormalized + currentlyUsed) * 100 / Keys.MAX_EXPOSURE
        requiredDeposit =
            FixedPointMathLib.mulDivUp(targetLiquidity + totalPnLNormalized + currentlyUsed, 100, Keys.MAX_EXPOSURE);
    }
}
