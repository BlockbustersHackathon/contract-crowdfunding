// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

enum CampaignState {
    Active,
    Succeeded,
    Failed,
    FundsWithdrawn,
    TokenLaunched,
    Cancelled,
    RefundsAvailable
}

enum WithdrawalCondition {
    Flexible,
    GoalRequired
}

struct CampaignData {
    address creator;
    string metadataURI;
    uint256 fundingGoal;
    uint256 deadline;
    uint256 totalRaised;
    uint256 creatorReservePercentage;
    uint256 liquidityPercentage;
    address tokenAddress;
    CampaignState state;
    WithdrawalCondition withdrawalCondition;
    bool allowEarlyWithdrawal;
    uint256 createdAt;
}

struct Contribution {
    address contributor;
    uint256 amount;
    uint256 timestamp;
    uint256 tokenAllocation;
    bool claimed;
}

interface ICampaignEvents {
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        address indexed tokenAddress,
        uint256 fundingGoal,
        uint256 deadline
    );
    
    event ContributionMade(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount,
        uint256 tokenAllocation
    );
    
    event TokensClaimed(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    
    event CampaignSucceeded(
        uint256 indexed campaignId,
        uint256 totalRaised
    );
    
    event CampaignFailed(
        uint256 indexed campaignId,
        uint256 totalRaised
    );
    
    event FundsWithdrawn(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount
    );
    
    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    
    event LiquidityPoolCreated(
        uint256 indexed campaignId,
        address indexed poolAddress,
        uint256 tokenAmount,
        uint256 ethAmount
    );
    
    event CampaignStateChanged(
        uint256 indexed campaignId,
        CampaignState previousState,
        CampaignState newState
    );
}