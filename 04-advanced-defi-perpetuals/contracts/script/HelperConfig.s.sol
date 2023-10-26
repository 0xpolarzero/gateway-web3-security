// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";

import {Perps} from "../src/Perps.sol";
import {Keys} from "../src/libraries/Keys.sol";

import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @dev Here we don't track the price of the collateral (USDC or any dollar-pegged stablecoin).
/// @dev Rather we just assume it's indeed pegged to the dollar...

contract HelperConfig is Script {
    struct NetworkConfig {
        Perps.Asset collateralAsset;
        Perps.Asset indexAsset;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    /// @dev Mock constants for price feeds
    uint8 public constant DECIMALS_NON_ETH_PAIR = 8;
    int256 public constant BTC_USD_PRICE = 30_000e8;
    int256 public constant USDC_USD_PRICE = 1e8;

    uint256 public constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public returns (NetworkConfig memory) {
        MockERC20 usdcMock = new MockERC20("USDC", "USDC", Keys.COLLATERAL_TOKEN_DECIMALS);

        return NetworkConfig({
            collateralAsset: Perps.Asset({
                token: address(usdcMock), // USDC (mock)
                priceFeed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E, // USDC/USD
                decimals: Keys.COLLATERAL_TOKEN_DECIMALS // USDC has 6 decimals, we don't mean the decimals of the value returned by the price feed
            }),
            indexAsset: Perps.Asset({
                token: address(0), // We don't need the actual token (which would be WBTC in any case)
                priceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // BTC/USD
                decimals: 0 // We don't need this as well
            }),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.collateralAsset.token != address(0)) {
            return activeNetworkConfig;
        }

        MockERC20 usdcMock = new MockERC20("USDC", "USDC", Keys.COLLATERAL_TOKEN_DECIMALS);
        MockV3Aggregator usdcUsdPriceFeed = new MockV3Aggregator(DECIMALS_NON_ETH_PAIR, USDC_USD_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS_NON_ETH_PAIR, BTC_USD_PRICE);

        return NetworkConfig({
            collateralAsset: Perps.Asset({
                token: address(usdcMock), // USDC (mock)
                priceFeed: address(usdcUsdPriceFeed), // USDC/USD
                decimals: Keys.COLLATERAL_TOKEN_DECIMALS // USDC has 6 decimals, we don't mean the decimals of the value returned by the price feed
            }),
            indexAsset: Perps.Asset({
                token: address(0), // We don't need the actual token (which would be WBTC in any case)
                priceFeed: address(btcUsdPriceFeed), // BTC/USD
                decimals: 0 // We don't need this as well
            }),
            deployerKey: ANVIL_DEPLOYER_KEY
        });
    }
}
