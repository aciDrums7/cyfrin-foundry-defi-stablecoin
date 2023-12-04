// SPDX-License-Identifier: MIT

// Layout of Address:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.20;

import {AcidStableCoin} from "./AcidStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";

/**
 * @title ACIDEngine
 * @author aciDrums7
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC.
 *
 * Our  ACID system should always be "overcollateralized". At no point, should the value of all collateral <= the $ backed value of all ACID.
 *
 * @notice This contract is the core of the ACID System. It handles all the logic for minting and redeeming ACID, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract ASCEngine is ReentrancyGuard {
    /////////////////////
    //* Errors         //
    /////////////////////
    error ASCEngine__NeedsMoreThanZero();
    error ASCEngine__AllowedTokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error ASCEngine__NotAllowedToken();
    error ASCEngine__TransferFailed();
    error ASCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error ASCEngine__MintFailed();
    error ASCEngine__HealthFactorOk();
    error ASCEngine__HealthFactorNotImproved();
    error ASCEngine__AmountMoreThanBalance(uint256 balance, uint256 amount);

    ////////////////////////
    //* State Variables   //
    ////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant DECIMAL_PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //! 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means a 10% bonus

    mapping(address tokenAddress => address priceFeedAddress) private s_priceFeeds;
    mapping(address user => mapping(address tokenAddress => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 acidMintedAmount) private s_ACIDMinted;
    address[] private s_collateralTokensAddresses;

    AcidStableCoin private immutable i_acid;

    /////////////////////
    //* Events         //
    /////////////////////
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed tokenAddress, uint256 amount
    );

    /////////////////////
    //* Modifiers      //
    /////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert ASCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert ASCEngine__NotAllowedToken();
        }
        _;
    }

    modifier checkUnderflow(uint256 _balance, uint256 _amount) {
        if (_amount > _balance) {
            revert ASCEngine__AmountMoreThanBalance(_balance, _amount);
        }
        _;
    }

    /////////////////////
    //* Functions      //
    /////////////////////
    constructor(address[] memory _allowedTokenAddresses, address[] memory _priceFeedAddresses, address _acidAddress) {
        //* USD Price Feeds
        if (_allowedTokenAddresses.length != _priceFeedAddresses.length) {
            revert ASCEngine__AllowedTokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        //* For example, ETH / USD, BTC / USD...
        for (uint256 i = 0; i < _allowedTokenAddresses.length; i++) {
            s_priceFeeds[_allowedTokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokensAddresses.push(_allowedTokenAddresses[i]);
        }
        i_acid = AcidStableCoin(_acidAddress);
    }

    /////////////////////////
    //* External Functions //
    /////////////////////////
    /**
     *
     * @param _tokenAddress The address of the token to deposit as collateral
     * @param _collateralAmount The amount of the collateral to deposit
     * @param _acidToMintAmount The amount of ACID to mint
     * @notice This function will deposit your collateral and mint your ACID in one transaction
     */
    function depositCollateralAndMintAcid(address _tokenAddress, uint256 _collateralAmount, uint256 _acidToMintAmount)
        external
    {
        depositCollateral(_tokenAddress, _collateralAmount);
        mintAcid(_acidToMintAmount);
    }

    /**
     * @param _tokenAddress The address of the token collateral
     * @param _collateralAmount The amount of token collateral to redeem
     * @param _amountAcidToBurn The amount of ACID to burn
     * This function burns ACID and redeems underlying collateral in one transaction
     */
    function redeemCollateralForAcid(address _tokenAddress, uint256 _collateralAmount, uint256 _amountAcidToBurn)
        external
    {
        burnAcid(_amountAcidToBurn);
        redeemCollateral(_tokenAddress, _collateralAmount);
        // redeemCollateral altready checks health factor
    }

    // If we do start nearing undercollateralization, we need someone to liquidate our positions
    // $100 ETH backing $50 ACID
    // $20 ETH back $50 ACID <- ACID isn't worth $1!!!

    // $75 backing $50 ACID
    // Liquidator take $75 backing and burns off the $50 ACID -> Our protocol stays overcollateralized

    // If someone is almost undercollateralized, we'll pay you to liquidate them!
    /**
     *
     * @param _tokenAddress The ERC20 collateral address to liquidate from the user
     * @param _userToLiquidate The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param _debtToCoverInUsd The amount of ACID you want to burn to improve the user health factor
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function assumes the protocol will be roughly 200% collateralized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentive the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(address _tokenAddress, address _userToLiquidate, uint256 _debtToCoverInUsd)
        external
        moreThanZero(_debtToCoverInUsd)
        nonReentrant
    {
        // Need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(_userToLiquidate);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert ASCEngine__HealthFactorOk();
        }
        // We want to burn their ACID "debt"
        // And take their collateral
        // Bad User: $140 ETH, $100 ACID
        // debtToCover = $100
        // $100 ACID = ??? ETH?
        uint256 tokenAmountFromDebtToCover = getTokenAmountFromUsd(_tokenAddress, _debtToCoverInUsd);
        // And give them a 10% collateral bonus
        // So we are giving the liquidator (tokenAmountFromDebtToCover + 10%) for $100 ACID
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtToCover * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtToCover + bonusCollateral;
        _redeemCollateral(_tokenAddress, totalCollateralToRedeem, _userToLiquidate, msg.sender);
        _burnAcid(_debtToCoverInUsd, _userToLiquidate, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(_userToLiquidate);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert ASCEngine__HealthFactorNotImproved();
        }
    }

    ////////////////////////
    //* Public  Functions //
    ////////////////////////
    /**
     * @notice follows CEI
     * @param _tokenAddress The address of the token to deposit as collateral
     * @param _collateralAmount The amount of collateral to deposit
     */
    function depositCollateral(address _tokenAddress, uint256 _collateralAmount)
        public
        moreThanZero(_collateralAmount)
        isAllowedToken(_tokenAddress)
        //? https://docs.openzeppelin.com/contracts/4.x/api/security
        //? https://solidity-by-example.org/hacks/re-entrancy/
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenAddress] += _collateralAmount;
        emit CollateralDeposited(msg.sender, _tokenAddress, _collateralAmount);
        bool success = IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _collateralAmount);
        if (!success) {
            revert ASCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // in order to redeem collateral:
    //1. health factor must be over 1 AFTER collateral pulled
    //! DRY: Don't Repeat Yourself
    // CEI
    function redeemCollateral(address _tokenAddress, uint256 _collateralAmount)
        public
        moreThanZero(_collateralAmount)
        nonReentrant
    {
        _redeemCollateral(_tokenAddress, _collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //1. Check if the collateral value > ACID amount. We'll need Price feeds, etc...
    //? $200 ETH -> $20 ACID
    /**
     * @notice follows CEI
     * @param _acidToMintAmount the amount of ACID to mint
     * @notice user must have more collateral value than the minimum threshold
     */
    function mintAcid(uint256 _acidToMintAmount) public moreThanZero(_acidToMintAmount) nonReentrant {
        s_ACIDMinted[msg.sender] += _acidToMintAmount;
        //* if they minted too much ($150 ACID, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_acid.mint(msg.sender, _acidToMintAmount);
        if (!minted) {
            revert ASCEngine__MintFailed();
        }
    }

    function burnAcid(uint256 _amount) public moreThanZero(_amount) {
        _burnAcid(_amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //! I don't think this would ever hit...
    }

    ////////////////////////////////////////
    //* Private & Internal View Functions //
    ////////////////////////////////////////
    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 totalAcidMinted, uint256 collateralValueInUsd)
    {
        totalAcidMinted = s_ACIDMinted[_user];
        collateralValueInUsd = getAccountTotalCollateralValue(_user);
    }
    /**
     *
     * @param _user user to check liquidation risk
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */

    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalAcidMinted, uint256 collateralValueInUsd) = _getAccountInformation(_user);
        if (totalAcidMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForTreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION; //? we need to be 200% collateralized

        //5 ($1000 ETH * 50) / 100 = $500
        //? if (collateralAdjustedForTreshold / totalAcidMinted) > 1, then we're overcollateralized (in this case, with a factor of 200%)
        //4 (n*1e18 * 1e18) / m*1e18 (because in WEI) = n/m * 1e18;
        return (collateralAdjustedForTreshold * DECIMAL_PRECISION) / totalAcidMinted;
    }

    //1 Check health factor (do they have enough collateral?)
    //2 Revert if they don't
    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert ASCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(address _tokenAddress, uint256 _collateralAmount, address _from, address _to)
        private
        checkUnderflow(s_collateralDeposited[_from][_tokenAddress], _collateralAmount)
    {
        // 100 - 1000 -> revert by solc
        s_collateralDeposited[_from][_tokenAddress] -= _collateralAmount;
        emit CollateralRedeemed(_from, _to, _tokenAddress, _collateralAmount);
        bool success = IERC20(_tokenAddress).transfer(_to, _collateralAmount);
        if (!success) {
            revert ASCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param _acidToBurnAmount The amount of ACIDs to burn
     * @param _onBehalfOf The address on behalf of burn ACIDs
     * @param _from The address from which to transfer ACIDs
     * @dev Low-level internal function, do not call unless the function calling it is checking for
     * health factors being broken
     */
    function _burnAcid(uint256 _acidToBurnAmount, address _onBehalfOf, address _from)
        private
        checkUnderflow(s_ACIDMinted[_onBehalfOf], _acidToBurnAmount)
    {
        s_ACIDMinted[_onBehalfOf] -= _acidToBurnAmount;
        bool success = i_acid.transferFrom(_from, address(this), _acidToBurnAmount);
        if (!success) {
            revert ASCEngine__TransferFailed();
        }
        i_acid.burn(_acidToBurnAmount);
    }

    ////////////////////////////////////////
    //* Public & External View Functions  //
    ////////////////////////////////////////
    function getAccountTotalCollateralValue(address _user) public view returns (uint256) {
        //1 loop through each collateral token, get the amount they have deposited, and map it to
        //1 the price, to get the USD value
        uint256 totalCollateralValueInUsd;
        for (uint256 i = 0; i < s_collateralTokensAddresses.length; i++) {
            address tokenAddress = s_collateralTokensAddresses[i];
            uint256 amountInToken = s_collateralDeposited[_user][tokenAddress];
            totalCollateralValueInUsd += getUsdValue(tokenAddress, amountInToken); //? USD value with 18 decimals
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address _tokenAddress, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData(); //! 8 decimals
        //? The returned value from priceFeed will be n * 1e8 (check on Chainlink Docs)
        //4 (n * 1e8 * 1e10) * (m * 1e18, because in WEI) / 1e18 = n*m*1e18;
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / DECIMAL_PRECISION;
    }

    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }

    function getTokenAmountFromUsd(address _tokenAddress, uint256 _usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (_usdAmountInWei * DECIMAL_PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address _user) external view returns (uint256, uint256) {
        return _getAccountInformation(_user);
    }

    function getPriceFeedAddress(address _tokenAddress) external view returns (address) {
        return s_priceFeeds[_tokenAddress];
    }

    function getCollateralTokenAddress(uint256 _index) external view returns (address) {
        return s_collateralTokensAddresses[_index];
    }

    function getCollateralTokenAddressLength() external view returns (uint256) {
        return s_collateralTokensAddresses.length;
    }

    function getAcidAddress() external view returns (address) {
        return address(i_acid);
    }

    function getCollateralDepositedByUserAndTokenAddress(address _user, address _tokenAddress)
        external
        view
        returns (uint256)
    {
        return s_collateralDeposited[_user][_tokenAddress];
    }

    function getAcidMinted(address _user) external view returns (uint256) {
        return s_ACIDMinted[_user];
    }
}
