// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DeployASCEngine} from "../../script/DeployASCEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {AcidStableCoin} from "../../src/AcidStableCoin.sol";
import {ASCEngine} from "../../src/ASCEngine.sol";

contract ASCEngineTest is Test {
    uint256 public constant PRICE_FEED_DECIMALS = 1e8;

    DeployASCEngine deployer;
    ASCEngine engine;
    AcidStableCoin acid;
    HelperConfig netConf;

    address wEthUsdPriceFeed;
    address wBtcUsdPriceFeed;
    address wEthContract;
    address wBtcContract;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 7 ether;

    function setUp() public {
        deployer = new DeployASCEngine();
        (acid, engine, netConf) = deployer.run();
        (wEthUsdPriceFeed, wBtcUsdPriceFeed, wEthContract, wBtcContract,) = netConf.activeNetworkConfig();

        ERC20Mock(wEthContract).mint(USER, STARTING_ERC20_BALANCE);
    }

    /////////////////////
    //* Price Tests     //
    /////////////////////
    //TODO: refactor to make it work on any chain! (Using Price Feed)
    function test_GetUsdValue() public {
        //1 Arrange
        uint256 ethAmount = 21e18;

        //2 Act
        uint256 expectedUsd = ethAmount * (uint256(netConf.ETH_USD_PRICE()) / PRICE_FEED_DECIMALS); // 21e18 * $2000 ETH = 4.2e22
        uint256 actualUsd = engine.getUsdValue(wEthContract, ethAmount);

        //3 Assert
        assertEq(actualUsd, expectedUsd);
    }

    ////////////////////////////////
    //* Deposit Collateral Tests  //
    ////////////////////////////////
    function test_RevertsIfCollateralZero() public {
        vm.startPrank(USER);
        vm.expectRevert(ASCEngine.ASCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(wEthContract, 0);
        vm.stopPrank();
    }
}
