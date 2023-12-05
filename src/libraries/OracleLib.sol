// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author aciDrums7
 * @notice This library is used to check the Chainlink Oracle for stable data.
 * If a price is stable, the function will revert and render the ASCEngine unusable - this is by design
 * We want the ASCEngine to freeze if prices become stale.
 *
 * So if Chainlink network explodes and you have a lot of money locked in the protocol... too bad. (WE'RE SCREWED)
 *
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 seconds

    function staleCheckLatestRoundData(AggregatorV3Interface _priceFeed)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = _priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince >= TIMEOUT) {
            revert OracleLib__StalePrice();
        }
    }
}
