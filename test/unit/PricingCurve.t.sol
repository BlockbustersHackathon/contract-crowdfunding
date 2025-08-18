// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../utils/BaseTest.sol";

contract PricingCurveTest is BaseTest {
    function test_CalculateTokenAllocation_ProportionalToGoal() public view {
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC
        uint256 fundingGoal = FUNDING_GOAL; // 10,000 USDC

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, fundingGoal);

        // Should get 10% of 750M tokens (75B tokens with 18 decimals)
        uint256 tokensForSale = (1e27 * 75) / 100; // 750M tokens
        uint256 expectedTokens = (contribution * tokensForSale) / fundingGoal;
        assertEq(tokens, expectedTokens);
    }

    function test_CalculateTokenAllocation_DifferentGoals() public view {
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC
        uint256 lowGoal = 5000 * 10 ** 6; // 5,000 USDC
        uint256 highGoal = 20000 * 10 ** 6; // 20,000 USDC

        uint256 lowGoalTokens = pricingCurve.calculateTokenAllocation(contribution, lowGoal);
        uint256 highGoalTokens = pricingCurve.calculateTokenAllocation(contribution, highGoal);

        // Lower goal should give more tokens (lower price per token)
        assertGt(lowGoalTokens, highGoalTokens);

        // Verify exact calculations
        uint256 tokensForSale = (1e27 * 75) / 100; // 750M tokens
        assertEq(lowGoalTokens, (contribution * tokensForSale) / lowGoal);
        assertEq(highGoalTokens, (contribution * tokensForSale) / highGoal);
    }

    function test_CalculateTokenAllocation_FullFunding() public view {
        uint256 fundingGoal = 10000 * 10 ** 6; // 10,000 USDC

        // If campaign is fully funded, all 750M tokens should be allocated
        uint256 tokens = pricingCurve.calculateTokenAllocation(fundingGoal, fundingGoal);

        uint256 tokensForSale = (1e27 * 75) / 100; // 750M tokens
        assertEq(tokens, tokensForSale);
    }

    function test_GetTokenPrice() public view {
        uint256 fundingGoal = 10000 * 10 ** 6; // 10,000 USDC

        uint256 price = pricingCurve.getTokenPrice(fundingGoal);

        // Price should be fundingGoal / (750M tokens)
        uint256 tokensForSale = (1e27 * 75) / 100; // 750M tokens
        uint256 expectedPrice = (fundingGoal * 1e18) / tokensForSale;
        assertEq(price, expectedPrice);
    }

    function test_CalculateTokenAllocation_ZeroContribution() public {
        vm.expectRevert("PricingCurve: Contribution must be greater than zero");
        pricingCurve.calculateTokenAllocation(0, CAMPAIGN_DURATION);
    }

    function test_CalculateTokenAllocation_ZeroFundingGoal() public {
        vm.expectRevert("PricingCurve: Funding goal must be greater than zero");
        pricingCurve.calculateTokenAllocation(1000 * 10 ** 6, 0); // 1000 USDC
    }

    function test_CalculateTokenAllocation_PrecisionCheck() public view {
        uint256 contribution = 1; // 1 unit USDC
        uint256 fundingGoal = 1000000 * 10 ** 6; // 1M USDC

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, fundingGoal);

        // Should handle small contributions correctly
        uint256 tokensForSale = (1e27 * 75) / 100;
        uint256 expectedTokens = (contribution * tokensForSale) / fundingGoal;
        assertEq(tokens, expectedTokens);
    }

    function test_CalculateTokenAllocation_LinearScaling() public view {
        uint256 fundingGoal = 10000 * 10 ** 6; // 10,000 USDC
        uint256 baseContribution = 100 * 10 ** 6; // 100 USDC

        uint256 singleContribution = pricingCurve.calculateTokenAllocation(baseContribution, fundingGoal);
        uint256 doubleContribution = pricingCurve.calculateTokenAllocation(baseContribution * 2, fundingGoal);
        uint256 tripleContribution = pricingCurve.calculateTokenAllocation(baseContribution * 3, fundingGoal);

        // Token allocation should scale linearly with contribution
        assertEq(doubleContribution, singleContribution * 2);
        assertEq(tripleContribution, singleContribution * 3);
    }

    function test_CalculateTokenAllocation_EdgeCases() public view {
        uint256 tokensForSale = (1e27 * 75) / 100; // 750M tokens

        // Very large funding goal
        uint256 largeGoal = 1000000 * 10 ** 6; // 1M USDC
        uint256 smallContribution = 10 * 10 ** 6; // 10 USDC
        uint256 tokens = pricingCurve.calculateTokenAllocation(smallContribution, largeGoal);
        uint256 expectedTokens = (smallContribution * tokensForSale) / largeGoal;
        assertEq(tokens, expectedTokens);

        // Very small funding goal
        uint256 smallGoal = 100 * 10 ** 6; // 100 USDC
        uint256 contribution = 10 * 10 ** 6; // 10 USDC
        tokens = pricingCurve.calculateTokenAllocation(contribution, smallGoal);
        expectedTokens = (contribution * tokensForSale) / smallGoal;
        assertEq(tokens, expectedTokens);
    }

    function test_TokenSupplyConstants() public view {
        // Verify the constants are set correctly
        assertEq(pricingCurve.TOTAL_SUPPLY(), 1e27); // 1 billion tokens
        assertEq(pricingCurve.TOKENS_FOR_SALE_PERCENTAGE(), 75); // 75%
        assertEq(pricingCurve.PRECISION(), 100); // Precision for percentage calculations
    }

    function test_MaxAllocation_EdgeCase() public view {
        uint256 fundingGoal = 1; // Minimum possible goal (edge case)
        uint256 contribution = 1; // Minimum possible contribution

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, fundingGoal);

        // Should allocate all tokens for sale
        uint256 tokensForSale = (1e27 * 75) / 100;
        assertEq(tokens, tokensForSale);
    }

    function test_TokenPrice_DifferentGoals() public view {
        uint256 smallGoal = 1000 * 10 ** 6; // 1,000 USDC
        uint256 largeGoal = 100000 * 10 ** 6; // 100,000 USDC

        uint256 smallGoalPrice = pricingCurve.getTokenPrice(smallGoal);
        uint256 largeGoalPrice = pricingCurve.getTokenPrice(largeGoal);

        // Larger goal should mean higher token price
        assertGt(largeGoalPrice, smallGoalPrice);

        // Verify exact calculations
        uint256 tokensForSale = (1e27 * 75) / 100;
        assertEq(smallGoalPrice, (smallGoal * 1e18) / tokensForSale);
        assertEq(largeGoalPrice, (largeGoal * 1e18) / tokensForSale);
    }

    function test_RoundingBehavior() public view {
        uint256 fundingGoal = 3 * 10 ** 6; // 3 USDC (creates potential rounding issues)
        uint256 contribution = 1 * 10 ** 6; // 1 USDC

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, fundingGoal);

        uint256 tokensForSale = (1e27 * 75) / 100;
        uint256 expectedTokens = (contribution * tokensForSale) / fundingGoal;
        assertEq(tokens, expectedTokens);

        // Should be exactly 1/3 of all tokens for sale
        assertEq(tokens * 3, tokensForSale);
    }

    function test_OverflowProtection() public view {
        // Test with maximum realistic values to ensure no overflow
        uint256 maxGoal = type(uint128).max / 1e12; // Large but safe goal
        uint256 contribution = 1000 * 10 ** 6; // 1000 USDC

        uint256 tokens = pricingCurve.calculateTokenAllocation(contribution, maxGoal);

        // Should be a very small amount but not zero
        assertGt(tokens, 0);
        assertLt(tokens, 1e18); // Less than 1 token
    }
}
