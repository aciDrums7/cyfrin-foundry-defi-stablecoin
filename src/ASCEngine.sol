// SPDX-License-Identifier: MIT

// Layout of Contract:
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
    error ASCEngine__AllowedTokenContractsAndPriceFeedContractsMustBeSameLength();
    error ASCEngine__NotAllowedToken();
    error ASCEngine__TransferFailed();
    error ASCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error ASCEngine__MintFailed();
    error ASCEngine__HealthFactorOk();

    ////////////////////////
    //* State Variables   //
    ////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant DECIMAL_PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //! 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means a 10% bonus

    mapping(address tokenContract => address priceFeedContract) private s_priceFeeds;
    mapping(address user => mapping(address tokenContract => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 acidMintedAmount) private s_ACIDMinted;
    address[] private s_collateralTokensContracts;

    AcidStableCoin private immutable i_acid;

    /////////////////////
    //* Events         //
    /////////////////////
    event CollateralDeposited(address indexed user, address indexed tokenContract, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed tokenContract, uint256 indexed amount);

    /////////////////////
    //* Modifiers      //
    /////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert ASCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenContract) {
        if (s_priceFeeds[_tokenContract] == address(0)) {
            revert ASCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////////////
    //* Functions      //
    /////////////////////
    constructor(address[] memory _allowedTokenContracts, address[] memory _priceFeedContracts, address _acidContract) {
        //* USD Price Feeds
        if (_allowedTokenContracts.length != _priceFeedContracts.length) {
            revert ASCEngine__AllowedTokenContractsAndPriceFeedContractsMustBeSameLength();
        }
        //* For example, ETH / USD, BTC / USD...
        for (uint256 i = 0; i < _allowedTokenContracts.length; i++) {
            s_priceFeeds[_allowedTokenContracts[i]] = _priceFeedContracts[i];
            s_collateralTokensContracts.push(_allowedTokenContracts[i]);
        }
        i_acid = AcidStableCoin(_acidContract);
    }

    /////////////////////////
    //* External Functions //
    /////////////////////////
    /**
     *
     * @param _tokenContract The address of the token to deposit as collateral
     * @param _collateralAmount The amount of the collateral to deposit
     * @param _acidToMintAmount The amount of ACID to mint
     * @notice This function will deposit your collateral and mint your ACID in one transaction
     */
    function depositCollateralAndMintAcid(address _tokenContract, uint256 _collateralAmount, uint256 _acidToMintAmount)
        external
    {
        depositCollateral(_tokenContract, _collateralAmount);
        mintAcid(_acidToMintAmount);
    }

    /**
     * @param _tokenContract The address of the token collateral
     * @param _collateralAmount The amount of token collateral to redeem
     * @param _amountAcidToBurn The amount of ACID to burn
     * This function burns ACID and redeems underlying collateral in one transaction
     */
    function redeemCollateralForAcid(address _tokenContract, uint256 _collateralAmount, uint256 _amountAcidToBurn)
        external
    {
        burnAcid(_amountAcidToBurn);
        redeemCollateral(_tokenContract, _collateralAmount);
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
     * @param _tokenContract The ERC20 collateral address to liquidate from the user
     * @param _userToLiquidate The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param _debtToCover The amount of ACID you want to burn to improve the user health factor
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% collateralized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentive the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(address _tokenContract, address _userToLiquidate, uint256 _debtToCover)
        external
        moreThanZero(_debtToCover)
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
        uint256 ethAmountFromDebtCovered = getTokenAmountFromUsd(_tokenContract, _debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for $100 ACID
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (ethAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = ethAmountFromDebtCovered + bonusCollateral;
    }

    ////////////////////////
    //* Public  Functions //
    ////////////////////////
    /**
     * @notice follows CEI
     * @param _tokenContract The address of the token to deposit as collateral
     * @param _collateralAmount The amount of collateral to deposit
     */
    function depositCollateral(address _tokenContract, uint256 _collateralAmount)
        public
        moreThanZero(_collateralAmount)
        isAllowedToken(_tokenContract)
        //? https://docs.openzeppelin.com/contracts/4.x/api/security
        //? https://solidity-by-example.org/hacks/re-entrancy/
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenContract] += _collateralAmount;
        emit CollateralDeposited(msg.sender, _tokenContract, _collateralAmount);
        bool success = IERC20(_tokenContract).transferFrom(msg.sender, address(this), _collateralAmount);
        if (!success) {
            revert ASCEngine__TransferFailed();
        }
    }

    // in order to redeem collateral:
    //1. health factor must be over 1 AFTER collateral pulled
    //! DRY: Don't Repeat Yourself
    // CEI
    function redeemCollateral(address _tokenContract, uint256 _collateralAmount)
        public
        moreThanZero(_collateralAmount)
        nonReentrant
    {
        // 100 - 1000 -> revert by solc
        s_collateralDeposited[msg.sender][_tokenContract] -= _collateralAmount;
        emit CollateralRedeemed(msg.sender, _tokenContract, _collateralAmount);
        bool success = IERC20(_tokenContract).transfer(msg.sender, _collateralAmount);
        if (!success) {
            revert ASCEngine__TransferFailed();
        }
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
        s_ACIDMinted[msg.sender] -= _amount;
        bool success = i_acid.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert ASCEngine__TransferFailed();
        }
        i_acid.burn(_amount);
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
        collateralValueInUsd = getAccountCollateralValue(_user);
    }
    /**
     *
     * @param _user user to check liquidation risk
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */

    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalAcidMinted, uint256 collateralValueInUsd) = _getAccountInformation(_user);
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

    ////////////////////////////////////////
    //* Public & External View Functions  //
    ////////////////////////////////////////
    function getAccountCollateralValue(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        //1 loop through each collateral token, get the amount they have deposited, and map it to
        //1 the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokensContracts.length; i++) {
            address tokenContract = s_collateralTokensContracts[i];
            uint256 amountInToken = s_collateralDeposited[_user][tokenContract];
            totalCollateralValueInUsd += getUsdValue(tokenContract, amountInToken); //? USD VALUE with 18 decimals
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address _tokenContract, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenContract]);
        (, int256 price,,,) = priceFeed.latestRoundData(); //! 8 decimals
        //? The returned value from priceFeed will be n * 1e8 (check on Chainlink Docs)
        //4 (n * 1e8 * 1e10) * (m * 1e18, because in WEI) / 1e18 = n*m*1e18;
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / DECIMAL_PRECISION;
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    function getTokenAmountFromUsd(address _tokenContract, uint256 _usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenContract]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (_usdAmountInWei * DECIMAL_PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }
}
