// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract PricingCurveTest is BaseTest {
    function test_CalculateTokenAllocation_BaseRate() public {
        uint256 contribution = 1 ether;
        uint256 totalRaised = 0;
        uint256 fundingGoal = 10 ether;
        uint256 timeRemaining = CAMPAIGN_DURATION;
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 tokens =
            pricingCurve.calculateTokenAllocation(contribution, totalRaised, fundingGoal, timeRemaining, totalDuration);

        // Should get base rate (1000 tokens per ETH) + early bird bonus (20%) when timeRemaining = totalDuration
        uint256 expectedBaseTokens = contribution * pricingCurve.getTokenRate();
        uint256 earlyBirdBonus = (expectedBaseTokens * pricingCurve.getEarlyBirdBonus()) / 100;
        assertEq(tokens, expectedBaseTokens + earlyBirdBonus);
    }

    function test_CalculateTokenAllocation_EarlyBirdBonus() public {
        uint256 contribution = 1 ether;
        uint256 totalRaised = 0;
        uint256 fundingGoal = 10 ether;
        uint256 totalDuration = CAMPAIGN_DURATION;

        // Early in campaign (within first 25%)
        uint256 earlyTimeRemaining = totalDuration - (totalDuration * 20 / 100); // 20% elapsed

        uint256 earlyTokens = pricingCurve.calculateTokenAllocation(
            contribution, totalRaised, fundingGoal, earlyTimeRemaining, totalDuration
        );

        // Later in campaign (after 25%)
        uint256 lateTimeRemaining = totalDuration - (totalDuration * 30 / 100); // 30% elapsed

        uint256 lateTokens = pricingCurve.calculateTokenAllocation(
            contribution, totalRaised, fundingGoal, lateTimeRemaining, totalDuration
        );

        // Early contributor should get more tokens (20% bonus)
        assertGt(earlyTokens, lateTokens);

        uint256 baseTokens = contribution * pricingCurve.getTokenRate();
        uint256 expectedEarlyTokens = baseTokens + (baseTokens * pricingCurve.getEarlyBirdBonus() / 100);
        assertEq(earlyTokens, expectedEarlyTokens);
    }

    function test_CalculateTokenAllocation_FundingProgressBonus() public {
        uint256 contribution = 1 ether;
        uint256 fundingGoal = 10 ether;
        uint256 timeRemaining = CAMPAIGN_DURATION / 2;
        uint256 totalDuration = CAMPAIGN_DURATION;

        // Campaign less than 50% funded
        uint256 lowFunding = fundingGoal * 30 / 100; // 30% funded

        uint256 lowFundingTokens =
            pricingCurve.calculateTokenAllocation(contribution, lowFunding, fundingGoal, timeRemaining, totalDuration);

        // Campaign more than 50% funded
        uint256 highFunding = fundingGoal * 70 / 100; // 70% funded

        uint256 highFundingTokens =
            pricingCurve.calculateTokenAllocation(contribution, highFunding, fundingGoal, timeRemaining, totalDuration);

        // Low funding should get bonus (10% extra)
        assertGt(lowFundingTokens, highFundingTokens);
    }

    function test_CalculateTokenAllocation_CombinedBonuses() public {
        uint256 contribution = 1 ether;
        uint256 totalRaised = 1 ether; // 10% funded
        uint256 fundingGoal = 10 ether;
        uint256 totalDuration = CAMPAIGN_DURATION;
        uint256 earlyTimeRemaining = totalDuration - (totalDuration * 15 / 100); // 15% elapsed

        uint256 tokens = pricingCurve.calculateTokenAllocation(
            contribution, totalRaised, fundingGoal, earlyTimeRemaining, totalDuration
        );

        uint256 baseTokens = contribution * pricingCurve.getTokenRate();
        uint256 earlyBirdBonus = baseTokens * pricingCurve.getEarlyBirdBonus() / 100;
        uint256 fundingBonus = (baseTokens + earlyBirdBonus) * 10 / 100; // 10% funding bonus
        uint256 expectedTokens = baseTokens + earlyBirdBonus + fundingBonus;

        assertEq(tokens, expectedTokens);
    }

    function test_CalculateTokenAllocation_ZeroContribution() public {
        vm.expectRevert("PricingCurve: Contribution must be greater than zero");
        pricingCurve.calculateTokenAllocation(0, 0, 10 ether, CAMPAIGN_DURATION, CAMPAIGN_DURATION);
    }

    function test_CalculateTokenAllocation_ZeroDuration() public {
        vm.expectRevert("PricingCurve: Total duration must be greater than zero");
        pricingCurve.calculateTokenAllocation(1 ether, 0, 10 ether, 0, 0);
    }

    function test_CalculateTokenAllocation_CampaignEnded() public {
        uint256 contribution = 1 ether;
        uint256 totalRaised = 5 ether;
        uint256 fundingGoal = 10 ether;
        uint256 totalDuration = CAMPAIGN_DURATION;
        uint256 timeRemaining = 0; // Campaign ended

        uint256 tokens =
            pricingCurve.calculateTokenAllocation(contribution, totalRaised, fundingGoal, timeRemaining, totalDuration);

        // Should still calculate tokens (no early bird bonus and no funding bonus since totalRaised=0)
        uint256 baseTokens = contribution * pricingCurve.getTokenRate();
        assertEq(tokens, baseTokens);
    }

    function test_CalculateTokenAllocation_DifferentContributionAmounts() public {
        uint256[] memory contributions = new uint256[](4);
        contributions[0] = 0.1 ether;
        contributions[1] = 1 ether;
        contributions[2] = 5 ether;
        contributions[3] = 10 ether;

        uint256 totalRaised = 0;
        uint256 fundingGoal = 100 ether;
        uint256 timeRemaining = CAMPAIGN_DURATION;
        uint256 totalDuration = CAMPAIGN_DURATION;

        for (uint256 i = 0; i < contributions.length; i++) {
            uint256 tokens = pricingCurve.calculateTokenAllocation(
                contributions[i], totalRaised, fundingGoal, timeRemaining, totalDuration
            );

            uint256 expectedTokens = contributions[i] * pricingCurve.getTokenRate();
            uint256 earlyBirdBonus = (expectedTokens * pricingCurve.getEarlyBirdBonus()) / 100;
            assertEq(tokens, expectedTokens + earlyBirdBonus); // Gets early bird bonus when timeRemaining = totalDuration
        }
    }

    function test_CalculateTokenAllocation_EdgeCases() public {
        uint256 contribution = 1 ether;
        uint256 fundingGoal = 10 ether;
        uint256 totalDuration = CAMPAIGN_DURATION;

        // Exactly at early bird threshold (25%)
        uint256 thresholdTimeRemaining = totalDuration - (totalDuration * 25 / 100);
        uint256 thresholdTokens =
            pricingCurve.calculateTokenAllocation(contribution, 0, fundingGoal, thresholdTimeRemaining, totalDuration);

        // Just after early bird threshold
        uint256 afterThresholdTimeRemaining = totalDuration - (totalDuration * 26 / 100);
        uint256 afterThresholdTokens = pricingCurve.calculateTokenAllocation(
            contribution, 0, fundingGoal, afterThresholdTimeRemaining, totalDuration
        );

        // At threshold should get bonus, after threshold should not
        assertGt(thresholdTokens, afterThresholdTokens);
    }

    function test_GetTokenRate() public {
        uint256 rate = pricingCurve.getTokenRate();
        assertEq(rate, 1000);
    }

    function test_GetEarlyBirdBonus() public {
        uint256 bonus = pricingCurve.getEarlyBirdBonus();
        assertEq(bonus, 20);
    }

    function test_CalculateTokenAllocation_HighPrecision() public {
        // Test with very small contributions to check precision
        uint256 contribution = 1 wei;
        uint256 totalRaised = 0;
        uint256 fundingGoal = 1 ether;
        uint256 timeRemaining = CAMPAIGN_DURATION;
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 tokens =
            pricingCurve.calculateTokenAllocation(contribution, totalRaised, fundingGoal, timeRemaining, totalDuration);

        // Should get proportional tokens + early bird bonus (when timeRemaining = totalDuration)
        uint256 expectedTokens = contribution * pricingCurve.getTokenRate();
        uint256 earlyBirdBonus = (expectedTokens * pricingCurve.getEarlyBirdBonus()) / 100;
        assertEq(tokens, expectedTokens + earlyBirdBonus);
    }
}
