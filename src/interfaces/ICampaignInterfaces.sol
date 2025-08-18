// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ICampaignStructs.sol";

interface ICrowdfundingFactory {
    function createCampaign(
        string memory metadataURI,
        uint256 fundingGoal,
        uint256 duration,
        uint256 creatorReservePercentage,
        uint256 liquidityPercentage,
        bool allowEarlyWithdrawal,
        string memory tokenName,
        string memory tokenSymbol
    ) external returns (uint256 campaignId);

    function getCampaign(uint256 campaignId) external view returns (CampaignData memory);
    function getCampaignsByCreator(address creator) external view returns (uint256[] memory);
    function getCampaignCount() external view returns (uint256);
}

interface ICampaign {
    function contribute(uint256 amount) external;
    function claimTokens() external;
    function withdrawFunds() external;
    function refund() external;
    function createLiquidityPool() external;
    function extendDeadline(uint256 newDeadline) external;
    function updateCampaignState() external;

    function getCampaignDetails() external view returns (CampaignData memory);
    function getContribution(address contributor) external view returns (Contribution memory);
    function calculateTokenAllocation(uint256 contributionAmount) external view returns (uint256);
    function getCampaignState() external view returns (CampaignState);
}

interface ICampaignToken {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function getCampaignAddress() external view returns (address);
}

interface IDEXIntegrator {
    function addLiquidity(address tokenA, uint256 tokenAmount, address tokenB, uint256 usdcAmount)
        external
        returns (uint256 amountToken, uint256 amountUSDC, uint256 liquidity);

    function getOptimalLiquidityAmounts(address tokenA, address tokenB, uint256 tokenDesired, uint256 usdcDesired)
        external
        view
        returns (uint256 tokenAmount, uint256 usdcAmount);
}

interface IPricingCurve {
    function calculateTokenAllocation(uint256 contributionAmount, uint256 totalDuration)
        external
        pure
        returns (uint256);
}

interface ITreasury {
    function depositFunds(uint256 campaignId) external payable;
    function withdrawFunds(uint256 campaignId, address recipient, uint256 amount) external;
    function refundContributor(uint256 campaignId, address contributor, uint256 amount) external;
}
