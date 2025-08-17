// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract AccessControlTest is BaseTest {
    uint256 campaignId;
    Campaign campaign;

    function setUp() public override {
        super.setUp();
        campaignId = createTestCampaign();
        campaign = getCampaign(campaignId);
    }

    function test_CreatorOnly_WithdrawFunds() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        // Non-creator attempts should fail
        vm.prank(contributor1);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.withdrawFunds();

        vm.prank(contributor2);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.withdrawFunds();

        vm.prank(deployer);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.withdrawFunds();

        // Creator should succeed
        vm.prank(creator);
        campaign.withdrawFunds();
    }

    function test_CreatorOnly_CreateLiquidityPool() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        // Non-creator attempts should fail
        vm.prank(contributor1);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.createLiquidityPool();

        vm.prank(deployer);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.createLiquidityPool();

        // Creator should succeed
        vm.prank(creator);
        campaign.createLiquidityPool();
    }

    function test_CreatorOnly_ExtendDeadline() public {
        uint256 newDeadline = block.timestamp + CAMPAIGN_DURATION + 1 days;

        // Non-creator attempts should fail
        vm.prank(contributor1);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.extendDeadline(newDeadline);

        vm.prank(deployer);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.extendDeadline(newDeadline);

        // Creator should succeed
        vm.prank(creator);
        campaign.extendDeadline(newDeadline);
    }

    function test_FactoryOwnerOnly_SetPlatformFee() public {
        // Non-owner attempts should fail
        vm.prank(creator);
        vm.expectRevert();
        factory.setPlatformFee(300);

        vm.prank(contributor1);
        vm.expectRevert();
        factory.setPlatformFee(300);

        // Owner should succeed
        vm.prank(deployer);
        factory.setPlatformFee(300);
    }

    function test_FactoryOwnerOnly_SetFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");

        // Non-owner attempts should fail
        vm.prank(creator);
        vm.expectRevert();
        factory.setFeeRecipient(newRecipient);

        vm.prank(contributor1);
        vm.expectRevert();
        factory.setFeeRecipient(newRecipient);

        // Owner should succeed
        vm.prank(deployer);
        factory.setFeeRecipient(newRecipient);
    }

    function test_FactoryOwnerOnly_WithdrawPlatformFees() public {
        // Fund the factory
        vm.deal(address(factory), 1 ether);

        // Non-owner attempts should fail
        vm.prank(creator);
        vm.expectRevert();
        factory.withdrawPlatformFees();

        vm.prank(contributor1);
        vm.expectRevert();
        factory.withdrawPlatformFees();

        // Owner should succeed
        vm.prank(deployer);
        factory.withdrawPlatformFees();
    }

    function test_CampaignTokenMinting_OnlyCampaign() public {
        CampaignData memory data = campaign.getCampaignDetails();
        CampaignToken token = CampaignToken(data.tokenAddress);

        // Non-campaign attempts should fail
        vm.prank(creator);
        vm.expectRevert("CampaignToken: Only campaign can call");
        token.mint(contributor1, 1000 * 10 ** 18);

        vm.prank(contributor1);
        vm.expectRevert("CampaignToken: Only campaign can call");
        token.mint(contributor1, 1000 * 10 ** 18);

        vm.prank(deployer);
        vm.expectRevert("CampaignToken: Only campaign can call");
        token.mint(contributor1, 1000 * 10 ** 18);

        // Campaign contract should succeed
        contributeToCompaign(campaignId, contributor1, 1 ether);
        contributeToCompaign(campaignId, contributor2, FUNDING_GOAL - 1 ether);
        campaign.updateCampaignState();

        vm.prank(contributor1);
        campaign.claimTokens(); // This should succeed and mint tokens

        assertGt(token.balanceOf(contributor1), 0);
    }

    function test_CampaignOwnership_FactoryAsOwner() public {
        // Campaign should be owned by factory
        assertEq(campaign.owner(), address(factory));

        // Only factory should be able to call owner functions
        address tokenAddress = makeAddr("newToken");

        vm.prank(creator);
        vm.expectRevert();
        campaign.setTokenAddress(tokenAddress);

        vm.prank(deployer);
        vm.expectRevert();
        campaign.setTokenAddress(tokenAddress);

        // Factory should be able to call
        vm.prank(address(factory));
        campaign.setTokenAddress(tokenAddress);
    }

    function test_TokenOwnership_CampaignAsOwner() public {
        CampaignData memory data = campaign.getCampaignDetails();
        CampaignToken token = CampaignToken(data.tokenAddress);

        // Token should be owned by campaign
        assertEq(token.owner(), address(campaign));

        // Only campaign should be able to transfer ownership
        address newOwner = makeAddr("newOwner");

        vm.prank(creator);
        vm.expectRevert();
        token.transferOwnership(newOwner);

        vm.prank(deployer);
        vm.expectRevert();
        token.transferOwnership(newOwner);
    }

    function test_ContributorRights_ClaimTokens() public {
        uint256 contribution = 2 ether;
        contributeToCompaign(campaignId, contributor1, contribution);
        contributeToCompaign(campaignId, contributor2, FUNDING_GOAL - contribution);
        campaign.updateCampaignState();

        // Non-contributors should not be able to claim tokens
        vm.prank(contributor3); // contributor3 never made a contribution
        vm.expectRevert("Campaign: No contribution found");
        campaign.claimTokens();

        // Both contributors can claim their own tokens
        vm.prank(contributor1);
        campaign.claimTokens();

        vm.prank(contributor2);
        campaign.claimTokens();

        CampaignData memory data = campaign.getCampaignDetails();
        assertGt(IERC20(data.tokenAddress).balanceOf(contributor1), 0);
        assertGt(IERC20(data.tokenAddress).balanceOf(contributor2), 0);
    }

    function test_ContributorRights_Refund() public {
        uint256 strictCampaignId = createTestCampaignWithGoalRequired();
        Campaign strictCampaign = getCampaign(strictCampaignId);

        uint256 contribution = 2 ether;
        contributeToCompaign(strictCampaignId, contributor1, contribution);

        fastForwardToDeadline(strictCampaignId);
        strictCampaign.updateCampaignState();

        // Only contributors can refund their own contributions
        vm.prank(contributor2);
        vm.expectRevert("Campaign: No contribution found");
        strictCampaign.refund();

        // Contributor1 can refund own contribution
        uint256 initialBalance = contributor1.balance;
        vm.prank(contributor1);
        strictCampaign.refund();

        assertEq(contributor1.balance, initialBalance + contribution);
    }

    function test_PublicFunctions_AnyoneCanCall() public {
        // These functions should be callable by anyone
        vm.prank(contributor1);
        campaign.updateCampaignState();

        vm.prank(makeAddr("randomUser"));
        campaign.getCampaignDetails();

        vm.prank(contributor2);
        campaign.calculateTokenAllocation(1 ether);

        vm.prank(deployer);
        campaign.getContributors();
    }

    function test_OwnershipTransfer_Factory() public {
        address newOwner = makeAddr("newOwner");

        // Transfer ownership
        vm.prank(deployer);
        factory.transferOwnership(newOwner);

        // New owner should have control immediately (OpenZeppelin Ownable)
        vm.prank(newOwner);
        factory.setPlatformFee(400);

        // Old owner should lose control
        vm.prank(deployer);
        vm.expectRevert();
        factory.setPlatformFee(500);
    }

    function test_EmergencyFunctions_OnlyOwner() public {
        // Emergency withdraw should only be callable by owner
        vm.deal(address(factory), 1 ether);

        vm.prank(creator);
        vm.expectRevert();
        factory.emergencyWithdraw();

        vm.prank(contributor1);
        vm.expectRevert();
        factory.emergencyWithdraw();

        uint256 ownerInitialBalance = deployer.balance;

        vm.prank(deployer);
        factory.emergencyWithdraw();

        assertEq(deployer.balance, ownerInitialBalance + 1 ether);
    }
}
