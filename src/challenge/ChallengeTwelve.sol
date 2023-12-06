// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ChallengeTwelveHelper} from "./ChallengeTwelveHelper.sol";

contract ChallengeTwelve {
    error ChallengeTwelve__AHAHAHAHAHA();

    string private constant LESSON_IMAGE = "ipfs://QmcSKN5FWehTrsmfpv5uiKHnoPM1L2uL8QekPSMuThHHkb";

    ChallengeTwelveHelper private immutable i_hellContract;

    constructor() {
        i_hellContract = new ChallengeTwelveHelper();
    }

    /*
     * CALL THIS FUNCTION!
     * 
     * Hint: Can you write a fuzz test that finds the solution for you? 
     * 
     * @param exploitContract - A contract that you're going to use to try to break this thing
     * @param yourTwitterHandle - Your twitter handle. Can be a blank string.
     */
    function solveChallenge(address exploitContract) external returns (bool) {
        (bool successOne, bytes memory numberrBytes) = exploitContract.call(abi.encodeWithSignature("getNumberr()"));
        (bool successTwo,) = exploitContract.call(abi.encodeWithSignature("getOwner()"));

        if (!successOne || !successTwo) {
            revert ChallengeTwelve__AHAHAHAHAHA();
        }

        uint128 numberr = abi.decode(numberrBytes, (uint128));

        try i_hellContract.hellFunc(numberr) returns (uint256) {
            revert ChallengeTwelve__AHAHAHAHAHA();
        } catch {
            return true;
        }
    }

    function getHellContract() public view returns (address) {
        return address(i_hellContract);
    }
}
