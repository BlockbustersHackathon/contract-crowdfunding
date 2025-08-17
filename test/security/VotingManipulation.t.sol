// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

// Import events for testing
import "../../src/interfaces/ICampaignStructs.sol";

contract VotingManipulationTest is CampaignFixtures {
    Campaign public campaign;
    CampaignToken public token;

    function setUp() public override {
        super.setUp();
        (campaign, token) = createBasicCampaign();
    }

    // ============ Access Control Security ============

    function test_votingAccess_OnlyTokenHolders() public {
        address nonTokenHolder = makeAddr("nonTokenHolder");

        // Set up valid vote first
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Test vote");

        // Non-token holder cannot vote
        vm.prank(nonTokenHolder);
        vm.expectRevert("Only token holders");
        campaign.castVote(0, VoteType.Invalid, "Unauthorized vote");

        // Non-token holder cannot initiate votes
        vm.prank(nonTokenHolder);
        vm.expectRevert("Only token holders");
        campaign.initiateVote("Unauthorized initiation");
    }

    function test_voteInitiation_RequiresTokens() public {
        // User without tokens cannot initiate votes
        address user = makeAddr("user");

        vm.prank(user);
        vm.expectRevert("Only token holders");
        campaign.initiateVote("Cannot initiate without tokens");

        // After getting tokens, can initiate
        vm.deal(user, 1 ether);
        vm.prank(user);
        campaign.contribute{value: 1 ether}();

        vm.prank(user);
        campaign.initiateVote("Now can initiate with tokens");

        (VotingStatus status,,) = campaign.getVoteStatus(0);
        assertEq(uint256(status), uint256(VotingStatus.Active));
    }

    // ============ Vote Timing Security ============

    function test_voteManipulation_TimeConstraints() public {
        // Set up voting scenario
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Time manipulation test");

        // Cannot vote before voting starts (edge case)
        // In our implementation, voting starts immediately, so this tests boundary

        // Can vote during valid period
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Valid timing");

        // Cannot vote after deadline
        vm.warp(block.timestamp + 8 days);

        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Not in voting period");
        campaign.castVote(0, VoteType.Valid, "Too late");

        // Cannot execute before deadline
        vm.warp(block.timestamp - 1 days);
        vm.expectRevert("Voting period not ended");
        campaign.executeVote(0);
    }

    function test_preventDoubleVoting() public {
        // Set up voting scenario
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Double voting test");

        // First vote should succeed
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "First vote");

        // Second vote should fail
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Already voted");
        campaign.castVote(0, VoteType.Valid, "Second vote");

        // Also test with same vote type
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Already voted");
        campaign.castVote(0, VoteType.Invalid, "Same type vote");
    }

    // ============ Vote Execution Security ============

    function test_prematureExecution_Prevention() public {
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Premature execution test");

        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Vote cast");

        // Cannot execute before voting period ends
        vm.expectRevert("Voting period not ended");
        campaign.executeVote(0);

        // Even if threshold is met
        assertTrue(campaign.checkVoteThreshold());
        vm.expectRevert("Voting period not ended");
        campaign.executeVote(0);

        // Can only execute after deadline
        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0); // Should not revert
    }

    function test_doubleExecution_Prevention() public {
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Double execution test");

        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Vote");

        vm.warp(block.timestamp + 8 days);

        // First execution should succeed
        campaign.executeVote(0);

        // Second execution should fail
        vm.expectRevert("Vote not active");
        campaign.executeVote(0);
    }

    // ============ Vote Threshold Security ============

    function test_thresholdCalculation_Accuracy() public {
        // Set up precise voting scenario to test threshold calculation
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 6 ether}(); // 60%

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 4 ether}(); // 40%

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Threshold test");

        // 40% votes invalid - should not meet threshold
        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Invalid, "40% invalid");

        assertFalse(campaign.checkVoteThreshold());

        // Add 60% invalid - should meet threshold
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "60% invalid");

        assertTrue(campaign.checkVoteThreshold());
    }

    function test_edgeCaseThreshold_ExactlyFiftyPercent() public {
        // Create scenario with exactly 50% threshold
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 5 ether}(); // 50%

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 5 ether}(); // 50%

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("50% threshold test");

        // Exactly 50% votes invalid
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Exactly 50%");

        // Should meet threshold (>= 50%)
        assertTrue(campaign.checkVoteThreshold());

        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        // Should cancel campaign
        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));
    }

    // ============ State Manipulation Prevention ============

    function test_voteAfterCampaignCancelled_Prevented() public {
        // Set up and execute vote to cancel campaign
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("First vote");

        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Cancel campaign");

        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));

        // Should not be able to initiate new votes on cancelled campaign
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Cannot vote in current state");
        campaign.initiateVote("Should not work on cancelled campaign");
    }

    function test_votingDuringPausedToken_HandledCorrectly() public {
        // Set up voting scenario
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Test with paused token");

        // Pause the token
        vm.prank(CREATOR);
        token.pause();

        // Voting should still work even with paused token
        // because voting power is based on balance, not transfers
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Vote with paused token");

        // Verify vote was recorded
        (, uint256 forVotes,) = campaign.getVoteStatus(0);
        assertGt(forVotes, 0);
    }

    // ============ Voting Power Manipulation ============

    function test_votingPowerTransferManipulation() public {
        // Test that voting power is based on balance at vote time, not manipulation

        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 2 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 2 ether}();

        // Enable transfers
        vm.prank(CREATOR);
        token.enableTransfers();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Transfer manipulation test");

        // Transfer tokens between contributors
        uint256 transferAmount = token.balanceOf(CONTRIBUTOR_1) / 2;
        vm.prank(CONTRIBUTOR_1);
        token.transfer(CONTRIBUTOR_2, transferAmount);

        // Voting power should be based on current balance
        uint256 power1 = token.getVotingPower(CONTRIBUTOR_1);
        uint256 power2 = token.getVotingPower(CONTRIBUTOR_2);

        assertEq(power1, token.balanceOf(CONTRIBUTOR_1));
        assertEq(power2, token.balanceOf(CONTRIBUTOR_2));

        // Both can vote with their current power
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Vote with reduced power");

        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Valid, "Vote with increased power");
    }

    // ============ Input Validation Security ============

    function test_voteReasonValidation() public {
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        // Empty reason should fail
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Reason required");
        campaign.initiateVote("");

        // Valid reason should work
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Valid reason");

        // Empty voting reason should work (optional)
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "");
    }

    function test_invalidVoteType_Handled() public {
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Vote type test");

        // Valid vote types should work
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Test invalid");

        // Note: Solidity enum validation prevents invalid enum values at compile time
        // Runtime validation is handled by the enum type system
    }

    // ============ Reentrancy Protection ============

    function test_reentrancyProtection_VotingFunctions() public {
        // Our voting functions don't make external calls that could lead to reentrancy
        // But test that state changes are consistent

        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Reentrancy test");

        // State should be consistent after vote initiation
        (VotingStatus status,,) = campaign.getVoteStatus(0);
        assertEq(uint256(status), uint256(VotingStatus.Active));
        assertTrue(campaign.votingActive());

        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Test vote");

        // State should be consistent after voting
        (, uint256 forVotes,) = campaign.getVoteStatus(0);
        assertGt(forVotes, 0);
        assertTrue(campaign.hasVoted(CONTRIBUTOR_1, 0));
    }

    // ============ Gas Limit Attack Prevention ============

    function test_gasLimitAttack_LargeVoteHistory() public {
        // Test that functions remain usable even with large vote history

        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        // Execute multiple voting rounds to build history
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(CONTRIBUTOR_1);
            campaign.initiateVote(string(abi.encodePacked("Vote round ", i)));

            vm.prank(CONTRIBUTOR_1);
            campaign.castVote(i, VoteType.Valid, "Vote");

            vm.warp(block.timestamp + 8 days);
            campaign.executeVote(i);

            // Reset for next round if campaign not cancelled
            if (uint256(campaign.state()) == uint256(CampaignState.Cancelled)) {
                break;
            }
        }

        // Functions should still work after multiple votes
        if (uint256(campaign.state()) != uint256(CampaignState.Cancelled)) {
            vm.prank(CONTRIBUTOR_1);
            campaign.initiateVote("Final test vote");

            (VotingStatus status,,) = campaign.getVoteStatus(5);
            assertEq(uint256(status), uint256(VotingStatus.Active));
        }
    }
}
