// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FundToken} from "../src/FundToken.sol";

contract FundTokenTest is Test {
    FundToken public fundToken;

    function setUp() public {
        fundToken = new FundToken(address(this));
    }

    function test_Mint() public {
        fundToken.mint(address(this), 100);
        assertEq(fundToken.balanceOf(address(this)), 100);
    }
}
