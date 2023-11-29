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
    // Errors          //
    /////////////////////
    error ACIDEngine__ZeroAmount();
    error ACIDEngine__AllowedTokenContractsAndPriceFeedContractsMustBeSameLength();
    error ACIDEngine__NotAllowedToken();
    error ASCEngine__TransferFailed();

    /////////////////////
    // State Variables //
    /////////////////////

    mapping(address tokenContract => address priceFeedContract) private s_priceFeeds;
    mapping(address user => mapping(address tokenContract => uint256 amount)) private s_collateralDeposited;

    AcidStableCoin private immutable i_acid;

    /////////////////////
    // Events          //
    /////////////////////
    event CollateralDeposited(address indexed user, address indexed tokenContract, uint256 indexed amount);

    /////////////////////
    // Modifiers       //
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
    //Functions        //
    /////////////////////
    constructor(
        address[] memory _allowedTokenContractsList,
        address[] memory _priceFeedContracts,
        address _acidContract
    ) {
        //* USD Price Feeds
        if (_allowedTokenContractsList.length != _priceFeedContracts.length) {
            revert ACIDEngine__AllowedTokenContractsAndPriceFeedContractsMustBeSameLength();
        }
        //* For example, ETH / USD, BTC / USD...
        for (uint256 i = 0; i < _allowedTokenContractsList.length; i++) {
            s_priceFeeds[_allowedTokenContractsList[i]] = _priceFeedContracts[i];
        }
        i_acid = AcidStableCoin(_acidContract);
    }

    ////////////////////////
    // External Functions //
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

    function mintAcid() external {}

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
}
