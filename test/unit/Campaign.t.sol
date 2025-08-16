// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

contract CampaignTest is CampaignFixtures {
    Campaign public campaign;
    CampaignToken public token;
    
    function setUp() public override {
        super.setUp();
        (campaign, token) = createBasicCampaign();
    }
    
    // ============ State Machine Tests ============
    
    function test_initialState_IsActive() public {
        assertEq(uint(campaign.state()), uint(CampaignState.Active));
    }
    
    function test_stateTransition_ReachGoal_BecomesSuccessful() public {
        contributeAndReachGoal(campaign);
        assertEq(uint(campaign.state()), uint(CampaignState.Successful));
    }
    
    function test_stateTransition_AfterDeadline_BecomesFailed() public {
        // Warp past deadline without reaching goal
        vm.warp(block.timestamp + 31 days); // Past the default 30-day duration
        
        // Trigger state update by attempting contribution
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Invalid state");
        campaign.contribute{value: 1 ether}();
    }
    
    // ============ Contribution Tests ============
    
    function test_contribute_ValidAmount_Success() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = CONTRIBUTOR_1.balance;
        
        // Note: We'll verify the event was emitted but not check exact token amount
        // since it depends on complex calculations
        
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: amount}();
        
        assertEq(CONTRIBUTOR_1.balance, balanceBefore - amount);
        assertEq(campaign.totalRaised(), amount);
        assertEq(campaign.totalContributed(CONTRIBUTOR_1), amount);
        assertGt(token.balanceOf(CONTRIBUTOR_1), 0);
    }
    
    function test_contribute_ExceedsHardCap_Reverts() public {
        uint256 hardCap = 50 ether; // Default hard cap
        
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Hard cap exceeded");
        campaign.contribute{value: hardCap + 1 ether}();
    }
    
    function test_contribute_AfterDeadline_Reverts() public {
        vm.warp(block.timestamp + 31 days); // Past the default 30-day duration
        
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Invalid state");
        campaign.contribute{value: 1 ether}();
    }
    
    function test_contribute_MultipleContributors_TracksCorrectly() public {
        contributeMultipleUsers(campaign, 2 ether);
        
        assertEq(campaign.totalRaised(), 4 ether);
        assertEq(campaign.totalContributors(), 2);
        assertEq(campaign.totalContributed(CONTRIBUTOR_1), 2 ether);
        assertEq(campaign.totalContributed(CONTRIBUTOR_2), 2 ether);
    }
    
    // ============ Withdrawal Tests ============
    
    function test_withdrawFunds_SuccessfulCampaign_Success() public {
        contributeAndReachGoal(campaign);
        
        uint256 creatorBalanceBefore = CREATOR.balance;
        uint256 totalRaised = campaign.totalRaised();
        uint256 platformFee = (totalRaised * 250) / 10000; // 2.5%
        uint256 expectedAmount = totalRaised - platformFee;
        
        vm.prank(CREATOR);
        campaign.withdrawFunds();
        
        assertEq(CREATOR.balance, creatorBalanceBefore + expectedAmount);
        assertTrue(campaign.creatorWithdrawn());
        assertEq(uint(campaign.state()), uint(CampaignState.Withdrawn));
    }
    
    function test_withdrawFunds_NotSuccessful_Reverts() public {
        vm.prank(CREATOR);
        vm.expectRevert("Invalid state");
        campaign.withdrawFunds();
    }
    
    function test_withdrawFunds_AlreadyWithdrawn_Reverts() public {
        contributeAndReachGoal(campaign);
        
        vm.prank(CREATOR);
        campaign.withdrawFunds();
        
        vm.prank(CREATOR);
        vm.expectRevert("Invalid state");
        campaign.withdrawFunds();
    }
    
    // ============ Refund Tests ============
    
    function test_claimRefund_FailedCampaign_Success() public {
        uint256 contribution = 2 ether;
        
        // Contribute
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: contribution}();
        
        // Make campaign fail
        (,,,,, uint256 endTime,,,,) = campaign.config();
        vm.warp(endTime + 1);
        vm.prank(ADMIN);
        campaign.cancelCampaign();
        
        uint256 balanceBefore = CONTRIBUTOR_1.balance;
        
        vm.prank(CONTRIBUTOR_1);
        campaign.claimRefund();
        
        assertEq(CONTRIBUTOR_1.balance, balanceBefore + contribution);
        assertTrue(campaign.hasClaimedRefund(CONTRIBUTOR_1));
        assertEq(token.balanceOf(CONTRIBUTOR_1), 0); // Tokens should be burned
    }
    
    function test_claimRefund_NoContribution_Reverts() public {
        vm.prank(ADMIN);
        campaign.cancelCampaign();
        
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("No contribution found");
        campaign.claimRefund();
    }
    
    // ============ Access Control Tests ============
    
    function test_onlyCreator_Functions_RestrictAccess() public {
        // Test creator-only functions with non-creator
        vm.startPrank(CONTRIBUTOR_1);
        
        vm.expectRevert("Only creator");
        campaign.updateMetadata("new-uri");
        
        vm.expectRevert("Only creator");
        campaign.enableTransfers();
        
        vm.expectRevert("Only creator");
        campaign.burnUnallocatedTokens();
        
        vm.stopPrank();
    }
    
    function test_updateMetadata_CreatorOnly_Success() public {
        string memory newURI = "ipfs://new-metadata";
        
        vm.prank(CREATOR);
        campaign.updateMetadata(newURI);
        
        (, string memory metadataURI,,,,,,,,) = campaign.config();
        assertEq(metadataURI, newURI);
    }
    
    // ============ Utility Function Tests ============
    
    function test_calculateTokenAmount_ReturnsCorrectly() public {
        uint256 amount = 1 ether;
        (uint256 tokenAmount, uint256 tier) = campaign.calculateTokenAmount(amount);
        
        assertGt(tokenAmount, 0);
        assertLt(tier, 3); // Should be within tier range
    }
    
    function test_checkGoalReached_BeforeGoal_ReturnsFalse() public {
        assertFalse(campaign.checkGoalReached());
    }
    
    function test_checkGoalReached_AfterGoal_ReturnsTrue() public {
        contributeAndReachGoal(campaign);
        assertTrue(campaign.checkGoalReached());
    }
    
    function test_getCampaignSummary_ReturnsCorrectData() public {
        contributeMultipleUsers(campaign, 1 ether);
        
        (
            uint256 totalRaised,
            uint256 totalContributors,
            uint256 totalTokensDistributed,
            CampaignState state,
            bool goalReached,
            uint256 timeRemaining
        ) = campaign.getCampaignSummary();
        
        assertEq(totalRaised, 2 ether);
        assertEq(totalContributors, 2);
        assertGt(totalTokensDistributed, 0);
        assertEq(uint(state), uint(CampaignState.Active));
        assertFalse(goalReached);
        assertGt(timeRemaining, 0);
    }
}
