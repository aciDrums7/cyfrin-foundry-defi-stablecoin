// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AcidStableCoin} from "../../src/AcidStableCoin.sol";

contract AcidStableCoinTest is Test {
    uint256 public constant ACID_AMOUNT = 10;
    AcidStableCoin acid;

    function setUp() public {
        acid = new AcidStableCoin();
    }

    /////////////////////
    //* Burn Tests     //
    /////////////////////
    function test_BurnRevertsIfAmountZero() public {
        vm.expectRevert(AcidStableCoin.AcidStableCoin__MustBeMoreThanZero.selector);
        acid.burn(0);
    }

    function test_BurnRevertsIfBalanceLessThanAmount() public {
        vm.expectRevert(AcidStableCoin.AcidStableCoin__BurnAmountExceedsBalance.selector);
        acid.burn(ACID_AMOUNT);
    }

    ////////////////////
    //* Mint Tests     //
    ////////////////////
    function test_MintRevertsIfZeroAddress() public {
        vm.expectRevert(AcidStableCoin.AcidStableCoin__ZeroAddressNotAllowed.selector);
        acid.mint(address(0), ACID_AMOUNT);
    }

    function test_MintRevertsIfAmountZero() public {
        vm.expectRevert(AcidStableCoin.AcidStableCoin__MustBeMoreThanZero.selector);
        acid.mint(address(21), 0);
    }
}
