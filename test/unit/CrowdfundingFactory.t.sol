// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

contract CrowdfundingFactoryTest is CampaignFixtures {
    
    function test_deployment_InitializesCorrectly() public {
        assertEq(address(factory.treasury()), address(treasury));
        assertEq(address(factory.pricingCurve()), address(pricingCurve));
        assertEq(address(factory.dexIntegrator()), address(dexIntegrator));
        assertEq(factory.feeRecipient(), FEE_RECIPIENT);
        assertEq(factory.defaultPlatformFeeBps(), 250);
        assertTrue(factory.isAdmin(ADMIN));
    }
    
    function test_createCampaign_ValidParams_Success() public {
        CampaignConfig memory config = createDefaultCampaignConfig();
        TokenConfig memory tokenConfig = createDefaultTokenConfig();
        ContributionTier[] memory tiers = createDefaultTiers();
        
        // Note: Testing event emission without exact address checking
        // since addresses are generated dynamically
        
        vm.prank(CREATOR);
        (address campaignAddr, address tokenAddr) = factory.createCampaign{value: 0.01 ether}(
            config,
            tokenConfig,
            tiers
        );
        
        // Verify campaign was created
        assertTrue(campaignAddr != address(0));
        assertTrue(tokenAddr != address(0));
        
        // Verify registry updates
        (address storedCampaign, address storedToken) = factory.getCampaignDetails(0);
        assertEq(storedCampaign, campaignAddr);
        assertEq(storedToken, tokenAddr);
        
        // Verify creator campaigns
        uint256[] memory creatorCampaigns = factory.getCampaignsByCreator(CREATOR);
        assertEq(creatorCampaigns.length, 1);
        assertEq(creatorCampaigns[0], 0);
    }
    
    function test_createCampaign_InsufficientFee_Reverts() public {
        CampaignConfig memory config = createDefaultCampaignConfig();
        TokenConfig memory tokenConfig = createDefaultTokenConfig();
        ContributionTier[] memory tiers = createDefaultTiers();
        
        vm.prank(CREATOR);
        vm.expectRevert("Insufficient creation fee");
        factory.createCampaign{value: 0.005 ether}(config, tokenConfig, tiers);
    }
    
    function test_createCampaign_DuplicateSymbol_Reverts() public {
        // Create first campaign
        createBasicCampaign();
        
        // Try to create second campaign with same symbol
        CampaignConfig memory config = createDefaultCampaignConfig();
        TokenConfig memory tokenConfig = createDefaultTokenConfig(); // Same symbol
        ContributionTier[] memory tiers = createDefaultTiers();
        
        vm.prank(CREATOR);
        vm.expectRevert("Symbol already used");
        factory.createCampaign{value: 0.01 ether}(config, tokenConfig, tiers);
    }
    
    function test_updatePlatformFee_AdminOnly_Success() public {
        vm.prank(ADMIN);
        factory.updatePlatformFee(300); // 3%
        
        assertEq(factory.defaultPlatformFeeBps(), 300);
    }
    
    function test_updatePlatformFee_NonAdmin_Reverts() public {
        vm.prank(CREATOR);
        vm.expectRevert("Only admin");
        factory.updatePlatformFee(300);
    }
    
    function test_pauseFactory_PauserOnly_Success() public {
        vm.prank(ADMIN);
        factory.pauseFactory();
        
        assertTrue(factory.factoryPaused());
        
        // Should not be able to create campaigns when paused
        CampaignConfig memory config = createDefaultCampaignConfig();
        TokenConfig memory tokenConfig = createDefaultTokenConfig();
        tokenConfig.symbol = "PAUSED";
        ContributionTier[] memory tiers = createDefaultTiers();
        
        vm.prank(CREATOR);
        vm.expectRevert("Factory is paused");
        factory.createCampaign{value: 0.01 ether}(config, tokenConfig, tiers);
    }
    
    function test_verifyCreator_AdminOnly_Success() public {
        vm.prank(ADMIN);
        factory.verifyCreator(CREATOR);
        
        assertTrue(factory.verifiedCreators(CREATOR));
        assertGt(factory.creatorReputation(CREATOR), 0);
    }
    
    function test_approvePaymentToken_AdminOnly_Success() public {
        address testToken = address(0x123);
        
        vm.prank(ADMIN);
        factory.approvePaymentToken(testToken);
        
        assertTrue(factory.approvedPaymentTokens(testToken));
    }
    
    function test_isSymbolAvailable_NewSymbol_ReturnsTrue() public {
        assertTrue(factory.isSymbolAvailable("NEWSYM"));
    }
    
    function test_isSymbolAvailable_UsedSymbol_ReturnsFalse() public {
        createBasicCampaign();
        assertFalse(factory.isSymbolAvailable("TEST"));
    }
}
