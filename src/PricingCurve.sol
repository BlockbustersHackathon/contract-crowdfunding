// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ICampaignInterfaces.sol";

contract PricingCurve is IPricingCurve {
    uint256 public constant EARLY_BIRD_BONUS_PERCENTAGE = 20; // 20% bonus for early contributors
    uint256 public constant EARLY_BIRD_THRESHOLD = 25; // First 25% of campaign duration
    uint256 public constant BASE_TOKEN_RATE = 1000; // Base tokens per ETH
    uint256 public constant PRECISION = 10000; // For percentage calculations

    function calculateTokenAllocation(
        uint256 contributionAmount,
        uint256 totalRaised,
        uint256 fundingGoal,
        uint256 timeRemaining,
        uint256 totalDuration
    ) external pure returns (uint256) {
        require(contributionAmount > 0, "PricingCurve: Contribution must be greater than zero");
        require(totalDuration > 0, "PricingCurve: Total duration must be greater than zero");

        uint256 baseTokens = contributionAmount * BASE_TOKEN_RATE;

        uint256 timeElapsed = totalDuration - timeRemaining;
        uint256 timeProgress = (timeElapsed * PRECISION) / totalDuration;

        bool isEarlyBird = timeProgress <= (EARLY_BIRD_THRESHOLD * PRECISION / 100);

        if (isEarlyBird) {
            uint256 bonusTokens = (baseTokens * EARLY_BIRD_BONUS_PERCENTAGE) / 100;
            baseTokens += bonusTokens;
        }

        uint256 fundingProgress = fundingGoal > 0 ? (totalRaised * PRECISION) / fundingGoal : 0;

        if (fundingProgress > 0 && fundingProgress < (50 * PRECISION / 100)) {
            uint256 fundingBonus = (baseTokens * 10) / 100; // 10% bonus if less than 50% funded
            baseTokens += fundingBonus;
        }

        return baseTokens;
    }

    function getTokenRate() external pure returns (uint256) {
        return BASE_TOKEN_RATE;
    }

    function getEarlyBirdBonus() external pure returns (uint256) {
        return EARLY_BIRD_BONUS_PERCENTAGE;
    }
}
