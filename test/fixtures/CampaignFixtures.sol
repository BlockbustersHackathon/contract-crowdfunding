// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BaseSetup.sol";

contract CampaignFixtures is BaseSetup {
    
    function createDefaultCampaignConfig() internal view returns (CampaignConfig memory) {
        return CampaignConfig({
            name: "Test Campaign",
            metadataURI: "ipfs://test-metadata",
            fundingGoal: 10 ether,
            softCap: 5 ether,
            hardCap: 50 ether,
            startTime: block.timestamp,
            endTime: block.timestamp + 30 days,
            creator: CREATOR,
            paymentToken: address(0), // ETH
            platformFeeBps: 250 // 2.5%
        });
    }
    
    function createDefaultTokenConfig() internal pure returns (TokenConfig memory) {
        return TokenConfig({
            name: "Test Token",
            symbol: "TEST",
            totalSupply: 1_000_000 * 1e18,
            creatorAllocation: 2000, // 20%
            treasuryAllocation: 1000, // 10%
            backersAllocation: 7000, // 70%
            transfersEnabled: false,
            launchStrategy: TokenLaunchStrategy.DelayedLaunch
        });
    }
    
    function createDefaultTiers() internal pure returns (ContributionTier[] memory) {
        ContributionTier[] memory tiers = new ContributionTier[](3);
        
        tiers[0] = ContributionTier({
            minContribution: 0.1 ether,
            maxContribution: 1 ether,
            bonusMultiplier: 12000, // 20% bonus
            availableSlots: 100,
            usedSlots: 0
        });
        
        tiers[1] = ContributionTier({
            minContribution: 1 ether,
            maxContribution: 5 ether,
            bonusMultiplier: 11500, // 15% bonus
            availableSlots: 50,
            usedSlots: 0
        });
        
        tiers[2] = ContributionTier({
            minContribution: 5 ether,
            maxContribution: 0, // No max
            bonusMultiplier: 11000, // 10% bonus
            availableSlots: 20,
            usedSlots: 0
        });
        
        return tiers;
    }
    
    function createBasicCampaign() internal returns (Campaign campaign, CampaignToken token) {
        CampaignConfig memory config = createDefaultCampaignConfig();
        TokenConfig memory tokenConfig = createDefaultTokenConfig();
        ContributionTier[] memory tiers = createDefaultTiers();
        
        vm.prank(CREATOR);
        (address campaignAddr, address tokenAddr) = factory.createCampaign{value: 0.01 ether}(
            config,
            tokenConfig,
            tiers
        );
        
        campaign = Campaign(payable(campaignAddr));
        token = CampaignToken(tokenAddr);
        
        // Register campaign with mock factory for treasury validation
        mockFactory.registerCampaign(0, campaignAddr); // Assuming campaignId 0 for basic test
        
        vm.label(address(campaign), "Campaign");
        vm.label(address(token), "CampaignToken");
    }
    
    function createHighValueCampaign() internal returns (Campaign campaign, CampaignToken token) {
        CampaignConfig memory config = createDefaultCampaignConfig();
        config.fundingGoal = 100 ether;
        config.hardCap = 500 ether;
        
        TokenConfig memory tokenConfig = createDefaultTokenConfig();
        tokenConfig.symbol = "HIGHVAL";
        
        ContributionTier[] memory tiers = createDefaultTiers();
        
        vm.prank(CREATOR);
        (address campaignAddr, address tokenAddr) = factory.createCampaign{value: 0.01 ether}(
            config,
            tokenConfig,
            tiers
        );
        
        campaign = Campaign(payable(campaignAddr));
        token = CampaignToken(tokenAddr);
        
        // Register campaign with mock factory for treasury validation 
        mockFactory.registerCampaign(1, campaignAddr); // Assuming campaignId 1 for high value test
    }
    
    function contributeAndReachGoal(Campaign campaign) internal {
        // Contribute enough to reach funding goal
        // We'll use a fixed amount that we know exceeds the default goal
        uint256 goalAmount = 15 ether; // Default goal is 10 ether
        
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: goalAmount}();
    }
    
    function contributeMultipleUsers(Campaign campaign, uint256 amountEach) internal {
        vm.prank(CONTRIBUTOR_1);
        campaign.contribute{value: amountEach}();
        
        vm.prank(CONTRIBUTOR_2);
        campaign.contribute{value: amountEach}();
    }
}
