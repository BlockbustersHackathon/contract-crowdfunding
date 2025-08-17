// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

contract MedicalVerificationIntegrationTest is CampaignFixtures {
    Campaign public campaign;
    CampaignToken public token;

    function setUp() public override {
        super.setUp();
        (campaign, token) = createBasicCampaign();
    }

    // ============ Full Medical Crowdfunding Flow ============

    function test_fullMedicalFlow_UploadThenWithdraw() public {
        // Step 1: Creator uploads medical verification
        vm.prank(CREATOR);
        campaign.uploadVerification(
            "QmMedicalReport123Hash", "Patient requires urgent heart surgery - estimated cost $50,000"
        );

        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));

        // Step 2: Contributors donate based on medical need
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 5 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 3 ether}();

        // Step 3: Creator immediately withdraws for urgent medical needs
        uint256 creatorBalanceBefore = CREATOR.balance;
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        // Verify withdrawal successful
        assertTrue(campaign.creatorWithdrawn());
        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));
        assertGt(CREATOR.balance, creatorBalanceBefore);

        // Step 4: Campaign can continue accepting donations even after withdrawal
        vm.prank(makeAddr("contributor3"));
        campaign.contribute{value: 2 ether}();

        assertEq(campaign.totalRaised(), 10 ether);
    }

    function test_medicalVerification_WithCommunityChallenge() public {
        // Step 1: Creator uploads verification
        vm.prank(CREATOR);
        campaign.uploadVerification("QmSuspiciousDocument", "Very urgent medical condition needs money immediately");

        // Step 2: Contributors donate
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 4 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 6 ether}();

        // Step 3: Community member suspects fraud despite verification
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Verification document looks fake - suspicious language and urgency");

        // Step 4: Community votes to invalidate
        vm.prank(CONTRIBUTOR_1);
        campaign.castVote(0, VoteType.Invalid, "Document formatting is suspicious");

        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Invalid, "Story doesn't add up");

        // Step 5: Vote passes and campaign is cancelled
        vm.warp(block.timestamp + 8 days);
        campaign.executeVote(0);

        assertEq(uint256(campaign.state()), uint256(CampaignState.Cancelled));

        // Step 6: Contributors get refunds
        uint256 balance1Before = CONTRIBUTOR_1.balance;
        uint256 balance2Before = CONTRIBUTOR_2.balance;

        vm.prank(CONTRIBUTOR_1);
        campaign.claimRefund();

        vm.prank(CONTRIBUTOR_2);
        campaign.claimRefund();

        assertGt(CONTRIBUTOR_1.balance, balance1Before);
        assertGt(CONTRIBUTOR_2.balance, balance2Before);
    }

    function test_medicalCampaign_UpdateVerificationAfterContributions() public {
        // Step 1: Initial contribution without verification
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 2 ether}();

        // Step 2: Creator adds verification documentation later
        vm.prank(CREATOR);
        campaign.uploadVerification(
            "QmDetailedMedicalReport",
            "Detailed medical report from certified hospital - pediatric emergency surgery required"
        );

        // Step 3: Verification increases confidence, more contributions come in
        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 3 ether}();

        vm.prank(makeAddr("contributor3"));
        campaign.contribute{value: 5 ether}();

        // Step 4: Creator updates verification with additional details
        vm.prank(CREATOR);
        campaign.updateVerification(
            "QmUpdatedMedicalReport", "Updated report with surgery date confirmation and hospital approval letter"
        );

        // Verification should be reset to pending after update
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));

        // Step 5: Withdrawal proceeds normally
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        assertTrue(campaign.creatorWithdrawn());
        assertEq(campaign.totalRaised(), 10 ether);
    }

    // ============ Medical Emergency Scenarios ============

    function test_urgentMedicalCase_ImmediateWithdrawalFlow() public {
        // Simulate urgent medical emergency requiring immediate funds

        // Step 1: Campaign created in emergency
        assertEq(uint256(campaign.state()), uint256(CampaignState.Active));

        // Step 2: Emergency donation comes in
        address emergencyDonor = makeAddr("emergencyDonor");
        vm.deal(emergencyDonor, 10 ether);
        vm.prank(emergencyDonor);
        campaign.contribute{value: 8 ether}();

        // Step 3: Creator immediately withdraws without verification (acceptable for emergencies)
        uint256 creatorBalanceBefore = CREATOR.balance;
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        assertGt(CREATOR.balance, creatorBalanceBefore);
        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));

        // Step 4: Creator can add verification later for transparency
        vm.prank(CREATOR);
        campaign.uploadVerification(
            "QmEmergencyMedicalProof",
            "Emergency surgery completed - providing post-surgery documentation for transparency"
        );

        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));

        // Step 5: Campaign continues to accept additional support
        vm.prank(makeAddr("additionalSupporter"));
        campaign.contribute{value: 1 ether}();

        assertEq(campaign.totalRaised(), 9 ether);
    }

    function test_medicalCampaign_TokenLaunchAfterSuccess() public {
        // Successful medical campaign transitions to token launch

        // Step 1: Medical verification uploaded
        vm.prank(CREATOR);
        campaign.uploadVerification(
            "QmInnovativeMedicalResearch",
            "Revolutionary medical research project with potential for breakthrough treatment"
        );

        // Step 2: Community supports medical research
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 15 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 10 ether}();

        // Step 3: Creator initially withdraws for research funding
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        // Step 4: Research shows promise, creator decides to launch token
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

        // Step 5: Token becomes tradeable, giving backers potential returns
        assertTrue(token.transfersEnabled());

        // Backers now have tokens that could appreciate if research succeeds
        assertGt(token.balanceOf(CONTRIBUTOR_1), 0);
        assertGt(token.balanceOf(CONTRIBUTOR_2), 0);
    }

    // ============ Complex Medical Verification Scenarios ============

    function test_multipleVerificationUpdates_DuringActiveVoting() public {
        // Test updating verification while community vote is active

        // Step 1: Upload initial verification
        vm.prank(CREATOR);
        campaign.uploadVerification("QmInitialDoc", "Initial medical documentation");

        // Step 2: Get contributions and tokens for voting
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 5 ether}();

        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 5 ether}();

        // Step 3: Community initiates vote due to concerns
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Initial documentation seems insufficient");

        // Step 4: Creator updates verification during voting period
        vm.prank(CREATOR);
        campaign.updateVerification(
            "QmDetailedDoc", "Comprehensive medical report with multiple physician confirmations"
        );

        // Step 5: Voting continues based on updated information
        vm.prank(CONTRIBUTOR_2);
        campaign.castVote(0, VoteType.Valid, "Updated documentation looks legitimate");

        // Vote should still be active and processable
        (VotingStatus status,,) = campaign.getVoteStatus(0);
        assertEq(uint256(status), uint256(VotingStatus.Active));
    }

    function test_verificationStatePersistence_ThroughCampaignStates() public {
        // Verification status should persist through campaign state changes

        // Step 1: Upload verification in Active state
        vm.prank(CREATOR);
        campaign.uploadVerification("QmPersistentDoc", "Medical documentation for tracking");
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));

        // Step 2: Contribute and withdraw (Active -> Withdrawn)
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 5 ether}();

        vm.prank(CREATOR);
        campaign.withdrawFunds();
        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));

        // Verification should still be accessible
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));

        // Step 3: Launch token (Withdrawn -> TokenLaunched)
        DEXLaunchConfig memory dexConfig = DEXLaunchConfig({
            router: address(mockRouter),
            liquidityTokens: 50000 * 1e18,
            liquidityETH: 3 ether,
            lockDuration: 365 days,
            listingPrice: 1e15,
            burnRemainingTokens: true
        });

        vm.deal(address(campaign), 3 ether);
        vm.prank(CREATOR);
        campaign.launchToken(dexConfig);
        assertEq(uint256(campaign.state()), uint256(CampaignState.TokenLaunched));

        // Verification should still be accessible in final state
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }

    // ============ Medical Campaign vs Traditional Campaign ============

    function test_medicalFlexibility_VsTraditionalCrowdfunding() public {
        // Demonstrate the flexibility of medical crowdfunding vs traditional models

        // Traditional model would require reaching goal before withdrawal
        // Medical model allows anytime withdrawal for urgent needs

        // Step 1: Small initial contribution (far from any theoretical goal)
        vm.deal(CONTRIBUTOR_1, 2 ether);
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        // Step 2: Medical emergency requires immediate access to funds
        uint256 creatorBalanceBefore = CREATOR.balance;
        vm.prank(CREATOR);
        campaign.withdrawFunds(); // This would fail in traditional crowdfunding

        assertGt(CREATOR.balance, creatorBalanceBefore);

        // Step 3: Campaign continues after withdrawal (unique to medical model)
        vm.deal(CONTRIBUTOR_2, 3 ether);
        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 2 ether}();

        // Step 4: Additional medical documentation provided for transparency
        vm.prank(CREATOR);
        campaign.uploadVerification("QmMedicalReceipts", "Hospital receipts and treatment records showing fund usage");

        // Total flow demonstrates medical crowdfunding flexibility
        assertEq(uint256(campaign.state()), uint256(CampaignState.Withdrawn));
        assertEq(campaign.totalRaised(), 3 ether);
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }
}
