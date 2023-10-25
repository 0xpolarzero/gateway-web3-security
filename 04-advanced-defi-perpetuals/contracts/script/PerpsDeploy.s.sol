// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";

import {Perps} from "../src/Perps.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract PerpsDeploy is Script {
    function run() external returns (Perps perps, HelperConfig config) {
        vm.startBroadcast();
        config = new HelperConfig();

        (Perps.Asset memory collateralAsset, Perps.Asset memory indexedAsset,) = config.activeNetworkConfig();
        perps = new Perps(collateralAsset, indexedAsset.priceFeed);
        vm.stopBroadcast();
    }
}
