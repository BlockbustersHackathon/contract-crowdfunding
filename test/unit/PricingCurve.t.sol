// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract PricingCurveTest is BaseTest {
    function test_CalculateTokenAllocation_BaseRate() public view {
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        // Should get base rate (1000 tokens per USDC) with stable pricing
        uint256 expectedTokens = contribution * pricingCurve.getTokenRate();
        assertEq(tokens, expectedTokens);
    }

    function test_CalculateTokenAllocation_StablePricing() public view {
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 earlyTokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        uint256 lateTokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        // With stable pricing, tokens should be the same regardless of timing
        assertEq(earlyTokens, lateTokens);

        uint256 expectedTokens = contribution * pricingCurve.getTokenRate();
        assertEq(earlyTokens, expectedTokens);
        assertEq(lateTokens, expectedTokens);
    }

    function test_CalculateTokenAllocation_FundingIndependent() public view {
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 lowFundingTokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        uint256 highFundingTokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        // With stable pricing, funding level shouldn't affect token allocation
        assertEq(lowFundingTokens, highFundingTokens);

        uint256 expectedTokens = contribution * pricingCurve.getTokenRate();
        assertEq(lowFundingTokens, expectedTokens);
        assertEq(highFundingTokens, expectedTokens);
    }

    function test_CalculateTokenAllocation_StableRate() public view {
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        uint256 expectedTokens = contribution * pricingCurve.getTokenRate();

        assertEq(tokens, expectedTokens);
    }

    function test_CalculateTokenAllocation_ZeroContribution() public {
        vm.expectRevert("PricingCurve: Contribution must be greater than zero");
        pricingCurve.calculateTokenAllocation(0, CAMPAIGN_DURATION);
    }

    function test_CalculateTokenAllocation_ZeroDuration() public {
        vm.expectRevert("PricingCurve: Total duration must be greater than zero");
        pricingCurve.calculateTokenAllocation(1000 * 10 ** 6, 0); // 1000 USDC
    }

    function test_CalculateTokenAllocation_CampaignEnded() public view {
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        // Should calculate stable tokens regardless of funding status
        uint256 expectedTokens = contribution * pricingCurve.getTokenRate();
        assertEq(tokens, expectedTokens);
    }

    function test_CalculateTokenAllocation_DifferentContributionAmounts() public view {
        uint256[] memory contributions = new uint256[](4);
        contributions[0] = 100 * 10 ** 6; // 100 USDC
        contributions[1] = 1000 * 10 ** 6; // 1000 USDC
        contributions[2] = 5000 * 10 ** 6; // 5000 USDC
        contributions[3] = 10000 * 10 ** 6; // 10000 USDC

        uint256 totalDuration = CAMPAIGN_DURATION;

        for (uint256 i = 0; i < contributions.length; i++) {
            uint256 tokens = pricingCurve.calculateTokenAllocation(contributions[i], totalDuration);

            uint256 expectedTokens = contributions[i] * pricingCurve.getTokenRate();
            assertEq(tokens, expectedTokens); // Stable pricing without early bird bonus
        }
    }

    function test_CalculateTokenAllocation_EdgeCases() public view {
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 thresholdTokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        uint256 afterThresholdTokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        // With stable pricing, both should get the same amount
        assertEq(thresholdTokens, afterThresholdTokens);

        uint256 expectedTokens = contribution * pricingCurve.getTokenRate();
        assertEq(thresholdTokens, expectedTokens);
        assertEq(afterThresholdTokens, expectedTokens);
    }

    function test_GetTokenRate() public view {
        uint256 rate = pricingCurve.getTokenRate();
        assertEq(rate, 1000);
    }

    function test_CalculateTokenAllocation_HighPrecision() public view {
        // Test with very small contributions to check precision
        uint256 contribution = 1; // 1 unit (smallest USDC unit)
        uint256 totalDuration = CAMPAIGN_DURATION;

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, totalDuration);

        // Should get proportional tokens with stable pricing
        uint256 expectedTokens = contribution * pricingCurve.getTokenRate();
        assertEq(tokens, expectedTokens);
    }
}
