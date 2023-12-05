// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockMoreDebtASC} from "../mocks/MockMoreDebtASC.sol";
import {MockFailedMintAcid} from "../mocks/MockFailedMintAcid.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {DeployASCEngine} from "../../script/DeployASCEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {AcidStableCoin} from "../../src/AcidStableCoin.sol";
import {ASCEngine} from "../../src/ASCEngine.sol";

contract ASCEngineTest is Test {
    uint256 public constant PRICE_FEED_DECIMALS = 1e8;
    int256 public constant PRICE_FEED_UPDATED_ANSWER = 18e8;
    uint256 public constant STARTING_COLLATERAL_BALANCE = 10 ether;
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant ACID_AMOUNT = 100 ether;
    uint256 public constant LIQUIDATION_BONUS = 10;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant DEBT_TO_COVER = 36 ether;

    DeployASCEngine deployer;
    ASCEngine engine;
    AcidStableCoin asc;
    HelperConfig netConf;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("USER");
    address public LIQUIDATOR = makeAddr("LIQUIDATOR");

    function setUp() public {
        deployer = new DeployASCEngine();
        (asc, engine, netConf) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = netConf.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_COLLATERAL_BALANCE);
    }

    modifier collateralDeposited() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier acidMinted() {
        vm.startPrank(USER);
        engine.mintAcid(ACID_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier collateralDepositedAndAcidMinted() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintAcid(weth, COLLATERAL_AMOUNT, ACID_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier liquidated() {
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_COLLATERAL_BALANCE);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateralAndMintAcid(weth, COLLATERAL_AMOUNT, ACID_AMOUNT);
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(PRICE_FEED_UPDATED_ANSWER);
        asc.approve(address(engine), DEBT_TO_COVER);
        engine.liquidate(weth, USER, DEBT_TO_COVER);
        vm.stopPrank();
        _;
    }

    ////////////////////////
    //* Constructor Tests //
    ////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function test_RevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        //1 Arrange
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        //2 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__AllowedTokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new ASCEngine(tokenAddresses, priceFeedAddresses, address(asc));
    }

    function test_SetsPriceFeedsMappingCollateralAddressesAndAcidTokenAddress() public {
        //1 Arrange
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        //2 Act
        ASCEngine testEngine = new ASCEngine(tokenAddresses, priceFeedAddresses, address(asc));
        //3 Assert
        for (uint256 i = 0; i < testEngine.getCollateralTokenAddressLength(); i++) {
            address collateralTokenAddress = testEngine.getCollateralTokenAddress(i);
            assertEq(tokenAddresses[i], collateralTokenAddress);
            assertEq(priceFeedAddresses[i], testEngine.getCollateralPriceFeed(collateralTokenAddress));
        }
        assertEq(address(asc), testEngine.getAcidAddress());
    }

    /////////////////////
    //* Price Tests    //
    /////////////////////
    //TODO: refactor to make it work on any chain! (Using Price Feed)
    function test_GetUsdValue() public {
        //1 Arrange
        uint256 ethAmount = 21e18;
        //2 Act
        uint256 expectedUsd = ethAmount * (uint256(netConf.ETH_USD_PRICE()) / PRICE_FEED_DECIMALS); // 21e18 * $2000 ETH = 4.2e22
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        //3 Assert
        assertEq(expectedUsd, actualUsd);
    }

    function test_GetTokenAmountFromUsd() public {
        //1 Arrange
        uint256 usdAmount = 100 ether; // 100e18
        uint256 expectedWeth = 0.05 ether; // 5e16
        //2 Act
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        //3 Assert
        assertEq(expectedWeth, actualWeth);
    }

    function test_GetAccountTotalCollateralValueReturnsCorrectAmount() public collateralDeposited {
        //1 Arrange
        uint256 expectedTotalCollateralValue = 320000 ether; // 10 ETH + 10 BTC, since 1 ETH = $2000 and 1 BTC = $30000 -> $320,000
        vm.startPrank(USER);
        ERC20Mock(wbtc).mint(USER, COLLATERAL_AMOUNT);
        ERC20Mock(wbtc).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(wbtc, COLLATERAL_AMOUNT);
        //2 Act
        uint256 actualTotalCollateralValue = engine.getAccountTotalCollateralValue(USER);
        //3 Assert
        assertEq(expectedTotalCollateralValue, actualTotalCollateralValue);
    }

    ////////////////////////////////
    //* depositCollateral Tests   //
    ////////////////////////////////
    //! this test needs it's own setup
    function test_DepositCollateralRevertsIfTransferFromFails() public {
        //1 Arrange - Setup
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransferFrom mockWeth = new MockFailedTransferFrom();
        mockWeth.mint(USER, COLLATERAL_AMOUNT);

        tokenAddresses.push(address(mockWeth));
        priceFeedAddresses.push(wethUsdPriceFeed);
        ASCEngine mockEngine = new ASCEngine(tokenAddresses, priceFeedAddresses, address(asc));

        mockWeth.transferOwnership(address(mockEngine));
        vm.stopPrank();
        //2 Arrange - User
        vm.prank(USER);
        mockWeth.approve(address(mockEngine), COLLATERAL_AMOUNT);

        //3 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__TransferFailed.selector);
        vm.prank(USER);
        mockEngine.depositCollateral(address(mockWeth), COLLATERAL_AMOUNT);
    }

    function test_DepositCollateralRevertsIfCollateralZero() public {
        //1 Arrange
        vm.startPrank(USER);
        //2 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_DepositCollateralRevertsWithUnapprovedCollateral() public {
        //1 Arrange
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        //2 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testCanDepositCollateralWithoutMinting() public collateralDeposited {
        uint256 userBalance = asc.balanceOf(USER);
        uint256 expectedBalance = 0;
        assertEq(expectedBalance, userBalance);
    }

    function test_CanDepositCollateralAndGetAccountInfo() public collateralDeposited {
        //1 Arrange
        (uint256 totalAcidMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalAcidMinted = 0;
        //2 Act
        uint256 expectedEthDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        //3 Assert
        assertEq(expectedTotalAcidMinted, totalAcidMinted);
        assertEq(COLLATERAL_AMOUNT, expectedEthDepositAmount);
    }

    function test_DepositCollateralEmitsEvent() public {
        //1 Arrange
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectEmit();
        //2 Act / Assert
        emit ASCEngine.CollateralDeposited(address(USER), weth, COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function test_DepositCollateralRevertsIfTransferNotAllowed() public {
        //1 Arrange
        uint256 currentAllowance = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(engine), currentAllowance, COLLATERAL_AMOUNT
            )
        );
        vm.prank(USER);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
    }

    ///////////////////////////////////////////
    //* depositCollateralAndMintAcid Tests   //
    ///////////////////////////////////////////
    function test_DepositCollateralAndMintAcidRevertsIfHealthFactorIsBroken() public {
        //1 Arrange
        uint256 expectedHealthFactor = 0.5 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        //2 Act / Assert
        vm.expectRevert(abi.encodeWithSelector(ASCEngine.ASCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        // $20,000 ETH * 50% collateralization threshold = $10,000 / 10,000 = 1 health factor
        engine.depositCollateralAndMintAcid(weth, COLLATERAL_AMOUNT, ACID_AMOUNT * 200);
        vm.stopPrank();
    }

    function test_CanDepositCollateralAndMintAcid() public collateralDepositedAndAcidMinted {
        uint256 acidMintedAmount = asc.balanceOf(USER);
        uint256 collateralDepositedAmount = engine.getCollateralDepositedByUserAndTokenAddress(USER, weth);
        assertEq(ACID_AMOUNT, acidMintedAmount);
        assertEq(COLLATERAL_AMOUNT, collateralDepositedAmount);
    }

    /////////////////////
    //* mintAcid Tests //
    /////////////////////
    //! This test needs it's own setup
    function test_MintAcidRevertsIfTransferFails() public {
        //1 Arrange - Setup
        MockFailedMintAcid mockAsc = new MockFailedMintAcid();
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        ASCEngine mockEngine = new ASCEngine(tokenAddresses, priceFeedAddresses, address(mockAsc));
        mockAsc.transferOwnership(address(mockEngine));
        //2 Arrange - USER

        ERC20Mock(weth).mint(USER, COLLATERAL_AMOUNT);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), COLLATERAL_AMOUNT);
        //3 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__MintFailed.selector);
        mockEngine.depositCollateralAndMintAcid(weth, COLLATERAL_AMOUNT, ACID_AMOUNT);
        vm.stopPrank();
    }

    ////////////////////////////////
    //* redeemCollateral Tests   //
    ////////////////////////////////
    //! this test needs it's own setup
    function test_RedeemCollateralRevertsIfTransferFails() public {
        //1 Arrange - Setup
        address owner = msg.sender;
        vm.startPrank(owner);
        MockFailedTransfer mockWeth = new MockFailedTransfer();
        mockWeth.mint(USER, COLLATERAL_AMOUNT);

        tokenAddresses.push(address(mockWeth));
        priceFeedAddresses.push(wethUsdPriceFeed);
        ASCEngine mockEngine = new ASCEngine(tokenAddresses, priceFeedAddresses, address(asc));

        mockWeth.transferOwnership(address(mockEngine));
        vm.stopPrank();
        //2 Arrange - User
        vm.startPrank(USER);
        mockWeth.approve(address(mockEngine), COLLATERAL_AMOUNT);
        mockEngine.depositCollateral(address(mockWeth), COLLATERAL_AMOUNT);
        vm.expectRevert(ASCEngine.ASCEngine__TransferFailed.selector);
        mockEngine.redeemCollateral(address(mockWeth), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function test_CanRedeemCollateralAndGetAccountInfo() public collateralDeposited {
        //1 Arrange
        uint256 expectedCollateralValueInUsd = 0;
        uint256 expectedTotalAcidMinted = 0;
        //2 Act
        vm.prank(USER);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        (uint256 totalAcidMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        //3 Assert
        assertEq(expectedCollateralValueInUsd, collateralValueInUsd);
        assertEq(expectedTotalAcidMinted, totalAcidMinted);
    }

    function test_RedeemCollateralEmitsEvent() public collateralDeposited {
        //1 Arrange
        vm.expectEmit();
        //2 Act / Assert
        emit ASCEngine.CollateralRedeemed(address(USER), address(USER), weth, COLLATERAL_AMOUNT);
        vm.prank(USER);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
    }

    function test_RedeemCollateralRevertsIfHealthFactorIsBroken() public collateralDeposited {
        //1 Arrange
        vm.startPrank(USER);
        engine.mintAcid(ACID_AMOUNT);
        uint256 userHealthFactor = 0; //? 'cause 1 ACID minted and 0 collateral -> 0/1 = 0
        vm.expectRevert(abi.encodeWithSelector(ASCEngine.ASCEngine__BreaksHealthFactor.selector, userHealthFactor));
        //2 Act / Assert
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function test_RedeemCollateralRevertsIfAmountMoreThanBalance() public collateralDeposited {
        //1 Arrange
        uint256 collateralBalance = engine.getCollateralDepositedByUserAndTokenAddress(address(USER), weth);
        vm.expectRevert(
            abi.encodeWithSelector(
                ASCEngine.ASCEngine__AmountMoreThanBalance.selector, collateralBalance, COLLATERAL_AMOUNT + 1
            )
        );
        //2 Act / Assert
        vm.prank(USER);
        engine.redeemCollateral(weth, COLLATERAL_AMOUNT + 1);
    }

    /////////////////////////////////////
    //* redeemCollateralForAcid Tests //
    ///////////////////////////////////
    function test_RedeemCollateralForAcidRevertsIfRedeemingZero() public collateralDepositedAndAcidMinted {
        //1 Arrange
        vm.startPrank(USER);
        asc.approve(address(engine), ACID_AMOUNT);
        //2 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForAcid(weth, 0, ACID_AMOUNT);
        vm.stopPrank();
    }

    function test_RedeemCollateralForAcidRevertsIfTransferingZeroAcid() public collateralDepositedAndAcidMinted {
        //1 Arrange
        vm.startPrank(USER);
        asc.approve(address(engine), ACID_AMOUNT);
        //2 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForAcid(weth, COLLATERAL_AMOUNT, 0);
        vm.stopPrank();
    }

    function test_RedeemCollateralForAcidRevertsIfHealthFactorIsBroken() public collateralDepositedAndAcidMinted {
        //1 Arrange
        uint256 acidToBurn = 1 ether;
        // 0 collateral / ACID_AMOUNT - 1 < 1
        uint256 expectedHealthFactor = 0;
        vm.startPrank(USER);
        asc.approve(address(engine), ACID_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ASCEngine.ASCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.redeemCollateralForAcid(weth, COLLATERAL_AMOUNT, acidToBurn);
        vm.stopPrank();
    }

    function test_CanRedeemCollateralForAcid() public collateralDepositedAndAcidMinted {
        //1 Arrange
        uint256 expectedAcidBalance = 0;
        vm.startPrank(USER);
        asc.approve(address(engine), ACID_AMOUNT);
        //2 Act
        engine.redeemCollateralForAcid(weth, COLLATERAL_AMOUNT, ACID_AMOUNT);
        uint256 actualAcidBalance = asc.balanceOf(USER);
        uint256 actualWethBalance = ERC20Mock(weth).balanceOf(USER);
        //3 Assert
        assertEq(expectedAcidBalance, actualAcidBalance);
        assertEq(STARTING_COLLATERAL_BALANCE, actualWethBalance);
    }

    //////////////////////
    //* burnAcid Tests  //
    //////////////////////
    //! this test needs it's own setup
    function test_BurnAcidRevertsIfTransferFails() public {
        //1 Arrange - Setup
        MockFailedTransferFrom mockAsc = new MockFailedTransferFrom();
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        ASCEngine mockEngine = new ASCEngine(tokenAddresses, priceFeedAddresses, address(mockAsc));
        mockAsc.transferOwnership(address(mockEngine));
        //2 Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, COLLATERAL_AMOUNT);
        ERC20Mock(weth).approve(address(mockEngine), COLLATERAL_AMOUNT);
        mockEngine.depositCollateralAndMintAcid(weth, COLLATERAL_AMOUNT, ACID_AMOUNT);
        //3 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__TransferFailed.selector);
        mockEngine.burnAcid(ACID_AMOUNT);
        vm.stopPrank();
    }

    function test_BurnAcidRevertsIfAmountMoreThanBalance() public collateralDeposited {
        //1 Arrange
        vm.startPrank(USER);
        engine.mintAcid(ACID_AMOUNT);
        uint256 acidMintedAmount = engine.getAcidMinted(address(USER));
        vm.expectRevert(
            abi.encodeWithSelector(
                ASCEngine.ASCEngine__AmountMoreThanBalance.selector, acidMintedAmount, ACID_AMOUNT + 1
            )
        );
        //2 Act / Assert
        engine.burnAcid(ACID_AMOUNT + 1);
        vm.stopPrank();
    }

    function test_BurnAcidSetsTheAcidBalanceToZero() public collateralDeposited acidMinted {
        //1 Arrange
        uint256 initialAcidMinted = engine.getAcidMinted(address(USER));
        uint256 initialAcidBalance = asc.balanceOf(address(USER));
        uint256 expectedFinalAcidBalance = 0;
        //2 Act
        vm.startPrank(USER);
        asc.approve(address(engine), ACID_AMOUNT);
        engine.burnAcid(ACID_AMOUNT);
        vm.stopPrank();
        uint256 finalAcidMinted = engine.getAcidMinted(address(USER));
        uint256 finalAcidBalance = asc.balanceOf(address(USER));
        //3 Assert
        assertEq(initialAcidMinted, initialAcidBalance);
        assertEq(initialAcidBalance, ACID_AMOUNT);
        assertEq(finalAcidMinted, finalAcidBalance);
        assertEq(finalAcidBalance, expectedFinalAcidBalance);
    }

    function test_BurnAcidRevertsIfTransferNotApproved() public collateralDeposited {
        //1 Arrange
        uint256 currentAllowance = 0;
        vm.startPrank(USER);
        engine.mintAcid(ACID_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(engine), currentAllowance, ACID_AMOUNT
            )
        );
        engine.burnAcid(ACID_AMOUNT);
        vm.stopPrank();
    }

    //////////////////////////
    //* healthFactor Tests  //
    //////////////////////////
    function test_HealthFactorIsProperlyReported() public collateralDepositedAndAcidMinted {
        //1 Arrange
        uint256 expectedHealthFactor = 100 ether;
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collateral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function test_HealthFactorCanGoBelowOne() public collateralDepositedAndAcidMinted {
        //1 Arrange
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        //! Rememeber, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 expectedHealthFactor = 0.9 ether;
        // 180 * 50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) = 90 / 100 (ACID_MINTED) = 0.9 healthFactor
        //2 Act
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        //3 Assert
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    ////////////////////////
    //* Liquidation Tests //
    ////////////////////////
    function test_LiquidateRevertsIfDebtToCoverIsZero() public {
        //1 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__NeedsMoreThanZero.selector);
        engine.liquidate(weth, USER, 0);
    }

    function test_LiquidateRevertsIfHealthFactorOk() public collateralDepositedAndAcidMinted {
        //1 Act / Assert
        vm.expectRevert(ASCEngine.ASCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, ACID_AMOUNT);
    }

    function test_LiquidationRedeemIsCorrect() public collateralDepositedAndAcidMinted liquidated {
        //1 Arrange
        uint256 partialReward = engine.getTokenAmountFromUsd(weth, DEBT_TO_COVER);
        uint256 expectedLiquidatorCollateralBalance =
            partialReward + (partialReward * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 expectedUserCollateralDeposited = COLLATERAL_AMOUNT - expectedLiquidatorCollateralBalance;
        //2 Act
        uint256 liquidatorCollateralBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 userCollateralDeposited = engine.getCollateralDepositedByUserAndTokenAddress(USER, weth);
        //3 Assert
        assertEq(expectedLiquidatorCollateralBalance, liquidatorCollateralBalance);
        assertEq(expectedUserCollateralDeposited, userCollateralDeposited);
    }

    function test_LiquidationBurningIsCorrect() public collateralDepositedAndAcidMinted liquidated {
        //1 Arrange
        uint256 expectedBalance = ACID_AMOUNT - DEBT_TO_COVER;
        //2 Act
        uint256 liquidatorAcidBalance = asc.balanceOf(LIQUIDATOR);
        uint256 userAcidMinted = engine.getAcidMinted(USER);
        //3 Assert
        assertEq(expectedBalance, liquidatorAcidBalance);
        assertEq(expectedBalance, userAcidMinted);
    }

    function test_LiquidationImprovesHealthFactor() public collateralDepositedAndAcidMinted liquidated {
        //1 Arrange
        uint256 newHealthFactor = engine.getHealthFactor(USER);
        //2 Assert
        assert(newHealthFactor >= 1);
    }

    //! This test needs it's own setup
    function test_LiquidateRevertsIfHealthFactorNotImproved() public {
        //1 Arrange - Setup
        MockMoreDebtASC mockAsc = new MockMoreDebtASC(wethUsdPriceFeed);
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        ASCEngine mockEngine = new ASCEngine(tokenAddresses, priceFeedAddresses, address(mockAsc));
        mockAsc.transferOwnership(address(mockEngine));

        //2 Arrange - USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), COLLATERAL_AMOUNT);
        mockEngine.depositCollateralAndMintAcid(weth, COLLATERAL_AMOUNT, ACID_AMOUNT);
        vm.stopPrank();

        //3 Arrange - LIQUIDATOR
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_COLLATERAL_BALANCE);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(mockEngine), COLLATERAL_AMOUNT);
        mockEngine.depositCollateralAndMintAcid(weth, COLLATERAL_AMOUNT, ACID_AMOUNT);

        //4 Act / Assert
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(PRICE_FEED_UPDATED_ANSWER);
        mockAsc.approve(address(mockEngine), DEBT_TO_COVER);
        vm.expectRevert(ASCEngine.ASCEngine__HealthFactorNotImproved.selector);
        mockEngine.liquidate(weth, USER, DEBT_TO_COVER);
        vm.stopPrank();
    }
}
