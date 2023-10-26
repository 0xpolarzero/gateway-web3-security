// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

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

    // OracleLib
    error OracleLib__StalePrice();
    // SafeTransferLib
    error TransferFromFailed();
    // ERC4626
    error WithdrawMoreThanMax();

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    // ERC4626
    event Deposit(address indexed by, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed by, address indexed to, address indexed owner, uint256 assets, uint256 shares);

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */
    /* -------------------------------- CONSTANTS ------------------------------- */

    uint256 private constant DEPOSIT_AMOUNT = 1_000e6; // 1,000 USDC

    address private constant ALICE = address(1);
    address private constant BOB = address(2);

    /* -------------------------------- VARIABLES ------------------------------- */

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

    modifier depositedLiquidity() {
        MockERC20(address(collateralAsset.token)).mint(address(this), DEPOSIT_AMOUNT);
        IERC20(address(collateralAsset.token)).approve(address(perps), DEPOSIT_AMOUNT);
        perps.depositLiquidity(DEPOSIT_AMOUNT);
        _;
    }

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

    modifier withdrawnLiquidity() {
        // Calculate available liquidity
        uint256 availableLiquidity = perps.getAvailableLiquidity();
        withdrawnLiquidityAmount = availableLiquidity / 2;

        // Withdraw liquidity
        perps.withdrawLiquidity(withdrawnLiquidityAmount);
        _;
    }

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
    /*                                  OracleLib                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Return the correct price from the oracle
    function test_OracleLib_returnsCorrectPrice() external {
        int256 answer = 20_000e8;
        MockV3Aggregator(collateralAsset.priceFeed).updateAnswer(answer);
        int256 price = perps.getCollateralPrice();
        assert(price == answer);
    }

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

    function _depositLiquidityAs(address provider, uint256 amount) private {
        MockERC20(address(collateralAsset.token)).mint(provider, amount);
        vm.startPrank(provider);
        IERC20(address(collateralAsset.token)).approve(address(perps), amount);
        perps.depositLiquidity(amount);
        vm.stopPrank();
    }
}
