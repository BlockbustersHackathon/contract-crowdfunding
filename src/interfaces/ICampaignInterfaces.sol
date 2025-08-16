// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ICampaignStructs.sol";

interface ICrowdfundingFactory {
    function createCampaign(
        CampaignConfig calldata campaignConfig,
        TokenConfig calldata tokenConfig,
        ContributionTier[] calldata tiers
    ) external payable returns (address campaignAddress, address tokenAddress);
    
    function pauseFactory() external;
    function updatePlatformFee(uint16 newFeeBps) external;
    function withdrawPlatformFees(address token) external;
    function verifyCreator(address creator) external;
    function approvePaymentToken(address token) external;
    
    function getCampaignsByCreator(address creator) external view returns (uint256[] memory);
    function getCampaignDetails(uint256 campaignId) external view returns (address campaignAddress, address tokenAddress);
    function isAdmin(address account) external view returns (bool);
}

interface ICampaign {
    function contribute() external payable;
    function contributeWithToken(uint256 amount) external;
    function batchContribute(uint256[] calldata amounts) external payable;
    function claimRefund() external;
    
    function withdrawFunds() external;
    function launchToken(DEXLaunchConfig calldata dexConfig) external;
    function updateMetadata(string calldata newMetadataURI) external;
    function completeMilestone(uint256 milestoneId, string calldata description) external;
    function emergencyWithdraw() external;
    
    function enableTransfers() external;
    function burnUnallocatedTokens() external;
    function cancelCampaign() external;
    function extendDeadline(uint256 newEndTime) external;
    
    function calculateTokenAmount(uint256 contributionAmount) external view returns (uint256 tokenAmount, uint256 tier);
    function checkGoalReached() external view returns (bool);
    function getContributionHistory(address contributor) external view returns (Contribution[] memory);
    function getCampaignState() external view returns (CampaignState);
}

interface ICampaignToken {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function pause() external;
    function unpause() external;
    function snapshot() external returns (uint256);
    function enableTransfers() external;
    function disableTransfers() external;
    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPricingCurve {
    function calculateTokensForContribution(
        uint256 contributionAmount,
        uint256 totalRaised,
        uint256 fundingGoal,
        ContributionTier[] calldata tiers
    ) external pure returns (uint256 tokenAmount, uint256 tier);
    
    function getCurrentPrice(uint256 totalRaised, uint256 fundingGoal) external pure returns (uint256);
    function getBonusMultiplier(uint256 tier, ContributionTier[] calldata tiers) external pure returns (uint256);
    function getDiscountedPrice(uint256 basePrice, uint256 timestamp, uint256 startTime) external pure returns (uint256);
}

interface ITreasury {
    function deposit(uint256 campaignId) external payable;
    function depositToken(uint256 campaignId, address token, uint256 amount) external;
    function withdraw(uint256 campaignId, address to, uint256 amount) external;
    function withdrawToken(uint256 campaignId, address token, address to, uint256 amount) external;
    function refund(uint256 campaignId, address to, uint256 amount) external;
    function refundToken(uint256 campaignId, address token, address to, uint256 amount) external;
    function emergencyWithdraw(uint256 campaignId, address to) external;
    
    function getBalance(uint256 campaignId) external view returns (uint256);
    function getTokenBalance(uint256 campaignId, address token) external view returns (uint256);
    function collectPlatformFee(uint256 campaignId, uint256 feeAmount) external;
    function collectPlatformTokenFee(uint256 campaignId, address token, uint256 feeAmount) external;
}

interface IDEXIntegrator {
    function createUniswapPair(address token) external returns (address pair);
    function addInitialLiquidity(
        address token,
        uint256 tokenAmount,
        uint256 ethAmount,
        address to
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
    
    function removeLiquidity(
        address token,
        uint256 liquidity,
        address to
    ) external returns (uint256 amountToken, uint256 amountETH);
    
    function estimateRequiredETH(address token, uint256 tokenAmount, uint256 desiredPrice) external view returns (uint256);
    function getPoolInfo(address pair) external view returns (uint256 reserve0, uint256 reserve1, uint256 totalSupply);
}
