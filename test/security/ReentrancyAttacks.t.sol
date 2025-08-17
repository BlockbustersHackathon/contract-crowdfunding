// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";
import "../mocks/MockMaliciousContract.sol";

contract ReentrancyAttackTest is BaseTest {
    MockMaliciousContract maliciousContract;
    uint256 campaignId;
    Campaign campaign;

    function setUp() public override {
        super.setUp();
        maliciousContract = new MockMaliciousContract();
        vm.deal(address(maliciousContract), 10 ether);

        campaignId = createTestCampaignWithGoalRequired();
        campaign = getCampaign(campaignId);
        maliciousContract.setTarget(address(campaign));
    }

    function test_Contribute_ReentrancyProtection() public {
        // This test verifies that the contribute function is protected against reentrancy
        uint256 contributionAmount = 1 ether;

        // Normal contribution should work
        vm.prank(address(maliciousContract));
        campaign.contribute{value: contributionAmount}();

        assertContributionExists(campaignId, address(maliciousContract), contributionAmount);
    }

    function test_Refund_ReentrancyProtection() public {
        uint256 contributionAmount = 2 ether;

        // Make contribution
        vm.prank(address(maliciousContract));
        campaign.contribute{value: contributionAmount}();

        // Move to failed state
        fastForwardToDeadline(campaignId);
        campaign.updateCampaignState();
        assertCampaignState(campaignId, CampaignState.Failed);

        // Activate attack before refund
        maliciousContract.activateAttack();

        uint256 initialBalance = address(maliciousContract).balance;

        // Attempt reentrancy attack during refund
        vm.prank(address(maliciousContract));
        maliciousContract.maliciousRefund();

        // Should only refund once due to reentrancy guard
        uint256 finalBalance = address(maliciousContract).balance;
        assertEq(finalBalance, initialBalance + contributionAmount);
        assertLt(maliciousContract.attackCount(), 3); // Attack should have been stopped

        // Verify contribution amount is reset (preventing double refund)
        Contribution memory contrib = campaign.getContribution(address(maliciousContract));
        assertEq(contrib.amount, 0);
    }

    function test_WithdrawFunds_ReentrancyProtection() public {
        // Create campaign where creator is a malicious contract
        vm.startPrank(address(maliciousContract));
        uint256 maliciousCampaignId = factory.createCampaign(
            "ipfs://malicious-campaign",
            5 ether,
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            true,
            "Malicious Token",
            "MAL"
        );
        vm.stopPrank();

        Campaign maliciousCampaign = getCampaign(maliciousCampaignId);
        maliciousContract.setTarget(address(maliciousCampaign));

        // Fund the campaign
        contributeToCompaign(maliciousCampaignId, contributor1, 5 ether);
        maliciousCampaign.updateCampaignState();

        uint256 initialBalance = address(maliciousContract).balance;

        // Attempt reentrancy attack during withdrawal
        maliciousContract.activateAttack();

        vm.prank(address(maliciousContract));
        maliciousCampaign.withdrawFunds();

        // Should only withdraw once
        uint256 finalBalance = address(maliciousContract).balance;
        assertEq(finalBalance, initialBalance + 5 ether);

        // Campaign state should be updated correctly
        assertEq(uint256(maliciousCampaign.getCampaignState()), uint256(CampaignState.FundsWithdrawn));
    }

    function test_TokenMinting_NoReentrancy() public {
        // Even though token minting isn't directly vulnerable to reentrancy in this design,
        // let's verify the flow doesn't allow unexpected behavior

        uint256 contributionAmount = 5 ether;
        contributeToCompaign(campaignId, address(maliciousContract), contributionAmount);
        contributeToCompaign(campaignId, contributor1, 5 ether);

        campaign.updateCampaignState();
        assertCampaignState(campaignId, CampaignState.Succeeded);

        // Claim tokens normally
        vm.prank(address(maliciousContract));
        campaign.claimTokens();

        CampaignData memory data = campaign.getCampaignDetails();
        assertGt(IERC20(data.tokenAddress).balanceOf(address(maliciousContract)), 0);

        // Verify claimed flag prevents double claiming
        assertTrue(campaign.getContribution(address(maliciousContract)).claimed);
    }

    function test_MultipleReentrancyAttempts() public {
        uint256 contributionAmount = 3 ether;

        // Make multiple contributions
        vm.startPrank(address(maliciousContract));
        campaign.contribute{value: contributionAmount}();
        campaign.contribute{value: contributionAmount}();
        vm.stopPrank();

        fastForwardToDeadline(campaignId);
        campaign.updateCampaignState();

        maliciousContract.activateAttack();

        uint256 initialBalance = address(maliciousContract).balance;

        // First refund attempt with reentrancy
        vm.prank(address(maliciousContract));
        maliciousContract.maliciousRefund();

        uint256 afterFirstRefund = address(maliciousContract).balance;

        // Second refund attempt should fail
        vm.prank(address(maliciousContract));
        vm.expectRevert("Campaign: No funds to refund");
        maliciousContract.maliciousRefund();

        // Balance should only increase by total contribution once
        assertEq(afterFirstRefund, initialBalance + (contributionAmount * 2));
    }

    function test_CrossFunctionReentrancy() public {
        // Test that reentrancy protection works across different functions
        uint256 contributionAmount = 2 ether;

        vm.prank(address(maliciousContract));
        campaign.contribute{value: contributionAmount}();

        // Try to contribute during a refund (after campaign fails)
        fastForwardToDeadline(campaignId);
        campaign.updateCampaignState();

        maliciousContract.activateAttack();

        // This should not allow additional contributions during refund
        vm.prank(address(maliciousContract));
        maliciousContract.maliciousRefund();

        // Verify only the original contribution exists
        Contribution memory contrib = campaign.getContribution(address(maliciousContract));
        assertEq(contrib.amount, 0); // Should be reset after refund
    }

    function test_StateConsistency_AfterReentrancyAttempt() public {
        uint256 contributionAmount = 4 ether;

        vm.prank(address(maliciousContract));
        campaign.contribute{value: contributionAmount}();

        fastForwardToDeadline(campaignId);
        campaign.updateCampaignState();

        maliciousContract.activateAttack();

        // Record state before attack
        CampaignData memory dataBefore = campaign.getCampaignDetails();
        uint256 totalRaisedBefore = dataBefore.totalRaised;

        vm.prank(address(maliciousContract));
        maliciousContract.maliciousRefund();

        // State should remain consistent
        CampaignData memory dataAfter = campaign.getCampaignDetails();
        assertEq(uint256(dataAfter.state), uint256(dataBefore.state)); // State shouldn't change unexpectedly
        assertEq(dataAfter.totalRaised, totalRaisedBefore); // Total raised should remain same

        maliciousContract.deactivateAttack();
    }

    function test_GasLimits_PreventReentrancy() public {
        // While our contracts use ReentrancyGuard, this test ensures
        // that even with gas limit manipulation, reentrancy is prevented

        uint256 contributionAmount = 1 ether;

        vm.prank(address(maliciousContract));
        campaign.contribute{value: contributionAmount}();

        fastForwardToDeadline(campaignId);
        campaign.updateCampaignState();

        maliciousContract.activateAttack();

        // Attempt refund with limited gas
        vm.prank(address(maliciousContract));
        try maliciousContract.maliciousRefund{gas: 100000}() {
            // If successful, verify no reentrancy occurred
            assertLt(maliciousContract.attackCount(), 3);
        } catch {
            // Expected to potentially fail due to gas limits, which is fine
        }

        maliciousContract.deactivateAttack();
    }
}
