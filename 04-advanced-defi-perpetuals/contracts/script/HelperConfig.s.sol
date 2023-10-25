// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";

import {Perps} from "../src/Perps.sol";

import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @dev Here we don't track the price of the collateral (USDC or any dollar-pegged stablecoin).
/// @dev Rather we just assume it's indeed pegged to the dollar...

contract HelperConfig is Script {
    struct NetworkConfig {
        address asset;
        address priceFeed;
        uint8 decimals;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    /// @dev Mock constants for price feeds
    uint8 public constant DECIMALS = 8;
    int256 public constant BTC_USD_PRICE = 30_000e8;

    uint256 public constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            asset: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // WBTC
            priceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // BTC/USD price feed
            decimals: 8,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.asset != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        MockERC20 wbtcMock = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        vm.stopBroadcast();

        return NetworkConfig({
            asset: address(wbtcMock),
            priceFeed: address(btcUsdPriceFeed),
            decimals: DECIMALS,
            deployerKey: ANVIL_DEPLOYER_KEY
        });
    }
}
