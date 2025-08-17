// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

contract CampaignLifecycleTest is CampaignFixtures {
    // ============ Successful Campaign Flow ============

    function test_lifecycle_CreateToWithdraw_Success() public {
        // 1. Create campaign
        (Campaign campaign, CampaignToken token) = createBasicCampaign();
        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));

        // 2. Multiple contributions
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 6 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 5 ether}();

        // 3. Verify goal reached (note: no automatic state change in new model)
        assertTrue(campaign.checkGoalReached());
        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));

        // 4. Verify tokens were minted
        assertGt(token.balanceOf(CONTRIBUTOR_1), 0);
        assertGt(token.balanceOf(CONTRIBUTOR_2), 0);

        // 5. Creator withdraws funds
        uint256 creatorBalanceBefore = CREATOR.balance;
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        // 6. Verify final state
        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));
        assertGt(CREATOR.balance, creatorBalanceBefore);
        assertTrue(campaign.creatorWithdrawn());
    }

    function test_lifecycle_CreateToTokenLaunch_Success() public {
        // 1. Create and fund campaign
        (Campaign campaign, CampaignToken token) = createBasicCampaign();
        contributeAndReachGoal(campaign);

        // 2. Launch token directly (without withdrawal)
        DEXLaunchConfig memory dexConfig = DEXLaunchConfig({
            router: address(mockRouter),
            liquidityTokens: 100000 * 1e18,
            liquidityETH: 5 ether,
            lockDuration: 365 days,
            listingPrice: 1e15, // 0.001 ETH per token
            burnRemainingTokens: true
        });

        // Mock ETH for liquidity
        vm.deal(address(campaign), 5 ether);

        vm.prank(CREATOR);
        campaign.launchToken(dexConfig);

        // 3. Verify final state
        assertEq(uint256(campaign.state()), uint256(CampaignState.TokenLaunched));
        assertTrue(token.transfersEnabled());
        assertTrue(campaign.liquidityPair() != address(0));
    }

    // ============ Failed Campaign Flow ============

    function test_lifecycle_CreateToFailed_Refunds() public {
        // 1. Create campaign and make some contributions
        (Campaign campaign, CampaignToken token) = createBasicCampaign();

        uint256 contribution1 = 2 ether;
        uint256 contribution2 = 3 ether;

        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: contribution1}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: contribution2}();

        // 2. Let campaign expire without reaching goal
        vm.warp(block.timestamp + 31 days); // Past the default 30-day duration

        // 3. In new model, campaigns don't auto-fail, so manually cancel
        vm.prank(ADMIN);
        campaign.cancelCampaign();

        // 4. Contributors claim refunds
        uint256 balance1Before = CONTRIBUTOR_1.balance;
        uint256 balance2Before = CONTRIBUTOR_2.balance;

        vm.prank(CONTRIBUTOR_1);
        campaign.claimRefund();

        vm.prank(CONTRIBUTOR_2);
        campaign.claimRefund();

        // 5. Verify refunds and token burning
        assertEq(CONTRIBUTOR_1.balance, balance1Before + contribution1);
        assertEq(CONTRIBUTOR_2.balance, balance2Before + contribution2);
        assertEq(token.balanceOf(CONTRIBUTOR_1), 0);
        assertEq(token.balanceOf(CONTRIBUTOR_2), 0);
    }

    // ============ Cancelled Campaign Flow ============

    function test_lifecycle_CreateToCancelled_Refunds() public {
        // 1. Create campaign and make contributions
        (Campaign campaign, CampaignToken token) = createBasicCampaign();

        uint256 contribution = 3 ether;
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: contribution}();

        // 2. Creator cancels campaign
        vm.prank(CREATOR);
        campaign.cancelCampaign();

        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));

        // 3. Contributor claims refund
        uint256 balanceBefore = CONTRIBUTOR_1.balance;

        vm.prank(CONTRIBUTOR_1);
        campaign.claimRefund();

        assertEq(CONTRIBUTOR_1.balance, balanceBefore + contribution);
        assertEq(token.balanceOf(CONTRIBUTOR_1), 0);
    }

    // ============ Multi-Campaign Integration ============

    function test_integration_MultipleCampaigns_Isolated() public {
        // 1. Create two campaigns
        (Campaign campaign1,) = createBasicCampaign();

        TokenConfig memory tokenConfig2 = createDefaultTokenConfig();
        tokenConfig2.symbol = "TEST2";

        vm.prank(CREATOR);
        (address addr2,) =
            factory.createCampaign{value: 0.01 ether}(createDefaultCampaignConfig(), tokenConfig2, createDefaultTiers());
        Campaign campaign2 = Campaign(payable(addr2));

        // Register second campaign with mock factory for treasury validation
        mockFactory.registerCampaign(1, addr2);

        // 2. Contribute to both campaigns
        vm.prank(CONTRIBUTOR_1);
        campaign1.contribute{value: 5 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign2.contribute{value: 7 ether}();

        // 3. Verify isolation
        assertEq(campaign1.totalRaised(), 5 ether);
        assertEq(campaign2.totalRaised(), 7 ether);
        assertEq(campaign1.totalContributors(), 1);
        assertEq(campaign2.totalContributors(), 1);

        // 4. One succeeds (by withdrawal), one fails
        vm.prank(CONTRIBUTOR_1);
        campaign1.contribute{value: 6 ether}(); // Reach goal

        // Creator withdraws from campaign1
        vm.prank(CREATOR);
        campaign1.withdrawFunds();

        vm.warp(block.timestamp + 31 days); // Past the default 30-day duration
        vm.prank(ADMIN);
        campaign2.cancelCampaign();

        // 5. Verify different final states
        assertEq(uint256(campaign1.state()), uint256(CampaignState.Withdrawn));
        assertEq(uint256(campaign2.state()), uint256(CampaignState.Cancelled));
    }

    // ============ Edge Case Flows ============

    function test_lifecycle_ExactGoalReached_Success() public {
        (Campaign campaign,) = createBasicCampaign();
        uint256 exactGoal = 10 ether; // Default funding goal

        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: exactGoal}();

        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));
        assertTrue(campaign.checkGoalReached());
    }

    function test_lifecycle_LastMinuteContribution_Success() public {
        (Campaign campaign,) = createBasicCampaign();

        // Contribute at the last block before deadline
        vm.warp(block.timestamp + 30 days - 1); // Just before the 30-day deadline

        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 15 ether}();

        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));
    }

    function test_lifecycle_HardCapReached_StopsContributions() public {
        (Campaign campaign,) = createBasicCampaign();
        uint256 hardCap = 50 ether; // Default hard cap

        // Contribute up to hard cap
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: hardCap}();

        // Additional contributions should fail
        vm.prank(CONTRIBUTOR_2);
        vm.expectRevert("Hard cap exceeded");
        campaign.contribute{value: 1 ether}();
    }

    // ============ State Transition Validation ============

    function test_lifecycle_InvalidStateTransition_Reverts() public {
        (Campaign campaign,) = createBasicCampaign();

        // In new model, creator can withdraw from Active state if there are funds
        contributeAndReachGoal(campaign);

        // Try to claim refund from Active state (should fail unless cancelled)
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Refunds not available");
        campaign.claimRefund();
    }

    function test_lifecycle_WithdrawThenTokenLaunch_Success() public {
        (Campaign campaign,) = createBasicCampaign();
        contributeAndReachGoal(campaign);

        // 1. Withdraw funds first
        vm.prank(CREATOR);
        campaign.withdrawFunds();
        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));

        // 2. Then launch token
        DEXLaunchConfig memory dexConfig = DEXLaunchConfig({
            router: address(mockRouter),
            liquidityTokens: 100000 * 1e18,
            liquidityETH: 5 ether,
            lockDuration: 365 days,
            listingPrice: 1e15,
            burnRemainingTokens: true
        });

        vm.deal(address(campaign), 5 ether);

        vm.prank(CREATOR);
        campaign.launchToken(dexConfig);

        assertEq(uint256(campaign.state()), uint256(CampaignState.TokenLaunched));
    }

    // ============ Medical Verification Lifecycle ============

    function test_lifecycle_MedicalVerificationFlow() public {
        // 1. Create campaign for medical emergency
        (Campaign campaign, CampaignToken token) = createBasicCampaign();

        // 2. Upload medical verification
        vm.prank(CREATOR);
        campaign.uploadVerification(
            "QmMedicalEmergencyDoc123", "Emergency heart surgery required - hospital estimate $75,000"
        );
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));

        // 3. Contributors support medical cause
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 8 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 7 ether}();

        // 4. Immediate withdrawal for medical emergency
        vm.prank(CREATOR);
        campaign.withdrawFunds();
        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));

        // 5. Campaign continues accepting support
        vm.prank(makeAddr("additionalDonor"));
        campaign.contribute{value: 2 ether}();

        // 6. Update verification with treatment progress
        vm.prank(CREATOR);
        campaign.updateVerification(
            "QmTreatmentProgressDoc", "Surgery completed successfully - providing recovery documentation"
        );

        assertEq(campaign.totalRaised(), 17 ether);
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }

    function test_lifecycle_CommunityVotingFlow() public {
        // 1. Create campaign and get contributions
        (Campaign campaign, CampaignToken token) = createBasicCampaign();

        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 6 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 4 ether}();

        // 2. Community detects suspicious activity
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Campaign appears fraudulent - fake medical documents");

        // 3. Community votes to invalidate
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Evidence suggests fraud");

        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Invalid, "Agree - likely fraudulent");

        // 4. Vote execution cancels campaign
        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));

        // 5. Contributors claim refunds
        uint256 balance1Before = CONTRIBUTOR_1.balance;
        uint256 balance2Before = CONTRIBUTOR_2.balance;

        vm.prank(CONTRIBUTOR_1);
        campaign.claimRefund();

        vm.prank(CONTRIBUTOR_2);
        campaign.claimRefund();

        assertGt(CONTRIBUTOR_1.balance, balance1Before);
        assertGt(CONTRIBUTOR_2.balance, balance2Before);
    }

    function test_lifecycle_VerificationWithSuccessfulVoteDefense() public {
        // 1. Medical campaign with verification
        (Campaign campaign, CampaignToken token) = createBasicCampaign();

        vm.prank(CREATOR);
        campaign.uploadVerification("QmLegitimateDoc", "Legitimate medical emergency with hospital documentation");

        // 2. Get diverse contributor base
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 3 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 2 ether}();

        address contributor3 = makeAddr("contributor3");
        vm.prank(contributor3);
        campaign.contribute{value: 5 ether}(); // Largest contributor

        // 3. Someone questions legitimacy
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Questioning the legitimacy of this campaign");

        // 4. Majority defends the campaign
        vm.prank(contributor3); // 50% voting power
        campaign.castVote(0, VoteType.Valid, "Documentation looks legitimate");

        vm.prank(CONTRIBUTOR_2); // 20% voting power
        campaign.castVote(0, VoteType.Valid, "Verified with hospital");

        vm.prank(CONTRIBUTOR_1); // 30% voting power
        campaign.castVote(0, VoteType.Invalid, "Still suspicious");

        // 5. Vote fails (70% voted valid, 30% invalid)
        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));

        // 6. Campaign proceeds normally
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));
        assertTrue(campaign.creatorWithdrawn());
    }
}
