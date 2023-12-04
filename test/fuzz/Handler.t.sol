//* Hanlder is going to narrow down the way we call function

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ASCEngine} from "../../src/ASCEngine.sol";
import {AcidStableCoin} from "../../src/AcidStableCoin.sol";

contract Handler is Test {
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    ASCEngine engine;
    AcidStableCoin asc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    constructor(ASCEngine _engine, AcidStableCoin _asc) {
        engine = _engine;
        asc = _asc;

        address[] memory collateralTokens = engine.getCollateralTokensAddresses();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    //* redeemCollateral <-
    function depositCollateral(uint256 _collateralSeed, uint256 _amountCollateral /* RANDOM */ ) public {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        _amountCollateral = bound(_amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, _amountCollateral);
        collateral.approve(address(engine), _amountCollateral);
        engine.depositCollateral(address(collateral), _amountCollateral);
        vm.stopPrank();
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 _collateralSeed) private view returns (ERC20Mock) {
        if (_collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
