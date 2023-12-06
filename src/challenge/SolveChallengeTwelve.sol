// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SolveChallengeTwelve {
    address private owner;

    constructor() {
        owner = msg.sender;
    }

    function getNumberr() public pure returns (uint128) {
        return 99;
    }

    function getOwner() public view returns (address) {
        return owner;
    }
}
