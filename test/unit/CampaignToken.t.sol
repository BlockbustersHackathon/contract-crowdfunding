// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract CampaignTokenTest is BaseTest {
    CampaignToken token;
    address mockCampaign;

    function setUp() public override {
        super.setUp();
        mockCampaign = makeAddr("mockCampaign");

        vm.prank(deployer);
        token = new CampaignToken("Test Campaign Token", "TCT", mockCampaign, deployer);
    }

    function test_Constructor_Success() public view {
        assertEq(token.name(), "Test Campaign Token");
        assertEq(token.symbol(), "TCT");
        assertEq(token.decimals(), 18);
        assertEq(token.campaignAddress(), mockCampaign);
        assertEq(token.owner(), deployer);
        assertEq(token.totalSupply(), 0);
    }

    function test_Constructor_InvalidAddresses() public {
        vm.startPrank(deployer);

        // Test invalid campaign address
        vm.expectRevert("CampaignToken: Invalid campaign address");
        new CampaignToken("Test", "TEST", address(0), deployer);

        // Test invalid owner address
        vm.expectRevert();
        new CampaignToken("Test", "TEST", mockCampaign, address(0));

        vm.stopPrank();
    }

    function test_Mint_Success() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(mockCampaign);
        token.mint(contributor1, mintAmount);

        assertEq(token.balanceOf(contributor1), mintAmount);
        assertEq(token.totalSupply(), mintAmount);
    }

    function test_Mint_OnlyCampaign() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(deployer);
        vm.expectRevert("CampaignToken: Only campaign can call");
        token.mint(contributor1, mintAmount);

        vm.prank(contributor1);
        vm.expectRevert("CampaignToken: Only campaign can call");
        token.mint(contributor1, mintAmount);
    }

    function test_Mint_InvalidParameters() public {
        vm.startPrank(mockCampaign);

        // Test zero address
        vm.expectRevert("CampaignToken: Cannot mint to zero address");
        token.mint(address(0), 1000 * 10 ** 18);

        // Test zero amount
        vm.expectRevert("CampaignToken: Amount must be greater than zero");
        token.mint(contributor1, 0);

        vm.stopPrank();
    }

    function test_Mint_ExceedsMaxSupply() public {
        uint256 maxSupply = token.MAX_SUPPLY();

        vm.prank(mockCampaign);
        vm.expectRevert("CampaignToken: Exceeds max supply");
        token.mint(contributor1, maxSupply + 1);
    }

    function test_Mint_MultipleMintsToMaxSupply() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        uint256 firstMint = maxSupply / 2;
        uint256 secondMint = maxSupply / 2;

        vm.startPrank(mockCampaign);
        token.mint(contributor1, firstMint);
        token.mint(contributor2, secondMint);
        vm.stopPrank();

        assertEq(token.totalSupply(), maxSupply);

        // Next mint should fail
        vm.prank(mockCampaign);
        vm.expectRevert("CampaignToken: Exceeds max supply");
        token.mint(contributor3, 1);
    }

    function test_Burn_Success() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 burnAmount = 500 * 10 ** 18;

        vm.prank(mockCampaign);
        token.mint(contributor1, mintAmount);

        vm.prank(contributor1);
        token.burn(burnAmount);

        assertEq(token.balanceOf(contributor1), mintAmount - burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
    }

    function test_Burn_InvalidParameters() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(mockCampaign);
        token.mint(contributor1, mintAmount);

        vm.startPrank(contributor1);

        // Test zero amount
        vm.expectRevert("CampaignToken: Amount must be greater than zero");
        token.burn(0);

        // Test insufficient balance
        vm.expectRevert("CampaignToken: Insufficient balance");
        token.burn(mintAmount + 1);

        vm.stopPrank();
    }

    function test_StandardERC20_Functions() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 transferAmount = 200 * 10 ** 18;
        uint256 approveAmount = 300 * 10 ** 18;

        // Mint tokens
        vm.prank(mockCampaign);
        token.mint(contributor1, mintAmount);

        // Test transfer
        vm.prank(contributor1);
        token.transfer(contributor2, transferAmount);

        assertEq(token.balanceOf(contributor1), mintAmount - transferAmount);
        assertEq(token.balanceOf(contributor2), transferAmount);

        // Test approve and transferFrom
        vm.prank(contributor1);
        token.approve(contributor2, approveAmount);

        assertEq(token.allowance(contributor1, contributor2), approveAmount);

        vm.prank(contributor2);
        token.transferFrom(contributor1, contributor3, approveAmount);

        assertEq(token.balanceOf(contributor1), mintAmount - transferAmount - approveAmount);
        assertEq(token.balanceOf(contributor3), approveAmount);
        assertEq(token.allowance(contributor1, contributor2), 0);
    }

    function test_GetCampaignAddress() public view {
        assertEq(token.getCampaignAddress(), mockCampaign);
    }

    function test_ERC20Permit_Functionality() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.prank(mockCampaign);
        token.mint(contributor1, mintAmount);

        // Test that permit functionality is available
        uint256 nonce = token.nonces(contributor1);
        assertEq(nonce, 0);

        // Test domain separator exists
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0));
    }

    function test_Ownership_Functions() public {
        assertEq(token.owner(), deployer);

        // Test ownership transfer
        address newOwner = makeAddr("newOwner");

        vm.prank(deployer);
        token.transferOwnership(newOwner);

        assertEq(token.owner(), newOwner);
    }
}
