// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ICampaignInterfaces.sol";

contract PricingCurve is IPricingCurve {
    uint256 public constant TOTAL_SUPPLY = 1e27; // 1 billion tokens (18 decimals)
    uint256 public constant TOKENS_FOR_SALE_PERCENTAGE = 75; // 75% of total supply for sale
    uint256 public constant PRECISION = 100; // For percentage calculations

    function calculateTokenAllocation(uint256 contributionAmount, uint256 fundingGoal)
        external
        pure
        returns (uint256)
    {
        require(contributionAmount > 0, "PricingCurve: Contribution must be greater than zero");
        require(fundingGoal > 0, "PricingCurve: Funding goal must be greater than zero");

        // Calculate tokens available for sale (75% of total supply)
        uint256 tokensForSale = (TOTAL_SUPPLY * TOKENS_FOR_SALE_PERCENTAGE) / PRECISION;

        // Token allocation = contributionAmount * tokensForSale / fundingGoal
        return (contributionAmount * tokensForSale) / fundingGoal;
    }

    function getTokenPrice(uint256 fundingGoal) external pure returns (uint256) {
        // Price per token = fundingGoal / (1 billion * 75%)
        uint256 tokensForSale = (TOTAL_SUPPLY * TOKENS_FOR_SALE_PERCENTAGE) / PRECISION;
        return (fundingGoal * 1e18) / tokensForSale; // Return price in wei per token
    }
}
