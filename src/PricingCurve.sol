// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ICampaignStructs.sol";
import "./interfaces/ICampaignInterfaces.sol";

/**
 * @title PricingCurve
 * @dev Handles token pricing calculations, bonuses, and tier management for campaigns
 */
contract PricingCurve is IPricingCurve {
    // Constants for calculations
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant EARLY_BIRD_DURATION = 7 days; // First week gets early bird bonus
    uint256 public constant EARLY_BIRD_BONUS_BPS = 1500; // 15% bonus
    uint256 public constant MAX_BONUS_BPS = 5000; // Max 50% bonus
    
    // Base token price calculation: tokens per ETH at start
    uint256 public constant BASE_TOKENS_PER_ETH = 1000;

    /**
     * @dev Calculate tokens for contribution with tier bonuses
     * @param contributionAmount Amount being contributed
     * @param totalRaised Current total raised amount
     * @param fundingGoal Campaign funding goal
     * @param tiers Array of contribution tiers
     * @return tokenAmount Number of tokens to mint
     * @return tier Tier index used for calculation
     */
    function calculateTokensForContribution(
        uint256 contributionAmount,
        uint256 totalRaised,
        uint256 fundingGoal,
        ContributionTier[] calldata tiers
    ) external pure override returns (uint256 tokenAmount, uint256 tier) {
        require(contributionAmount > 0, "Contribution must be positive");
        
        // Find appropriate tier
        tier = _findTier(contributionAmount, tiers);
        
        // Calculate base token amount
        uint256 basePrice = getCurrentPrice(totalRaised, fundingGoal);
        uint256 baseTokens = (contributionAmount * BASE_TOKENS_PER_ETH) / basePrice;
        
        // Apply tier bonus
        uint256 bonusMultiplier = getBonusMultiplier(tier, tiers);
        tokenAmount = (baseTokens * bonusMultiplier) / BASIS_POINTS;
        
        return (tokenAmount, tier);
    }

    /**
     * @dev Get current token price based on bonding curve
     * @param totalRaised Current total raised amount
     * @param fundingGoal Campaign funding goal
     * @return Current price in wei per token
     */
    function getCurrentPrice(uint256 totalRaised, uint256 fundingGoal) public pure override returns (uint256) {
        require(fundingGoal > 0, "Funding goal must be positive");
        
        // Simple bonding curve: price increases as more funds are raised
        // Price = basePrice * (1 + (totalRaised / fundingGoal) * 0.5)
        // This means price increases by 50% when goal is reached
        
        uint256 basePrice = 1e18 / BASE_TOKENS_PER_ETH; // Price per token in wei
        uint256 progressMultiplier = (totalRaised * 5000) / fundingGoal; // 50% max increase
        uint256 priceMultiplier = BASIS_POINTS + progressMultiplier;
        
        return (basePrice * priceMultiplier) / BASIS_POINTS;
    }

    /**
     * @dev Get bonus multiplier for a specific tier
     * @param tierIndex Index of the tier
     * @param tiers Array of contribution tiers
     * @return Bonus multiplier in basis points
     */
    function getBonusMultiplier(uint256 tierIndex, ContributionTier[] calldata tiers) public pure override returns (uint256) {
        if (tierIndex >= tiers.length) {
            return BASIS_POINTS; // No bonus for invalid tier
        }
        
        uint256 bonus = tiers[tierIndex].bonusMultiplier;
        require(bonus <= BASIS_POINTS + MAX_BONUS_BPS, "Bonus too high");
        
        return bonus;
    }

    /**
     * @dev Get discounted price for early contributors
     * @param basePrice Base token price
     * @param timestamp Current timestamp
     * @param startTime Campaign start time
     * @return Discounted price
     */
    function getDiscountedPrice(
        uint256 basePrice,
        uint256 timestamp,
        uint256 startTime
    ) external pure override returns (uint256) {
        if (timestamp <= startTime + EARLY_BIRD_DURATION) {
            // Apply early bird discount
            uint256 discountMultiplier = BASIS_POINTS - EARLY_BIRD_BONUS_BPS;
            return (basePrice * discountMultiplier) / BASIS_POINTS;
        }
        
        return basePrice;
    }

    /**
     * @dev Calculate tokens with early bird bonus
     * @param contributionAmount Amount being contributed
     * @param totalRaised Current total raised
     * @param fundingGoal Campaign funding goal
     * @param timestamp Current timestamp
     * @param startTime Campaign start time
     * @param tiers Array of contribution tiers
     * @return tokenAmount Number of tokens including early bird bonus
     * @return tier Tier used for calculation
     */
    function calculateTokensWithEarlyBird(
        uint256 contributionAmount,
        uint256 totalRaised,
        uint256 fundingGoal,
        uint256 timestamp,
        uint256 startTime,
        ContributionTier[] calldata tiers
    ) external view returns (uint256 tokenAmount, uint256 tier) {
        // Calculate base tokens with tier bonus
        (uint256 baseTokens, uint256 tierUsed) = this.calculateTokensForContribution(
            contributionAmount,
            totalRaised,
            fundingGoal,
            tiers
        );
        
        // Apply early bird bonus if applicable
        if (timestamp <= startTime + EARLY_BIRD_DURATION) {
            uint256 earlyBirdMultiplier = BASIS_POINTS + EARLY_BIRD_BONUS_BPS;
            tokenAmount = (baseTokens * earlyBirdMultiplier) / BASIS_POINTS;
        } else {
            tokenAmount = baseTokens;
        }
        
        return (tokenAmount, tierUsed);
    }

    /**
     * @dev Project future token price based on funding progress
     * @param currentRaised Current amount raised
     * @param targetRaised Target amount to project to
     * @param fundingGoal Campaign funding goal
     * @return Projected future price
     */
    function projectFuturePrice(
        uint256 currentRaised,
        uint256 targetRaised,
        uint256 fundingGoal
    ) external pure returns (uint256) {
        require(targetRaised >= currentRaised, "Target must be >= current");
        
        return getCurrentPrice(targetRaised, fundingGoal);
    }

    /**
     * @dev Calculate average price for a large contribution across multiple price points
     * @param contributionAmount Large contribution amount
     * @param currentRaised Current total raised
     * @param fundingGoal Campaign funding goal
     * @return Average price for the contribution
     */
    function calculateAveragePrice(
        uint256 contributionAmount,
        uint256 currentRaised,
        uint256 fundingGoal
    ) external pure returns (uint256) {
        // For simplicity, use price at midpoint of contribution
        uint256 midpointRaised = currentRaised + (contributionAmount / 2);
        return getCurrentPrice(midpointRaised, fundingGoal);
    }

    /**
     * @dev Internal function to find the appropriate tier for a contribution
     * @param amount Contribution amount
     * @param tiers Array of available tiers
     * @return Index of the tier to use
     */
    function _findTier(uint256 amount, ContributionTier[] calldata tiers) internal pure returns (uint256) {
        // Start from the highest tier and work down
        for (uint256 i = tiers.length; i > 0; i--) {
            uint256 tierIndex = i - 1;
            ContributionTier memory tier = tiers[tierIndex];
            
            // Check if contribution fits this tier and slots are available
            if (amount >= tier.minContribution &&
                (tier.maxContribution == 0 || amount <= tier.maxContribution) &&
                tier.usedSlots < tier.availableSlots) {
                return tierIndex;
            }
        }
        
        // If no tier matches, return tiers.length to indicate no valid tier
        return tiers.length;
    }

    /**
     * @dev Check if a contribution amount is valid for any tier
     * @param amount Contribution amount to check
     * @param tiers Array of available tiers
     * @return isValid Whether the amount is valid
     * @return tierIndex Index of the tier it would use
     */
    function validateContribution(
        uint256 amount,
        ContributionTier[] calldata tiers
    ) external pure returns (bool isValid, uint256 tierIndex) {
        tierIndex = _findTier(amount, tiers);
        
        if (tierIndex < tiers.length) {
            ContributionTier memory tier = tiers[tierIndex];
            isValid = tier.usedSlots < tier.availableSlots;
        } else {
            isValid = false;
        }
        
        return (isValid, tierIndex);
    }

    /**
     * @dev Get tier information for UI display
     * @param tiers Array of tiers
     * @return minAmounts Minimum contribution amounts
     * @return maxAmounts Maximum contribution amounts
     * @return bonuses Bonus multipliers
     * @return availableSlots Available slots per tier
     * @return usedSlots Used slots per tier
     */
    function getTierInfo(ContributionTier[] calldata tiers) external pure returns (
        uint256[] memory minAmounts,
        uint256[] memory maxAmounts,
        uint256[] memory bonuses,
        uint256[] memory availableSlots,
        uint256[] memory usedSlots
    ) {
        uint256 length = tiers.length;
        
        minAmounts = new uint256[](length);
        maxAmounts = new uint256[](length);
        bonuses = new uint256[](length);
        availableSlots = new uint256[](length);
        usedSlots = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            minAmounts[i] = tiers[i].minContribution;
            maxAmounts[i] = tiers[i].maxContribution;
            bonuses[i] = tiers[i].bonusMultiplier;
            availableSlots[i] = tiers[i].availableSlots;
            usedSlots[i] = tiers[i].usedSlots;
        }
        
        return (minAmounts, maxAmounts, bonuses, availableSlots, usedSlots);
    }
}
