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
    Perps.Asset private indexedAsset;

    /* -------------------------------------------------------------------------- */
    /*                                   ERRORS                                   */
    /* -------------------------------------------------------------------------- */

    // OracleLib
    error OracleLib__StalePrice();
    // SafeTransferLib
    error TransferFromFailed();

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    // ERC4626
    event Deposit(address indexed by, address indexed owner, uint256 assets, uint256 shares);

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    uint256 private constant DEPOSIT_AMOUNT = 1_000e6; // 1,000 USDC

    /* -------------------------------------------------------------------------- */
    /*                                    SETUP                                   */
    /* -------------------------------------------------------------------------- */

    function setUp() external {
        (perps, config) = new PerpsDeploy().run();
        (collateralAsset, indexedAsset,) = config.activeNetworkConfig();
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
    /*                                   ORACLE                                   */
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
}
