// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract CrowdfundingFactoryTest is BaseTest {
    function test_CreateCampaign_Success() public {
        vm.prank(creator);
        (uint256 campaignId,) = factory.createCampaign(
            "Test Campaign",
            "ipfs://test-metadata",
            FUNDING_GOAL,
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            "Test Token",
            "TEST"
        );

        assertEq(campaignId, 0);
        assertEq(factory.getCampaignCount(), 1);

        CampaignData memory campaign = factory.getCampaign(campaignId);
        assertEq(campaign.creator, creator);
        assertEq(campaign.fundingGoal, FUNDING_GOAL);
        assertEq(campaign.creatorReservePercentage, CREATOR_RESERVE);
    }

    function test_CreateCampaign_InvalidParameters() public {
        vm.startPrank(creator);

        // Test invalid funding goal - too low
        vm.expectRevert("CrowdfundingFactory: Invalid funding goal");
        factory.createCampaign(
            "Test Campaign",
            "ipfs://test",
            50e6, // Below minimum (100 USDC)
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            "Test Token",
            "TEST"
        );

        // Test invalid funding goal - too high
        vm.expectRevert("CrowdfundingFactory: Invalid funding goal");
        factory.createCampaign(
            "Test Campaign",
            "ipfs://test",
            15000000e6, // Above maximum (10M USDC)
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            "Test Token",
            "TEST"
        );

        // Test invalid duration - too long
        vm.expectRevert("CrowdfundingFactory: Invalid duration");
        factory.createCampaign(
            "Test Campaign",
            "ipfs://test",
            FUNDING_GOAL,
            181 days, // Above maximum (180 days)
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            "Test Token",
            "TEST"
        );

        // Test creator reserve too high
        vm.expectRevert("CrowdfundingFactory: Creator reserve too high");
        factory.createCampaign(
            "Test Campaign",
            "ipfs://test",
            FUNDING_GOAL,
            CAMPAIGN_DURATION,
            60, // Above 50%
            LIQUIDITY_PERCENTAGE,
            "Test Token",
            "TEST"
        );

        vm.stopPrank();
    }

    function test_CreateCampaign_EmptyParameters() public {
        vm.startPrank(creator);

        // Test empty metadata URI
        vm.expectRevert("CrowdfundingFactory: Empty metadata URI");
        factory.createCampaign(
            "Test Campaign", "", FUNDING_GOAL, CAMPAIGN_DURATION, CREATOR_RESERVE, LIQUIDITY_PERCENTAGE, "Test Token", "TEST"
        );

        // Test empty token name
        vm.expectRevert("CrowdfundingFactory: Empty token name");
        factory.createCampaign(
            "Test Campaign", "ipfs://test", FUNDING_GOAL, CAMPAIGN_DURATION, CREATOR_RESERVE, LIQUIDITY_PERCENTAGE, "", "TEST"
        );

        // Test empty token symbol
        vm.expectRevert("CrowdfundingFactory: Empty token symbol");
        factory.createCampaign(
            "Test Campaign", "ipfs://test", FUNDING_GOAL, CAMPAIGN_DURATION, CREATOR_RESERVE, LIQUIDITY_PERCENTAGE, "Test Token", ""
        );

        vm.stopPrank();
    }

    function test_GetCampaignsByCreator() public {
        vm.startPrank(creator);

        // Create multiple campaigns
        (uint256 campaignId1,) = factory.createCampaign(
            "Campaign 1",
            "ipfs://test1",
            FUNDING_GOAL,
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            "Test Token 1",
            "TEST1"
        );

        (uint256 campaignId2,) = factory.createCampaign(
            "Campaign 2",
            "ipfs://test2",
            FUNDING_GOAL * 2,
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            "Test Token 2",
            "TEST2"
        );

        vm.stopPrank();

        uint256[] memory creatorCampaigns = factory.getCampaignsByCreator(creator);
        assertEq(creatorCampaigns.length, 2);
        assertEq(creatorCampaigns[0], campaignId1);
        assertEq(creatorCampaigns[1], campaignId2);

        // Test empty array for non-creator
        uint256[] memory emptyCampaigns = factory.getCampaignsByCreator(contributor1);
        assertEq(emptyCampaigns.length, 0);
    }

    function test_CampaignCounter_Increments() public {
        assertEq(factory.getCampaignCount(), 0);

        vm.startPrank(creator);

        factory.createCampaign(
            "Campaign 1",
            "ipfs://test1",
            FUNDING_GOAL,
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            "Test Token 1",
            "TEST1"
        );
        assertEq(factory.getCampaignCount(), 1);

        factory.createCampaign(
            "Campaign 2",
            "ipfs://test2",
            FUNDING_GOAL,
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            "Test Token 2",
            "TEST2"
        );
        assertEq(factory.getCampaignCount(), 2);

        vm.stopPrank();
    }

    function test_GetCampaign_InvalidId() public {
        vm.expectRevert("CrowdfundingFactory: Campaign does not exist");
        factory.getCampaign(999);
    }

    // Note: setPlatformFee function was removed since platform fees are no longer used

    // Note: setFeeRecipient function was also removed since fee recipient is no longer used
}
