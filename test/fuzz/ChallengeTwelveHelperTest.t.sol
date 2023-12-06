// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ChallengeTwelveHelper} from "../../src/challenge/ChallengeTwelveHelper.sol";
import {SolveChallengeTwelve} from "../../src/challenge/SolveChallengeTwelve.sol";
import {ChallengeTwelve} from "../../src/challenge/ChallengeTwelve.sol";

contract ChallengeTwelveHelperTest is Test {
    ChallengeTwelveHelper helper;
    SolveChallengeTwelve solver;
    ChallengeTwelve challenge;

    function setUp() public {
        challenge = new ChallengeTwelve();
        helper = new ChallengeTwelveHelper();
        solver = new SolveChallengeTwelve();
    }

    function test_SolveChallenge() public {
        vm.expectRevert(ChallengeTwelve.ChallengeTwelve__AHAHAHAHAHA.selector);
        challenge.solveChallenge(address(solver));
    }
}
