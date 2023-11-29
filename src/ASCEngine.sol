// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
contract ACIDEngine {
    function depositCollateralAndMintAcid() external {}

    function depositCollateral() external {}

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
