// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";
import {DeployASCEngine} from "../../script/DeployASCEngine.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {AcidStableCoin} from "../../src/AcidStableCoin.sol";
import {ASCEngine} from "../../src/ASCEngine.sol";

contract Invariants is StdInvariant, Test {
    DeployASCEngine deployer;
    ASCEngine engine;
    AcidStableCoin asc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployASCEngine();
        (asc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(engine));
        // hey, don't call redeemCollateral, unless there is collateral to redeem
        handler = new Handler(engine, asc);
        targetContract(address(handler));
    }

    function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to the debt (acid)
        uint256 totalSupply = asc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value:", wethValue);
        console.log("wbtc value:", wbtcValue);
        console.log("total supply:", totalSupply);
        console.log("Times mint called:", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    //* EVERGREEN INVARIANT
    function invariant_GettersShouldNotRevert() public view {
        engine.getAccountInformation(msg.sender);
        engine.getAccountTotalCollateralValue(msg.sender);
        engine.getAcidAddress();
        engine.getAcidMinted(msg.sender);
        engine.getCollateralTokenAddressLength();
        engine.getCollateralTokensAddresses();
        engine.getHealthFactor(msg.sender);
        // engine.getCollateralDepositedByUserAndTokenAddress(msg.sender, collateral);
        //   "getCollateralTokenAddress(uint256)": "4aee985b",
        //   "getPriceFeedAddress(address)": "b21eb1e6",
        //   "getTokenAmountFromUsd(address,uint256)": "afea2e48",
        //   "getUsdValue(address,uint256)": "c660d112",
    }
}
