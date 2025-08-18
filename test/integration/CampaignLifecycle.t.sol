// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract CampaignLifecycleTest is BaseTest {
    function test_FullLifecycle_TraditionalWithdrawal() public {
        // 1. Create campaign
        uint256 campaignId = createTestCampaign();
        Campaign campaign = getCampaign(campaignId);

        // Verify initial state
        assertCampaignState(campaignId, CampaignState.Active);

        // 2. Multiple contributions
        uint256 contrib1 = 3000e6; // 3000 USDC
        uint256 contrib2 = 4000e6; // 4000 USDC
        uint256 contrib3 = 3000e6; // 3000 USDC

        contributeToCompaign(campaignId, contributor1, contrib1);
        contributeToCompaign(campaignId, contributor2, contrib2);
        contributeToCompaign(campaignId, contributor3, contrib3);

        // Verify contributions recorded
        assertContributionExists(campaignId, contributor1, contrib1);
        assertContributionExists(campaignId, contributor2, contrib2);
        assertContributionExists(campaignId, contributor3, contrib3);

        // 3. Reach funding goal
        campaign.updateCampaignState();
        assertCampaignState(campaignId, CampaignState.Succeeded);

        // 4. Creator withdraws funds
        uint256 creatorInitialBalance = usdcToken.balanceOf(creator);
        vm.prank(creator);
        campaign.withdrawFunds();

        assertEq(usdcToken.balanceOf(creator), creatorInitialBalance + FUNDING_GOAL);
        assertCampaignState(campaignId, CampaignState.FundsWithdrawn);

        // 5. Contributors claim tokens
        vm.prank(contributor1);
        campaign.claimTokens();

        vm.prank(contributor2);
        campaign.claimTokens();

        vm.prank(contributor3);
        campaign.claimTokens();

        // 6. Verify final state
        CampaignData memory data = campaign.getCampaignDetails();

        // Check contributors have tokens
        assertGt(IERC20(data.tokenAddress).balanceOf(contributor1), 0);
        assertGt(IERC20(data.tokenAddress).balanceOf(contributor2), 0);
        assertGt(IERC20(data.tokenAddress).balanceOf(contributor3), 0);

        // Check creator has reserve tokens
        assertGt(IERC20(data.tokenAddress).balanceOf(creator), 0);

        // Verify all contributions marked as claimed
        assertTrue(campaign.getContribution(contributor1).claimed);
        assertTrue(campaign.getContribution(contributor2).claimed);
        assertTrue(campaign.getContribution(contributor3).claimed);
    }

    function test_FullLifecycle_TokenLaunch() public {
        // 1. Create campaign
        uint256 campaignId = createTestCampaign();
        Campaign campaign = getCampaign(campaignId);

        // 2. Contributions with early bonuses
        uint256 earlyContrib = 2000e6; // 2000 USDC
        contributeToCompaign(campaignId, contributor1, earlyContrib);

        // Fast forward partially through campaign
        fastForwardTime(CAMPAIGN_DURATION / 3);

        uint256 lateContrib = 8000e6; // 8000 USDC
        contributeToCompaign(campaignId, contributor2, lateContrib);

        // 3. Campaign succeeds
        campaign.updateCampaignState();
        assertCampaignState(campaignId, CampaignState.Succeeded);

        // 4. Creator launches token on DEX
        vm.prank(creator);
        campaign.createLiquidityPool();

        assertCampaignState(campaignId, CampaignState.TokenLaunched);

        // 5. Verify liquidity pool creation
        CampaignData memory data = campaign.getCampaignDetails();

        // Creator should have received remaining USDC after liquidity
        // uint256 expectedLiquidityUSDC = (FUNDING_GOAL * LIQUIDITY_PERCENTAGE) / 100;
        // uint256 expectedRemainingUSDC = FUNDING_GOAL - expectedLiquidityUSDC;

        // 6. Contributors can claim tokens
        vm.prank(contributor1);
        campaign.claimTokens();

        vm.prank(contributor2);
        campaign.claimTokens();

        // Verify token trading is enabled
        assertGt(IERC20(data.tokenAddress).balanceOf(contributor1), 0);
        assertGt(IERC20(data.tokenAddress).balanceOf(contributor2), 0);
    }

    function test_FailedCampaign_RefundFlow() public {
        // 1. Create campaign with goal requirement
        uint256 campaignId = createTestCampaignWithGoalRequired();
        Campaign campaign = getCampaign(campaignId);

        // 2. Partial contributions
        uint256 contrib1 = 3000e6; // 3000 USDC
        uint256 contrib2 = 2000e6; // 2000 USDC

        contributeToCompaign(campaignId, contributor1, contrib1);
        contributeToCompaign(campaignId, contributor2, contrib2);

        assertEq(campaign.getCampaignDetails().totalRaised, contrib1 + contrib2);
        assertLt(campaign.getCampaignDetails().totalRaised, FUNDING_GOAL);

        // 3. Deadline passes without reaching goal
        fastForwardToDeadline(campaignId);
        campaign.updateCampaignState();

        // 4. Campaign marked as failed
        assertCampaignState(campaignId, CampaignState.Failed);

        // 5. Contributors get refunds
        uint256 contrib1InitialBalance = usdcToken.balanceOf(contributor1);
        uint256 contrib2InitialBalance = usdcToken.balanceOf(contributor2);

        vm.prank(contributor1);
        campaign.refund();

        vm.prank(contributor2);
        campaign.refund();

        assertEq(usdcToken.balanceOf(contributor1), contrib1InitialBalance + contrib1);
        assertEq(usdcToken.balanceOf(contributor2), contrib2InitialBalance + contrib2);

        // 6. No tokens distributed
        CampaignData memory data = campaign.getCampaignDetails();
        assertEq(IERC20(data.tokenAddress).totalSupply(), 0);

        // Verify contribution amounts reset
        assertEq(campaign.getContribution(contributor1).amount, 0);
        assertEq(campaign.getContribution(contributor2).amount, 0);
    }

    function test_CampaignExtension_Success() public {
        uint256 campaignId = createTestCampaign();
        Campaign campaign = getCampaign(campaignId);

        // Partially fund campaign
        contributeToCompaign(campaignId, contributor1, FUNDING_GOAL / 2);

        // Extend deadline
        uint256 extension = 7 days;
        uint256 originalDeadline = campaign.getCampaignDetails().deadline;
        uint256 newDeadline = originalDeadline + extension;

        vm.prank(creator);
        campaign.extendDeadline(newDeadline);

        assertEq(campaign.getCampaignDetails().deadline, newDeadline);

        // Should still be active after original deadline
        vm.warp(originalDeadline + 1);
        campaign.updateCampaignState();
        assertCampaignState(campaignId, CampaignState.Active);

        // Complete funding in extended period
        contributeToCompaign(campaignId, contributor2, FUNDING_GOAL / 2);
        campaign.updateCampaignState();
        assertCampaignState(campaignId, CampaignState.Succeeded);
    }

    function test_EarlyWithdrawal_vs_GoalRequired() public {
        // Create two campaigns: one flexible, one strict
        uint256 flexibleCampaignId = createTestCampaign(); // allowEarlyWithdrawal = true
        uint256 strictCampaignId = createTestCampaignWithGoalRequired(); // allowEarlyWithdrawal = false

        Campaign flexibleCampaign = getCampaign(flexibleCampaignId);
        Campaign strictCampaign = getCampaign(strictCampaignId);

        // Partially fund both campaigns
        uint256 partialAmount = FUNDING_GOAL / 2;
        contributeToCompaign(flexibleCampaignId, contributor1, partialAmount);
        contributeToCompaign(strictCampaignId, contributor2, partialAmount);

        // Fast forward to deadline
        fastForwardToDeadline(flexibleCampaignId);
        fastForwardToDeadline(strictCampaignId);

        // Update states
        flexibleCampaign.updateCampaignState();
        strictCampaign.updateCampaignState();

        // Flexible campaign should succeed, strict should fail
        assertCampaignState(flexibleCampaignId, CampaignState.Succeeded);
        assertCampaignState(strictCampaignId, CampaignState.Failed);

        // Flexible campaign allows withdrawal and token claiming
        vm.prank(creator);
        flexibleCampaign.withdrawFunds();

        vm.prank(contributor1);
        flexibleCampaign.claimTokens();

        // Strict campaign allows refunds
        vm.prank(contributor2);
        strictCampaign.refund();
    }

    function test_MultipleCampaigns_SameCreator() public {
        vm.startPrank(creator);

        uint256 campaign1Id = factory.createCampaign(
            "ipfs://campaign1",
            5000e6, // 5000 USDC
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            true,
            "Token 1",
            "TK1"
        );

        uint256 campaign2Id = factory.createCampaign(
            "ipfs://campaign2",
            15000e6, // 15000 USDC
            CAMPAIGN_DURATION * 2,
            30, // Different reserve
            50, // Different liquidity
            false,
            "Token 2",
            "TK2"
        );

        vm.stopPrank();

        // Fund both campaigns differently
        contributeToCompaign(campaign1Id, contributor1, 5000e6); // Fully fund
        contributeToCompaign(campaign2Id, contributor2, 10000e6); // Partially fund

        Campaign campaign1 = getCampaign(campaign1Id);
        Campaign campaign2 = getCampaign(campaign2Id);

        campaign1.updateCampaignState();
        campaign2.updateCampaignState();

        // Campaign 1 should succeed
        assertCampaignState(campaign1Id, CampaignState.Succeeded);
        // Campaign 2 should still be active
        assertCampaignState(campaign2Id, CampaignState.Active);

        // Verify creator can manage both
        vm.prank(creator);
        campaign1.withdrawFunds();

        vm.prank(creator);
        campaign2.extendDeadline(block.timestamp + CAMPAIGN_DURATION * 3);

        uint256[] memory creatorCampaigns = factory.getCampaignsByCreator(creator);
        assertEq(creatorCampaigns.length, 2);
        assertEq(creatorCampaigns[0], campaign1Id);
        assertEq(creatorCampaigns[1], campaign2Id);
    }

    function test_ContributorAcrossMultipleCampaigns() public {
        uint256 campaign1Id = createTestCampaign();

        vm.prank(makeAddr("anotherCreator"));
        uint256 campaign2Id =
            factory.createCampaign("ipfs://campaign2", 8000e6, CAMPAIGN_DURATION, 25, 40, true, "Token 2", "TK2");

        // Contributor participates in both campaigns
        contributeToCompaign(campaign1Id, contributor1, 5000e6); // 5000 USDC
        contributeToCompaign(campaign2Id, contributor1, 4000e6); // 4000 USDC

        Campaign campaign1 = getCampaign(campaign1Id);
        Campaign campaign2 = getCampaign(campaign2Id);

        // Complete both campaigns
        contributeToCompaign(campaign1Id, contributor2, 5000e6); // 5000 USDC
        contributeToCompaign(campaign2Id, contributor2, 4000e6); // 4000 USDC

        campaign1.updateCampaignState();
        campaign2.updateCampaignState();

        // Contributor can claim tokens from both
        vm.startPrank(contributor1);
        campaign1.claimTokens();
        campaign2.claimTokens();
        vm.stopPrank();

        // Verify tokens from both campaigns
        CampaignData memory data1 = campaign1.getCampaignDetails();
        CampaignData memory data2 = campaign2.getCampaignDetails();

        assertGt(IERC20(data1.tokenAddress).balanceOf(contributor1), 0);
        assertGt(IERC20(data2.tokenAddress).balanceOf(contributor1), 0);

        // Tokens should be from different contracts
        assertTrue(data1.tokenAddress != data2.tokenAddress);
    }
}
