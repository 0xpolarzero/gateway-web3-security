// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Keys} from "./Keys.sol";

/// @dev Check the Chainlink oracle for stale data.
/// @dev It revert if it happens to "freeze" everything.

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = Keys.MAX_ORACLE_RESPONSE_TIMEOUT;

    function staleCheckLatestRoundData(address _priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundID, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            AggregatorV3Interface(_priceFeed).latestRoundData();

        uint256 timeSinceLastUpdate = block.timestamp - updatedAt;
        if (timeSinceLastUpdate > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundID, answer < 0 ? int256(0) : answer, startedAt, updatedAt, answeredInRound);
    }
}
