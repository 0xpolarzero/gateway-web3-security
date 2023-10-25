// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {PerpsDeploy} from "../../script/PerpsDeploy.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {Perps} from "../../src/Perps.sol";
import {Keys} from "../../src/libraries/Keys.sol";

import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract PerpsTest is Test {
    error OracleLib__StalePrice();

    Perps private perps;
    HelperConfig private config;
    Perps.Asset private collateralAsset;
    Perps.Asset private indexedAsset;

    function setUp() external {
        (perps, config) = new PerpsDeploy().run();
        (collateralAsset, indexedAsset,) = config.activeNetworkConfig();
    }

    /* -------------------------------------------------------------------------- */
    /*                                   ORACLE                                   */
    /* -------------------------------------------------------------------------- */

    function test_OracleLib_success() external {
        int256 answer = 20_000e8;
        MockV3Aggregator(collateralAsset.priceFeed).updateAnswer(answer);
        int256 price = perps.getCollateralPrice();
        assert(price == answer);
    }

    function test_OracleLib_revertIfStalePrice() external {
        int256 answer = 20_000e8;
        MockV3Aggregator(collateralAsset.priceFeed).updateAnswer(answer);

        vm.warp(block.timestamp + Keys.MAX_ORACLE_RESPONSE_TIMEOUT + 1);
        vm.expectRevert(OracleLib__StalePrice.selector);
        perps.getCollateralPrice();
    }
}
