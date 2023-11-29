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
contract ACIDEngine is ReentrancyGuard {
    /////////////////////
    //* Errors         //
    /////////////////////
    error ACIDEngine__ZeroAmount();
    error ACIDEngine__AllowedTokenContractsAndPriceFeedContractsMustBeSameLength();
    error ACIDEngine__NotAllowedToken();
    error ASCEngine__TransferFailed();

    ////////////////////////
    //* State Variables   //
    ////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant DECIMAL_PRECISION = 1e18;

    mapping(address tokenContract => address priceFeedContract) private s_priceFeeds;
    mapping(address user => mapping(address tokenContract => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 acidMintedAmount) private s_ACIDMinted;
    address[] private s_collateralTokensContracts;

    AcidStableCoin private immutable i_acid;

    /////////////////////
    //* Events         //
    /////////////////////
    event CollateralDeposited(address indexed user, address indexed tokenContract, uint256 indexed amount);

    /////////////////////
    //* Modifiers      //
    /////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert ACIDEngine__ZeroAmount();
        }
        _;
    }

    modifier isAllowedToken(address _tokenContract) {
        if (s_priceFeeds[_tokenContract] == address(0)) {
            revert ACIDEngine__NotAllowedToken();
        }
        _;
    }

    /////////////////////
    //* Functions      //
    /////////////////////
    constructor(address[] memory _allowedTokenContracts, address[] memory _priceFeedContracts, address _acidContract) {
        //* USD Price Feeds
        if (_allowedTokenContracts.length != _priceFeedContracts.length) {
            revert ACIDEngine__AllowedTokenContractsAndPriceFeedContractsMustBeSameLength();
        }
        //* For example, ETH / USD, BTC / USD...
        for (uint256 i = 0; i < _allowedTokenContracts.length; i++) {
            s_priceFeeds[_allowedTokenContracts[i]] = _priceFeedContracts[i];
            s_collateralTokensContracts.push(_allowedTokenContracts[i]);
        }
        i_acid = AcidStableCoin(_acidContract);
    }

    ////////////////////////
    //* External Functions //
    ////////////////////////
    function depositCollateralAndMintAcid() external {}

    /**
     * @notice follows CEI
     * @param _tokenContract The address of the token to deposit as collateral
     * @param _collateralAmount The amount of collateral to deposit
     */
    function depositCollateral(address _tokenContract, uint256 _collateralAmount)
        external
        moreThanZero(_collateralAmount)
        isAllowedToken(_tokenContract)
        nonReentrant
    //? https://docs.openzeppelin.com/contracts/4.x/api/security
    //? https://solidity-by-example.org/hacks/re-entrancy/
    {
        s_collateralDeposited[msg.sender][_tokenContract] += _collateralAmount;
        emit CollateralDeposited(msg.sender, _tokenContract, _collateralAmount);
        bool success = IERC20(_tokenContract).transferFrom(msg.sender, address(this), _collateralAmount);
        if (!success) {
            revert ASCEngine__TransferFailed();
        }
    }

    function redeemCollateralForAcid() external {}

    function redeemCollateral() external {}

    //1. Check if the collateral value > ACID amount. Price feeds, etc...
    //? $200 ETH -> $20 ACID
    /**
     * @notice follows CEI
     * @param _acidToMintAmount the amount of ACID to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintAcid(uint256 _acidToMintAmount) external moreThanZero(_acidToMintAmount) nonReentrant {
        s_ACIDMinted[msg.sender] += _acidToMintAmount;
        //* if they minted too much ($150 ACID, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnAcid() external {}

    //? Threshold to let's say 150%
    //? $100 ETH Collateral -> $74 ETH
    //? $50 ACID
    //! UNDERCOLLATERALIZED!!! -> people can liquidate your position (paying $50 ACID, gaining 74$ ETH -> earning $24 in ETH!)

    //! I'll pay back the $50 ACID -> Get all your collateral! ($74 ETH)
    //* $74 ETH
    //* -$50 ASC
    //* $24 profit
    function liquidate() external {}

    function getHealthFactor() external view {}

    ////////////////////////////////////////
    //* Private & Internal View Functions //
    ////////////////////////////////////////

    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 totalAcidMinted, uint256 collateralValueInUsd)
    {
        totalAcidMinted = s_ACIDMinted[msg.sender];
        collateralValueInUsd = getAccountCollateralValue(_user);
    }
    /**
     *
     * @param _user user to check liquidation risk
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */

    function _healthFactor(address _user) private view returns (uint256) {
        // total ACID minted
        // total collateral VALUE
        (uint256 totalAcidMinted, uint256 collateralValueInUsd) = _getAccountInformation(_user);
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        //? Check health factor (do they have enough collateral?)
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
            totalCollateralValueInUsd += getUsdValue(tokenContract, amountInToken);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address _tokenContract, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_tokenContract]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8 (check on Chainlink Docs)
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / DECIMAL_PRECISION; // (n * 1e8 * 1e10) * (m * 1e18, because in WEI) / 1e18 = n*m*1e18;
    }
}
