// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============ ENUMS ============

enum CampaignState {
    Active,      // Accepting contributions
    Successful,  // Goal reached, can withdraw
    Failed,      // Deadline passed without reaching goal
    Cancelled,   // Campaign cancelled by creator/admin
    Withdrawn,   // Funds withdrawn by creator
    TokenLaunched, // Token launched on DEX
    Refunded     // All refunds processed (final state)
}

enum TokenLaunchStrategy {
    NoLaunch,           // Traditional crowdfunding
    ImmediateLaunch,    // Launch immediately after success
    DelayedLaunch,      // Launch after development phase
    ConditionalLaunch   // Launch based on milestones
}

// ============ STRUCTS ============

struct CampaignConfig {
    string name;
    string metadataURI;        // IPFS hash for off-chain data
    uint256 fundingGoal;        // Minimum amount to raise
    uint256 softCap;            // Optional soft cap
    uint256 hardCap;            // Maximum amount to raise
    uint256 startTime;
    uint256 endTime;
    address creator;
    address paymentToken;       // ETH or ERC20
    uint16 platformFeeBps;      // Platform fee in basis points
}

struct TokenConfig {
    string name;
    string symbol;
    uint256 totalSupply;
    uint256 creatorAllocation;  // Percentage for creator (basis points)
    uint256 treasuryAllocation; // Percentage for treasury
    uint256 backersAllocation;  // Percentage for backers
    bool transfersEnabled;      // Whether transfers are enabled during campaign
    TokenLaunchStrategy launchStrategy;
}

struct ContributionTier {
    uint256 minContribution;
    uint256 maxContribution;
    uint256 bonusMultiplier;   // e.g., 120 = 20% bonus
    uint256 availableSlots;    // Limited slots for this tier
    uint256 usedSlots;
}

struct Contribution {
    address contributor;
    uint256 amount;
    uint256 tokenAmount;
    uint256 timestamp;
    uint256 tier;
    bool refunded;
}

struct DEXLaunchConfig {
    address router;             // Uniswap router address
    uint256 liquidityTokens;    // Tokens for liquidity pool
    uint256 liquidityETH;       // ETH for liquidity pool
    uint256 lockDuration;       // LP token lock duration
    uint256 listingPrice;       // Initial token price
    bool burnRemainingTokens;   // Burn unsold tokens
}

// ============ EVENTS ============

interface ICampaignEvents {
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        address indexed campaignContract,
        address tokenContract
    );
    
    event ContributionMade(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount,
        uint256 tokensReceived,
        uint256 tier
    );
    
    event CampaignStateChanged(
        uint256 indexed campaignId,
        CampaignState oldState,
        CampaignState newState
    );
    
    event FundsWithdrawn(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount
    );
    
    event RefundClaimed(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    
    event TokenLaunched(
        uint256 indexed campaignId,
        address indexed pair,
        uint256 liquidityAdded,
        uint256 initialPrice
    );
    
    event MilestoneCompleted(
        uint256 indexed campaignId,
        uint256 milestoneId,
        string description
    );
    
    event BonusTokensMinted(
        uint256 indexed campaignId,
        address indexed recipient,
        uint256 amount,
        string reason
    );
}
