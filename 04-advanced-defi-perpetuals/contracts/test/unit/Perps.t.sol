// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Perps} from "../../src/Perps.sol";
import {PerpsDeploy} from "../../script/PerpsDeploy.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract PerpsTest is Test {
    Perps perps;
    HelperConfig config;

    function setUp() external {
        (perps, config) = new PerpsDeploy().run();
    }
}
