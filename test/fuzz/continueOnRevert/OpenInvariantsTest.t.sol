//* Have our invariant aka properties

//? What are our invariants?

//1. The total supply of ACID should be less than the total value of collateral
//2. Getter view functions should nevert revert <- EVERGREEN INVARIANT

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployASCEngine} from "../../../script/DeployASCEngine.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {AcidStableCoin} from "../../../src/AcidStableCoin.sol";
import {ASCEngine} from "../../../src/ASCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
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

    /* function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to the debt (acid)
        uint256 totalSupply = asc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", wbtcValue);
        console.log("totalSupply: ", totalSupply);

        assert(wethValue + wbtcValue >= totalSupply);
    } */
}
