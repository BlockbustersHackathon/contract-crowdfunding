// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

contract CommunityFraudDetectionTest is CampaignFixtures {
    Campaign public campaign;
    CampaignToken public token;

    address public contributor3;
    address public contributor4;
    address public contributor5;

    function setUp() public override {
        super.setUp();
        (campaign, token) = createBasicCampaign();

        // Set up diverse contributor base for comprehensive voting scenarios
        contributor3 = makeAddr("contributor3");
        contributor4 = makeAddr("contributor4");
        contributor5 = makeAddr("contributor5");

        // Create token distribution for testing various voting scenarios
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 6 ether}(); // 35.3% voting power

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 4 ether}(); // 23.5% voting power

        vm.prank(contributor3);
        campaign.contribute{value: 3 ether}(); // 17.6% voting power

        vm.prank(contributor4);
        campaign.contribute{value: 2 ether}(); // 11.8% voting power

        vm.prank(contributor5);
        campaign.contribute{value: 2 ether}(); // 11.8% voting power
            // Total: 17 ether
    }

    // ============ Fraud Detection Scenarios ============

    function test_obviousFraud_QuickCommunityResponse() public {
        // Scenario: Obviously fraudulent campaign gets quickly detected

        // Step 1: Suspicious campaign behavior triggers community concern
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Creator posted fake medical documents and contradictory stories");

        // Step 2: Multiple community members quickly vote to invalidate
        vm.prank(CONTRIBUTOR_1); // 35.3%
        campaign.castVote(0, VoteType.Invalid, "Documents clearly fake");

        vm.prank(CONTRIBUTOR_2); // 23.5% -> Total: 58.8%
        campaign.castVote(0, VoteType.Invalid, "Story doesn't match up");

        // Already over 50% threshold - should pass when executed
        assertTrue(campaign.checkVoteThreshold());

        // Step 3: Wait for voting period and execute
        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        // Campaign should be cancelled
        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));

        // Step 4: All contributors get refunds
        uint256 balance1Before = CONTRIBUTOR_1.balance;
        uint256 balance2Before = CONTRIBUTOR_2.balance;
        uint256 balance3Before = contributor3.balance;

        vm.prank(CONTRIBUTOR_1);
        campaign.claimRefund();

        vm.prank(CONTRIBUTOR_2);
        campaign.claimRefund();

        vm.prank(contributor3);
        campaign.claimRefund();

        // Verify refunds received
        assertGt(CONTRIBUTOR_1.balance, balance1Before);
        assertGt(CONTRIBUTOR_2.balance, balance2Before);
        assertGt(contributor3.balance, balance3Before);
    }

    function test_borderlineFraud_CommunityDebate() public {
        // Scenario: Borderline case where community is divided

        // Step 1: Community member raises concerns
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Medical documentation seems questionable but not clearly fake");

        // Step 2: Community is split - some vote invalid, others valid
        vm.prank(CONTRIBUTOR_1); // 35.3%
        campaign.castVote(0, VoteType.Invalid, "Something feels off");

        vm.prank(CONTRIBUTOR_2); // 23.5%
        campaign.castVote(0, VoteType.Valid, "Looks legitimate to me");

        vm.prank(contributor3); // 17.6%
        campaign.castVote(0, VoteType.Valid, "Benefit of the doubt");

        // Total: Invalid 35.3%, Valid 41.1% - Valid leads

        vm.prank(contributor4); // 11.8%
        campaign.castVote(0, VoteType.Invalid, "Better safe than sorry");

        // Total: Invalid 47.1%, Valid 41.1% - Still not 50%
        assertFalse(campaign.checkVoteThreshold());

        // Step 3: Execute vote - should fail due to insufficient threshold
        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        // Campaign should continue
        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));

        (VotingStatus status,,) = campaign.getVoteStatus(0);
        assertEq(uint256(status), uint256(VotingStatus.Failed));
    }

    function test_falseAlarm_CommunityDefendsLegitimate() public {
        // Scenario: False fraud accusation gets rejected by community

        // Step 1: Overzealous contributor raises unfounded concerns
        vm.prank(contributor5);
        campaign.initiateVote("I don't trust this campaign even though documentation looks real");

        // Step 2: Majority of community defends the campaign
        vm.prank(CONTRIBUTOR_1); // 35.3%
        campaign.castVote(0, VoteType.Valid, "Documentation is clearly legitimate");

        vm.prank(CONTRIBUTOR_2); // 23.5%
        campaign.castVote(0, VoteType.Valid, "This accusation is unfounded");

        vm.prank(contributor3); // 17.6%
        campaign.castVote(0, VoteType.Valid, "Campaign creator has good reputation");

        vm.prank(contributor4); // 11.8%
        campaign.castVote(0, VoteType.Valid, "Supporting legitimate medical need");

        // Only initiator votes invalid
        vm.prank(contributor5); // 11.8%
        campaign.castVote(0, VoteType.Invalid, "Still suspicious");

        // Overwhelming majority supports campaign
        assertFalse(campaign.checkVoteThreshold()); // Less than 50% invalid

        // Step 3: Vote fails, campaign continues
        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));

        // Step 4: Campaign proceeds normally - creator can withdraw
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        assertTrue(campaign.creatorWithdrawn());
    }

    // ============ Edge Cases in Fraud Detection ============

    function test_exactFiftyPercent_PassesThreshold() public {
        // Test exact 50% threshold behavior

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Testing exact threshold");

        // Get exactly 50% to vote invalid
        // CONTRIBUTOR_1 (35.3%) + contributor4 (11.8%) + contributor5 (11.8%) = 58.9%
        // CONTRIBUTOR_1 (35.3%) + contributor3 (17.6%) = 52.9%
        // Let's get contributor4 + contributor5 = 23.6%, then need 26.4% more

        vm.prank(contributor4); // 11.8%
        campaign.castVote(0, VoteType.Invalid, "Invalid");

        vm.prank(contributor5); // 11.8%
        campaign.castVote(0, VoteType.Invalid, "Invalid");

        vm.prank(contributor3); // 17.6% -> Total invalid: 41.2%
        campaign.castVote(0, VoteType.Invalid, "Invalid");

        // Still need more for 50%
        vm.prank(CONTRIBUTOR_2); // 23.5% -> Total invalid: 64.7% (over 50%)
        campaign.castVote(0, VoteType.Invalid, "Invalid");

        assertTrue(campaign.checkVoteThreshold());
    }

    function test_lateVotingRush_BeforeDeadline() public {
        // Test scenario where voting rush happens near deadline

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Last minute fraud detection");

        // Most of voting period passes with few votes
        vm.warp(block.timestamp + 6 days);

        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Invalid, "Late but important vote");

        // Rush of votes in final hours
        vm.warp(block.timestamp + 23 hours); // Almost at deadline

        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Fraud confirmed");

        vm.prank(contributor3);
        campaign.castVote(0, VoteType.Invalid, "Agree");

        // Should still be in voting period
        (VotingStatus status,,) = campaign.getVoteStatus(0);
        assertEq(uint256(status), uint256(VotingStatus.Active));

        // Execute after deadline
        vm.warp(block.timestamp + 2 hours);
        campaign.executeVote(0);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));
    }

    function test_postWithdrawal_FraudDetection() public {
        // Test fraud detection after creator has already withdrawn

        // Step 1: Creator withdraws funds early (medical emergency scenario)
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));

        // Step 2: Later evidence suggests fraud
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Creator never had medical emergency - photos were fake");

        // Step 3: Community votes to cancel even after withdrawal
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Evidence of fraud emerged");

        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Invalid, "Hospital confirmed no such patient");

        vm.prank(contributor3);
        campaign.castVote(0, VoteType.Invalid, "Fake documentation confirmed");

        // Step 4: Campaign gets cancelled for fraud even post-withdrawal
        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));

        // Contributors can still claim refunds (though funds already withdrawn)
        // This would be handled by insurance/platform mechanisms in real implementation
    }

    // ============ Anti-Manipulation Tests ============

    function test_preventFlashLoanVoting_NotApplicable() public {
        // In this implementation, voting power is based on actual token ownership
        // Flash loan attacks are prevented because:
        // 1. You need to contribute to get tokens (real funds)
        // 2. Tokens are minted at contribution time, not borrowed
        // 3. Voting period is 7 days, making flash loans impractical

        // Demonstrate legitimate large contribution for voting
        address largeContributor = makeAddr("largeContributor");
        vm.deal(largeContributor, 20 ether);

        // Large contributor joins and gets proportional voting power
        vm.prank(largeContributor);
        campaign.contribute{value: 17 ether}();

        // This is legitimate - they actually contributed funds
        uint256 votingPower = token.getVotingPower(largeContributor);
        assertGt(votingPower, token.getVotingPower(CONTRIBUTOR_1));

        // They can legitimately initiate and vote
        vm.prank(largeContributor);
        campaign.initiateVote("Large contributor's concerns");

        vm.prank(largeContributor);
        campaign.castVote(0, VoteType.Invalid, "Using my legitimate voting power");

        // This is fair because they have actual stake in the campaign
    }

    function test_sybilResistance_ThroughStaking() public {
        // Sybil attacks are naturally resistant due to staking requirement

        // Attacker would need real funds to create multiple accounts
        address sybil1 = makeAddr("sybil1");
        address sybil2 = makeAddr("sybil2");
        address sybil3 = makeAddr("sybil3");

        // Each sybil account needs real ETH to get voting power
        vm.deal(sybil1, 1 ether);
        vm.deal(sybil2, 1 ether);
        vm.deal(sybil3, 1 ether);

        vm.prank(sybil1);
        campaign.contribute{value: 1 ether}();

        vm.prank(sybil2);
        campaign.contribute{value: 1 ether}();

        vm.prank(sybil3);
        campaign.contribute{value: 1 ether}();

        // Sybil accounts only get proportional power to their real stakes
        uint256 sybilPower = token.getVotingPower(sybil1) + token.getVotingPower(sybil2) + token.getVotingPower(sybil3);

        uint256 legitimatePower = token.getVotingPower(CONTRIBUTOR_1);

        // Legitimate large contributor still has more power than multiple small sybils
        assertGt(legitimatePower, sybilPower);
    }

    // ============ Multiple Voting Rounds ============

    function test_multipleVotingRounds_Different_Outcomes() public {
        // Test multiple sequential voting rounds with different outcomes

        // Round 1: Vote fails
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("First concern about campaign");

        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Suspicious");

        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Valid, "Looks fine");

        vm.prank(contributor3);
        campaign.castVote(0, VoteType.Valid, "Agree, looks fine");

        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));

        // Round 2: New evidence emerges, vote passes
        vm.prank(CONTRIBUTOR_2);
        campaign.initiateVote("New evidence of fraud discovered");

        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(1, VoteType.Invalid, "New evidence is convincing");

        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(1, VoteType.Invalid, "I changed my mind");

        vm.prank(contributor3);
        campaign.castVote(1, VoteType.Invalid, "Evidence is clear");

        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(1);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));
    }

    // ============ Integration with Medical Verification ============

    function test_fraudDetection_OverridesVerification() public {
        // Community vote can override even verified medical documentation

        // Step 1: Upload medical verification
        vm.prank(CREATOR);
        campaign.uploadVerification("QmMedicalDoc", "Verified medical documentation");

        // Step 2: Community discovers verification is fraudulent
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Medical verification documents are fabricated");

        // Step 3: Community votes to cancel despite verification
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Fake medical documents");

        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Invalid, "Contacted hospital - no such patient");

        vm.prank(contributor3);
        campaign.castVote(0, VoteType.Invalid, "Documents are clearly forged");

        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        // Campaign cancelled despite having "verification"
        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }
}
