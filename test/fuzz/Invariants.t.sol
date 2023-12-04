// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployASCEngine} from "../../script/DeployASCEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {AcidStableCoin} from "../../src/AcidStableCoin.sol";
import {ASCEngine} from "../../src/ASCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariants is StdInvariant, Test {
    DeployASCEngine deployer;
    ASCEngine engine;
    AcidStableCoin asc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployASCEngine();
        (asc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(engine));
    }
}
