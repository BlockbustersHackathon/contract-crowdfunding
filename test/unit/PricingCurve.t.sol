// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../fixtures/CampaignFixtures.sol";

contract PricingCurveTest is CampaignFixtures {
    
    // ============ Price Calculation Tests ============
    
    function test_getCurrentPrice_ZeroRaised_ReturnsBasePrice() public {
        uint256 price = pricingCurve.getCurrentPrice(0, 10 ether);
        uint256 expectedBasePrice = 1e18 / 1000; // 1 ETH / 1000 tokens
        
        assertEq(price, expectedBasePrice);
    }
    
    function test_getCurrentPrice_ProgressIncreases_PriceIncreases() public {
        uint256 fundingGoal = 10 ether;
        
        uint256 price1 = pricingCurve.getCurrentPrice(0, fundingGoal);
        uint256 price2 = pricingCurve.getCurrentPrice(5 ether, fundingGoal);
        uint256 price3 = pricingCurve.getCurrentPrice(10 ether, fundingGoal);
        
        assertLt(price1, price2);
        assertLt(price2, price3);
    }
    
    function test_calculateTokensForContribution_BasicCalculation() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        
        (uint256 tokenAmount, uint256 tier) = pricingCurve.calculateTokensForContribution(
            1 ether,
            0,
            10 ether,
            tiers
        );
        
        assertGt(tokenAmount, 0);
        assertEq(tier, 1); // Should be in tier 1 (1 ETH contribution)
    }
    
    function test_calculateTokensForContribution_TierBonusApplied() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        
        // Small contribution (tier 0 - 20% bonus)
        (uint256 tokens1, ) = pricingCurve.calculateTokensForContribution(
            0.5 ether,
            0,
            10 ether,
            tiers
        );
        
        // Large contribution (tier 2 - 10% bonus)
        (uint256 tokens2, ) = pricingCurve.calculateTokensForContribution(
            5 ether,
            0,
            10 ether,
            tiers
        );
        
        // Tier 0 should give more tokens per ETH due to higher bonus
        assertGt(tokens1 * 10, tokens2); // Accounting for 10x contribution difference
    }
    
    // ============ Tier Management Tests ============
    
    function test_getBonusMultiplier_ValidTier_ReturnsCorrectly() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        
        uint256 bonus0 = pricingCurve.getBonusMultiplier(0, tiers);
        uint256 bonus1 = pricingCurve.getBonusMultiplier(1, tiers);
        uint256 bonus2 = pricingCurve.getBonusMultiplier(2, tiers);
        
        assertEq(bonus0, 12000); // 20% bonus
        assertEq(bonus1, 11500); // 15% bonus
        assertEq(bonus2, 11000); // 10% bonus
    }
    
    function test_getBonusMultiplier_InvalidTier_ReturnsBase() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        
        uint256 bonus = pricingCurve.getBonusMultiplier(999, tiers);
        assertEq(bonus, 10000); // Base multiplier (no bonus)
    }
    
    function test_validateContribution_ValidAmount_ReturnsTrue() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        
        (bool isValid, uint256 tierIndex) = pricingCurve.validateContribution(1 ether, tiers);
        
        assertTrue(isValid);
        assertEq(tierIndex, 1);
    }
    
    function test_validateContribution_TooSmall_ReturnsFalse() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        
        (bool isValid, ) = pricingCurve.validateContribution(0.05 ether, tiers);
        
        assertFalse(isValid);
    }
    
    // ============ Early Bird Discount Tests ============
    
    function test_getDiscountedPrice_EarlyBird_AppliesDiscount() public {
        uint256 basePrice = 1000;
        uint256 startTime = block.timestamp;
        
        // Within early bird period
        uint256 discountedPrice = pricingCurve.getDiscountedPrice(
            basePrice,
            startTime + 1 days,
            startTime
        );
        
        // Should be less than base price
        assertLt(discountedPrice, basePrice);
        
        // Should be exactly 15% discount
        uint256 expectedPrice = (basePrice * 8500) / 10000;
        assertEq(discountedPrice, expectedPrice);
    }
    
    function test_getDiscountedPrice_AfterEarlyBird_NoDiscount() public {
        uint256 basePrice = 1000;
        uint256 startTime = block.timestamp;
        
        // After early bird period
        uint256 price = pricingCurve.getDiscountedPrice(
            basePrice,
            startTime + 8 days,
            startTime
        );
        
        assertEq(price, basePrice);
    }
    
    function test_calculateTokensWithEarlyBird_AppliesBothBonuses() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        uint256 startTime = block.timestamp;
        
        // Calculate with early bird bonus
        (uint256 tokensEarly, ) = pricingCurve.calculateTokensWithEarlyBird(
            1 ether,
            0,
            10 ether,
            startTime + 1 days,
            startTime,
            tiers
        );
        
        // Calculate without early bird bonus
        (uint256 tokensLater, ) = pricingCurve.calculateTokensWithEarlyBird(
            1 ether,
            0,
            10 ether,
            startTime + 8 days,
            startTime,
            tiers
        );
        
        // Early bird should get more tokens
        assertGt(tokensEarly, tokensLater);
    }
    
    // ============ Utility Function Tests ============
    
    function test_projectFuturePrice_IncreasingTargets() public {
        uint256 currentRaised = 5 ether;
        uint256 fundingGoal = 10 ether;
        
        uint256 currentPrice = pricingCurve.getCurrentPrice(currentRaised, fundingGoal);
        uint256 futurePrice = pricingCurve.projectFuturePrice(currentRaised, 8 ether, fundingGoal);
        
        assertGt(futurePrice, currentPrice);
    }
    
    function test_calculateAveragePrice_ReturnsReasonableValue() public {
        uint256 averagePrice = pricingCurve.calculateAveragePrice(
            2 ether,
            5 ether,
            10 ether
        );
        
        assertGt(averagePrice, 0);
    }
    
    function test_getTierInfo_ReturnsAllData() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        
        (
            uint256[] memory minAmounts,
            uint256[] memory maxAmounts,
            uint256[] memory bonuses,
            uint256[] memory availableSlots,
            uint256[] memory usedSlots
        ) = pricingCurve.getTierInfo(tiers);
        
        assertEq(minAmounts.length, 3);
        assertEq(maxAmounts.length, 3);
        assertEq(bonuses.length, 3);
        assertEq(availableSlots.length, 3);
        assertEq(usedSlots.length, 3);
        
        assertEq(minAmounts[0], 0.1 ether);
        assertEq(minAmounts[1], 1 ether);
        assertEq(minAmounts[2], 5 ether);
        
        assertEq(bonuses[0], 12000);
        assertEq(bonuses[1], 11500);
        assertEq(bonuses[2], 11000);
    }
    
    // ============ Edge Case Tests ============
    
    function test_calculateTokens_ZeroContribution_Reverts() public {
        ContributionTier[] memory tiers = createDefaultTiers();
        
        vm.expectRevert("Contribution must be positive");
        pricingCurve.calculateTokensForContribution(0, 0, 10 ether, tiers);
    }
    
    function test_getCurrentPrice_ZeroGoal_Reverts() public {
        vm.expectRevert("Funding goal must be positive");
        pricingCurve.getCurrentPrice(5 ether, 0);
    }
    
    function test_projectFuturePrice_InvalidTarget_Reverts() public {
        vm.expectRevert("Target must be >= current");
        pricingCurve.projectFuturePrice(10 ether, 5 ether, 20 ether);
    }
}
