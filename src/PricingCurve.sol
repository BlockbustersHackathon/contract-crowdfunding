// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/ICampaignInterfaces.sol";

contract PricingCurve is IPricingCurve {
    uint256 public constant BASE_TOKEN_RATE = 1000; // Base tokens per USDC
    uint256 public constant PRECISION = 10000; // For percentage calculations

    function calculateTokenAllocation(uint256 contributionAmount, uint256 totalDuration)
        external
        pure
        returns (uint256)
    {
        require(contributionAmount > 0, "PricingCurve: Contribution must be greater than zero");
        require(totalDuration > 0, "PricingCurve: Total duration must be greater than zero");

        return contributionAmount * BASE_TOKEN_RATE;
    }

    function getTokenRate() external pure returns (uint256) {
        return BASE_TOKEN_RATE;
    }
}
