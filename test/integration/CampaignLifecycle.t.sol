// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

contract CampaignLifecycleTest is CampaignFixtures {
    
    // ============ Successful Campaign Flow ============
    
    function test_lifecycle_CreateToWithdraw_Success() public {
        // 1. Create campaign
        (Campaign campaign, CampaignToken token) = createBasicCampaign();
        assertEq(uint(campaign.state()), uint(CampaignState.Active));
        
        // 2. Multiple contributions
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 6 ether}();
        
        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: 5 ether}();
        
        // 3. Verify goal reached and state change
        assertTrue(campaign.checkGoalReached());
        assertEq(uint(campaign.state()), uint(CampaignState.Successful));
        
        // 4. Verify tokens were minted
        assertGt(token.balanceOf(CONTRIBUTOR_1), 0);
        assertGt(token.balanceOf(CONTRIBUTOR_2), 0);
        
        // 5. Creator withdraws funds
        uint256 creatorBalanceBefore = CREATOR.balance;
        vm.prank(CREATOR);
        campaign.withdrawFunds();
        
        // 6. Verify final state
        assertEq(uint(campaign.state()), uint(CampaignState.Withdrawn));
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
        assertEq(uint(campaign.state()), uint(CampaignState.TokenLaunched));
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
        
        // 3. Trigger state update
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Invalid state");
        campaign.contribute{value: 1 ether}();
        
        // 4. Manually transition to failed state (would happen automatically)
        vm.prank(ADMIN);
        campaign.cancelCampaign();
        
        // 5. Contributors claim refunds
        uint256 balance1Before = CONTRIBUTOR_1.balance;
        uint256 balance2Before = CONTRIBUTOR_2.balance;
        
        vm.prank(CONTRIBUTOR_1);
        campaign.claimRefund();
        
        vm.prank(CONTRIBUTOR_2);
        campaign.claimRefund();
        
        // 6. Verify refunds and token burning
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
        
        assertEq(uint(campaign.state()), uint(CampaignState.Cancelled));
        
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
        (Campaign campaign1, ) = createBasicCampaign();
        
        TokenConfig memory tokenConfig2 = createDefaultTokenConfig();
        tokenConfig2.symbol = "TEST2";
        
        vm.prank(CREATOR);
        (address addr2, ) = factory.createCampaign{value: 0.01 ether}(
            createDefaultCampaignConfig(),
            tokenConfig2,
            createDefaultTiers()
        );
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
        
        // 4. One succeeds, one fails
        vm.prank(CONTRIBUTOR_1);
        campaign1.contribute{value: 6 ether}(); // Reach goal
        
        vm.warp(block.timestamp + 31 days); // Past the default 30-day duration
        vm.prank(ADMIN);
        campaign2.cancelCampaign();
        
        // 5. Verify different final states
        assertEq(uint(campaign1.state()), uint(CampaignState.Successful));
        assertEq(uint(campaign2.state()), uint(CampaignState.Cancelled));
    }
    
    // ============ Edge Case Flows ============
    
    function test_lifecycle_ExactGoalReached_Success() public {
        (Campaign campaign, ) = createBasicCampaign();
        uint256 exactGoal = 10 ether; // Default funding goal
        
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: exactGoal}();
        
        assertEq(uint(campaign.state()), uint(CampaignState.Successful));
        assertTrue(campaign.checkGoalReached());
    }
    
    function test_lifecycle_LastMinuteContribution_Success() public {
        (Campaign campaign, ) = createBasicCampaign();
        
        // Contribute at the last block before deadline  
        vm.warp(block.timestamp + 30 days - 1); // Just before the 30-day deadline
        
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: 15 ether}();
        
        assertEq(uint(campaign.state()), uint(CampaignState.Successful));
    }
    
    function test_lifecycle_HardCapReached_StopsContributions() public {
        (Campaign campaign, ) = createBasicCampaign();
        uint256 hardCap = 50 ether; // Default hard cap
        
        // Contribute up to hard cap
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: hardCap}();
        
        // Additional contributions should fail
        vm.prank(CONTRIBUTOR_2);
        vm.expectRevert("Invalid state");
        campaign.contribute{value: 1 ether}();
    }
    
    // ============ State Transition Validation ============
    
    function test_lifecycle_InvalidStateTransition_Reverts() public {
        (Campaign campaign, ) = createBasicCampaign();
        
        // Try to withdraw from Active state
        vm.prank(CREATOR);
        vm.expectRevert("Invalid state");
        campaign.withdrawFunds();
        
        // Reach successful state
        contributeAndReachGoal(campaign);
        
        // Try to claim refund from Successful state
        vm.prank(CONTRIBUTOR_1);
        vm.expectRevert("Refunds not available");
        campaign.claimRefund();
    }
    
    function test_lifecycle_WithdrawThenTokenLaunch_Success() public {
        (Campaign campaign, ) = createBasicCampaign();
        contributeAndReachGoal(campaign);
        
        // 1. Withdraw funds first
        vm.prank(CREATOR);
        campaign.withdrawFunds();
        assertEq(uint(campaign.state()), uint(CampaignState.Withdrawn));
        
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
        
        assertEq(uint(campaign.state()), uint(CampaignState.TokenLaunched));
    }
}
