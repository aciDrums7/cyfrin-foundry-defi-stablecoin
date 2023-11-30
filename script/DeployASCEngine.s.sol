// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AcidStableCoin} from "../src/AcidStableCoin.sol";
import {ASCEngine} from "../src/ASCEngine.sol";

contract DeployASCEngine is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (AcidStableCoin, ASCEngine) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address wEthUsdPriceFeed,
            address wBtcUsdPriceFeed,
            address wEthContract,
            address wBtcContract,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        tokenAddresses = [wEthContract, wBtcContract];
        priceFeedAddresses = [wEthUsdPriceFeed, wBtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        AcidStableCoin acid = new AcidStableCoin();
        ASCEngine ascEngine = new ASCEngine(tokenAddresses, priceFeedAddresses, address(acid));

        acid.transferOwnership(address(ascEngine));
        vm.stopBroadcast();
        return (acid, ascEngine);
    }
}
