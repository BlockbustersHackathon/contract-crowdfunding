// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

// Import events for testing
import "../../src/interfaces/ICampaignStructs.sol";

contract MedicalVerificationTest is CampaignFixtures {
    Campaign public campaign;
    CampaignToken public token;

    // Events for testing (copied from ICampaignStructs.sol)
    event VerificationUploaded(uint256 indexed campaignId, string documentHash, string description);

    event VerificationStatusChanged(
        uint256 indexed campaignId, VerificationStatus oldStatus, VerificationStatus newStatus, address verifier
    );

    function setUp() public override {
        super.setUp();
        (campaign, token) = createBasicCampaign();
    }

    // ============ Document Upload Tests ============

    function test_uploadVerification_ValidData_Success() public {
        string memory documentHash = "QmTestHash123";
        string memory description = "Medical condition requiring urgent treatment";

        vm.prank(CREATOR);
        campaign.uploadVerification(documentHash, description);

        // Verify verification status is pending
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }

    function test_uploadVerification_EmptyDocumentHash_Reverts() public {
        vm.prank(CREATOR);
        vm.expectRevert("Document hash required");
        campaign.uploadVerification("", "Valid description");
    }

    function test_uploadVerification_EmptyDescription_Reverts() public {
        vm.prank(CREATOR);
        vm.expectRevert("Description required");
        campaign.uploadVerification("QmTestHash123", "");
    }

    function test_uploadVerification_NonCreator_Reverts() public {
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Only creator");
        campaign.uploadVerification("QmTestHash123", "Description");
    }

    function test_uploadVerification_EmitsEvent() public {
        string memory documentHash = "QmTestHash123";
        string memory description = "Medical condition description";

        vm.expectEmit(true, false, false, true);
        emit VerificationUploaded(campaign.campaignId(), documentHash, description);

        vm.prank(CREATOR);
        campaign.uploadVerification(documentHash, description);
    }

    // ============ Document Update Tests ============

    function test_updateVerification_AfterInitialUpload_Success() public {
        // First upload
        vm.prank(CREATOR);
        campaign.uploadVerification("QmOldHash", "Old description");

        // Update verification
        string memory newHash = "QmNewHash456";
        string memory newDescription = "Updated medical condition details";

        vm.prank(CREATOR);
        campaign.updateVerification(newHash, newDescription);

        // Verify status reset to pending
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }

    function test_updateVerification_WithoutInitialUpload_Reverts() public {
        vm.prank(CREATOR);
        vm.expectRevert("No verification uploaded");
        campaign.updateVerification("QmNewHash", "New description");
    }

    function test_updateVerification_NonCreator_Reverts() public {
        // First upload by creator
        vm.prank(CREATOR);
        campaign.uploadVerification("QmTestHash", "Description");

        // Try to update by non-creator
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Only creator");
        campaign.updateVerification("QmNewHash", "New description");
    }

    // ============ Verification Status Tests ============

    function test_getVerificationStatus_InitiallyNone() public {
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.None));
    }

    function test_getVerificationStatus_AfterUpload_Pending() public {
        vm.prank(CREATOR);
        campaign.uploadVerification("QmTestHash", "Description");

        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }

    // ============ Optional Verification Tests ============

    function test_campaignFunctionality_WithoutVerification_Works() public {
        // Campaign should work normally without verification
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        // Creator should be able to withdraw
        vm.prank(CREATOR);
        campaign.withdrawFunds();

        assertTrue(campaign.creatorWithdrawn());
    }

    function test_campaignFunctionality_WithVerification_StillWorks() public {
        // Upload verification
        vm.prank(CREATOR);
        campaign.uploadVerification("QmTestHash", "Medical condition");

        // Campaign should still work normally
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        vm.prank(CREATOR);
        campaign.withdrawFunds();

        assertTrue(campaign.creatorWithdrawn());
    }

    // ============ Edge Cases ============

    function test_multipleUpdates_KeepLatestData() public {
        // Upload initial verification
        vm.prank(CREATOR);
        campaign.uploadVerification("QmHash1", "Description 1");

        // Update multiple times
        vm.prank(CREATOR);
        campaign.updateVerification("QmHash2", "Description 2");

        vm.prank(CREATOR);
        campaign.updateVerification("QmHash3", "Description 3");

        // Status should still be pending after updates
        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }

    function test_longDescription_Accepted() public {
        string memory longDescription =
            "This is a very long medical description that details the specific condition, treatment requirements, urgency of the situation, expected outcomes, and other relevant medical information that might be necessary for verification purposes.";

        vm.prank(CREATOR);
        campaign.uploadVerification("QmTestHash", longDescription);

        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }

    function test_specialCharacters_InDescription_Accepted() public {
        string memory description =
            "Patient needs urgent surgery for condition X-123 (critical stage) $5000 required immediately! @hospital";

        vm.prank(CREATOR);
        campaign.uploadVerification("QmTestHash", description);

        assertEq(uint256(campaign.getVerificationStatus()), uint256(VerificationStatus.Pending));
    }

    // ============ Integration with Voting System ============

    function test_verifiedCampaign_CanStillBeVotedOn() public {
        // Upload and "verify" (simulate verification)
        vm.prank(CREATOR);
        campaign.uploadVerification("QmTestHash", "Medical condition");

        // Contribute to get tokens for voting
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 1 ether}();

        // Should still be able to initiate vote
        vm.prank(CONTRIBUTOR_1);
        campaign.initiateVote("Suspicious despite verification");

        // Verify vote was initiated
        (VotingStatus status,,) = campaign.getVoteStatus(0);
        assertEq(uint256(status), uint256(VotingStatus.Active));
    }
}
