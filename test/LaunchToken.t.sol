// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken public launchToken;

    function setUp() public {
        launchToken = new LaunchToken("LaunchToken", "LTK", address(this));
    }

    function test_NameAndSymbol() public {
        assertEq(launchToken.name(), "LaunchToken");
        assertEq(launchToken.symbol(), "LTK");
    }
}
