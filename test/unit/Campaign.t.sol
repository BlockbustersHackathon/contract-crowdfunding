// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract CampaignTest is BaseTest {
    uint256 campaignId;
    Campaign campaign;

    function setUp() public override {
        super.setUp();
        campaignId = createTestCampaign();
        campaign = getCampaign(campaignId);
    }

    // Contribution Tests
    function test_Contribute_Success() public {
        uint256 contributionAmount = 1 ether;
        uint256 initialBalance = contributor1.balance;

        vm.prank(contributor1);
        campaign.contribute{value: contributionAmount}();

        // Check contribution recorded
        Contribution memory contrib = campaign.getContribution(contributor1);
        assertEq(contrib.amount, contributionAmount);
        assertEq(contrib.contributor, contributor1);
        assertTrue(contrib.tokenAllocation > 0);

        // Check campaign state updated
        CampaignData memory data = campaign.getCampaignDetails();
        assertEq(data.totalRaised, contributionAmount);

        // Check contributor balance reduced
        assertEq(contributor1.balance, initialBalance - contributionAmount);
    }

    function test_Contribute_MultipleContributions() public {
        uint256 firstContribution = 1 ether;
        uint256 secondContribution = 2 ether;

        vm.startPrank(contributor1);
        campaign.contribute{value: firstContribution}();
        campaign.contribute{value: secondContribution}();
        vm.stopPrank();

        Contribution memory contrib = campaign.getContribution(contributor1);
        assertEq(contrib.amount, firstContribution + secondContribution);

        CampaignData memory data = campaign.getCampaignDetails();
        assertEq(data.totalRaised, firstContribution + secondContribution);
    }

    function test_Contribute_BelowMinimum() public {
        vm.prank(contributor1);
        vm.expectRevert("Campaign: Contribution below minimum");
        campaign.contribute{value: 0.0005 ether}(); // Below MIN_CONTRIBUTION
    }

    function test_Contribute_CreatorCannotContribute() public {
        vm.prank(creator);
        vm.expectRevert("Campaign: Creator cannot contribute");
        campaign.contribute{value: 1 ether}();
    }

    function test_Contribute_AfterDeadline() public {
        fastForwardToDeadline(campaignId);

        vm.prank(contributor1);
        vm.expectRevert("Campaign: Campaign expired");
        campaign.contribute{value: 1 ether}();
    }

    function test_Contribute_InactiveState() public {
        // Reach goal and change state
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        vm.prank(contributor2);
        vm.expectRevert("Campaign: Campaign not active");
        campaign.contribute{value: 1 ether}();
    }

    function test_EarlyBackerBonus() public {
        // Early contribution should get bonus
        vm.prank(contributor1);
        campaign.contribute{value: 1 ether}();
        Contribution memory earlyContrib = campaign.getContribution(contributor1);

        // Fast forward to later in campaign (past early bird period which is 25%)
        fastForwardTime(CAMPAIGN_DURATION / 3); // 33% through campaign

        vm.prank(contributor2);
        campaign.contribute{value: 1 ether}();
        Contribution memory laterContrib = campaign.getContribution(contributor2);

        // Early contributor should have more tokens for same contribution due to early bird bonus
        // Note: The exact amounts will depend on the pricing curve logic
        assertGt(earlyContrib.tokenAllocation, laterContrib.tokenAllocation);
    }

    // State Transition Tests
    function test_StateTransition_ActiveToSucceeded_GoalReached() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        assertCampaignState(campaignId, CampaignState.Succeeded);
    }

    function test_StateTransition_ActiveToSucceeded_DeadlineWithFlexible() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL / 2);
        fastForwardToDeadline(campaignId);
        campaign.updateCampaignState();

        // Should succeed because allowEarlyWithdrawal is true
        assertCampaignState(campaignId, CampaignState.Succeeded);
    }

    function test_StateTransition_ActiveToFailed_DeadlineWithoutGoal() public {
        uint256 strictCampaignId = createTestCampaignWithGoalRequired();
        Campaign strictCampaign = getCampaign(strictCampaignId);

        contributeToCompaign(strictCampaignId, contributor1, FUNDING_GOAL / 2);
        fastForwardToDeadline(strictCampaignId);
        strictCampaign.updateCampaignState();

        assertEq(uint256(strictCampaign.getCampaignState()), uint256(CampaignState.Failed));
    }

    // Fund Withdrawal Tests
    function test_WithdrawFunds_Success() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        uint256 initialBalance = creator.balance;

        vm.prank(creator);
        campaign.withdrawFunds();

        assertEq(creator.balance, initialBalance + FUNDING_GOAL);
        assertCampaignState(campaignId, CampaignState.FundsWithdrawn);
    }

    function test_WithdrawFunds_OnlyCreator() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        vm.prank(contributor1);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.withdrawFunds();
    }

    function test_WithdrawFunds_WrongState() public {
        vm.prank(creator);
        vm.expectRevert("Campaign: Campaign must be successful");
        campaign.withdrawFunds();
    }

    // Token Claiming Tests
    function test_ClaimTokens_Success() public {
        uint256 contributionAmount = 1 ether;
        contributeToCompaign(campaignId, contributor1, contributionAmount);
        contributeToCompaign(campaignId, contributor2, FUNDING_GOAL - contributionAmount);
        campaign.updateCampaignState();

        Contribution memory contrib = campaign.getContribution(contributor1);
        uint256 expectedTokens = contrib.tokenAllocation;

        vm.prank(contributor1);
        campaign.claimTokens();

        CampaignData memory data = campaign.getCampaignDetails();
        assertTokenBalance(data.tokenAddress, contributor1, expectedTokens);

        // Check claimed flag
        Contribution memory updatedContrib = campaign.getContribution(contributor1);
        assertTrue(updatedContrib.claimed);
    }

    function test_ClaimTokens_DoubleClaim() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        vm.startPrank(contributor1);
        campaign.claimTokens();

        vm.expectRevert("Campaign: Tokens already claimed");
        campaign.claimTokens();
        vm.stopPrank();
    }

    function test_ClaimTokens_NoContribution() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        vm.prank(contributor2); // Didn't contribute
        vm.expectRevert("Campaign: No contribution found");
        campaign.claimTokens();
    }

    function test_ClaimTokens_WrongState() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL / 2);

        vm.prank(contributor1);
        vm.expectRevert("Campaign: Cannot claim tokens yet");
        campaign.claimTokens();
    }

    // Refund Tests
    function test_Refund_FailedCampaign() public {
        uint256 strictCampaignId = createTestCampaignWithGoalRequired();
        Campaign strictCampaign = getCampaign(strictCampaignId);

        uint256 contributionAmount = FUNDING_GOAL / 2;
        contributeToCompaign(strictCampaignId, contributor1, contributionAmount);

        fastForwardToDeadline(strictCampaignId);
        strictCampaign.updateCampaignState();

        uint256 initialBalance = contributor1.balance;

        vm.prank(contributor1);
        strictCampaign.refund();

        assertEq(contributor1.balance, initialBalance + contributionAmount);

        // Check contribution amount reset
        Contribution memory contrib = strictCampaign.getContribution(contributor1);
        assertEq(contrib.amount, 0);
    }

    function test_Refund_SuccessfulCampaign() public {
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL);
        campaign.updateCampaignState();

        vm.prank(contributor1);
        vm.expectRevert("Campaign: Refunds not available");
        campaign.refund();
    }

    function test_Refund_NoContribution() public {
        uint256 strictCampaignId = createTestCampaignWithGoalRequired();
        Campaign strictCampaign = getCampaign(strictCampaignId);

        fastForwardToDeadline(strictCampaignId);
        strictCampaign.updateCampaignState();

        vm.prank(contributor1); // Didn't contribute
        vm.expectRevert("Campaign: No contribution found");
        strictCampaign.refund();
    }

    // Extension Tests
    function test_ExtendDeadline_Success() public {
        uint256 newDeadline = block.timestamp + CAMPAIGN_DURATION + 1 days;

        vm.prank(creator);
        campaign.extendDeadline(newDeadline);

        CampaignData memory data = campaign.getCampaignDetails();
        assertEq(data.deadline, newDeadline);
    }

    function test_ExtendDeadline_OnlyCreator() public {
        uint256 newDeadline = block.timestamp + CAMPAIGN_DURATION + 1 days;

        vm.prank(contributor1);
        vm.expectRevert("Campaign: Only creator can call");
        campaign.extendDeadline(newDeadline);
    }

    function test_ExtendDeadline_EarlierThanCurrent() public {
        uint256 newDeadline = block.timestamp + CAMPAIGN_DURATION - 1 days;

        vm.prank(creator);
        vm.expectRevert("Campaign: New deadline must be later");
        campaign.extendDeadline(newDeadline);
    }

    function test_ExtendDeadline_ExceedsLimit() public {
        uint256 newDeadline = block.timestamp + CAMPAIGN_DURATION + 31 days; // Exceeds 30 day limit

        vm.prank(creator);
        vm.expectRevert("Campaign: Extension exceeds limit");
        campaign.extendDeadline(newDeadline);
    }

    // View Function Tests
    function test_CalculateTokenAllocation() public {
        uint256 allocation = campaign.calculateTokenAllocation(1 ether);
        assertGt(allocation, 0);

        // Later in campaign should give less allocation
        fastForwardTime(CAMPAIGN_DURATION / 2);
        uint256 laterAllocation = campaign.calculateTokenAllocation(1 ether);
        assertLt(laterAllocation, allocation);
    }

    function test_GetContributors() public {
        contributeToCompaign(campaignId, contributor1, 1 ether);
        contributeToCompaign(campaignId, contributor2, 2 ether);

        address[] memory contributors = campaign.getContributors();
        assertEq(contributors.length, 2);
        assertEq(contributors[0], contributor1);
        assertEq(contributors[1], contributor2);
    }
}
