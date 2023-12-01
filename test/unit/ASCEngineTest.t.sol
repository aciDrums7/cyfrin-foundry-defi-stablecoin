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

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address wethAddress;
    address wbtcAddress;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 7 ether;

    function setUp() public {
        deployer = new DeployASCEngine();
        (acid, engine, netConf) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, wethAddress, wbtcAddress,) = netConf.activeNetworkConfig();

        ERC20Mock(wethAddress).mint(USER, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wethAddress).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wethAddress, AMOUNT_COLLATERAL);
        _;
    }

    ////////////////////////
    //* Constructor Tests //
    ////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function test_RevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(wethAddress);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(ASCEngine.ASCEngine__AllowedTokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new ASCEngine(tokenAddresses, priceFeedAddresses, address(acid));
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
        uint256 actualUsd = engine.getUsdValue(wethAddress, ethAmount);

        //3 Assert
        assertEq(expectedUsd, actualUsd);
    }

    function test_GetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether; // 100e18
        uint256 expectedWeth = 0.05 ether; // 5e16
        uint256 actualWeth = engine.getTokenAmountFromUsd(wethAddress, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////
    //* Deposit Collateral Tests  //
    ////////////////////////////////
    function test_RevertsIfCollateralZero() public {
        vm.startPrank(USER);
        vm.expectRevert(ASCEngine.ASCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(wethAddress, 0);
        vm.stopPrank();
    }

    function test_RevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(ASCEngine.ASCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_CanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalAcidMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalAcidMinted = 0;
        uint256 expectedEthDepositAmount = engine.getTokenAmountFromUsd(wethAddress, collateralValueInUsd);
        assertEq(expectedTotalAcidMinted, totalAcidMinted);
        assertEq(AMOUNT_COLLATERAL, expectedEthDepositAmount);
    }
}
