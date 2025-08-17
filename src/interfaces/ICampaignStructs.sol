// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ============ ENUMS ============

enum CampaignState {
    Active, // Accepting contributions, creator can withdraw anytime
    Withdrawn, // Funds withdrawn by creator, campaign can continue
    Cancelled, // Cancelled by creator/admin/community vote
    TokenLaunched, // Token launched on DEX
    Refunded // All contributors refunded (final state)

}

enum TokenLaunchStrategy {
    NoLaunch, // Traditional crowdfunding
    ImmediateLaunch, // Launch immediately after success
    DelayedLaunch, // Launch after development phase
    ConditionalLaunch // Launch based on milestones

}

enum VerificationStatus {
    None, // No verification uploaded
    Pending, // Verification uploaded, under review
    Verified, // Verification approved
    Rejected // Verification rejected

}

enum VoteType {
    Invalid, // Vote that campaign is invalid/fraudulent
    Valid // Vote that campaign is valid

}

enum VotingStatus {
    NotStarted, // No voting initiated
    Active, // Voting in progress
    Passed, // Vote passed (campaign marked invalid)
    Failed, // Vote failed (campaign remains valid)
    Executed // Vote result executed

}

// ============ STRUCTS ============

struct CampaignConfig {
    string name;
    string metadataURI; // IPFS hash for off-chain data
    uint256 fundingGoal; // Minimum amount to raise
    uint256 softCap; // Optional soft cap
    uint256 hardCap; // Maximum amount to raise
    uint256 startTime;
    uint256 endTime;
    address creator;
    address paymentToken; // ETH or ERC20
    uint16 platformFeeBps; // Platform fee in basis points
}

struct TokenConfig {
    string name;
    string symbol;
    uint256 totalSupply;
    uint256 creatorAllocation; // Percentage for creator (basis points)
    uint256 treasuryAllocation; // Percentage for treasury
    uint256 backersAllocation; // Percentage for backers
    bool transfersEnabled; // Whether transfers are enabled during campaign
    TokenLaunchStrategy launchStrategy;
}

struct ContributionTier {
    uint256 minContribution;
    uint256 maxContribution;
    uint256 bonusMultiplier; // e.g., 120 = 20% bonus
    uint256 availableSlots; // Limited slots for this tier
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
    address router; // Uniswap router address
    uint256 liquidityTokens; // Tokens for liquidity pool
    uint256 liquidityETH; // ETH for liquidity pool
    uint256 lockDuration; // LP token lock duration
    uint256 listingPrice; // Initial token price
    bool burnRemainingTokens; // Burn unsold tokens
}

struct MedicalVerification {
    string documentHash; // IPFS hash of verification document
    string description; // Description of medical condition
    uint256 uploadTimestamp; // When verification was uploaded
    VerificationStatus status; // Current verification status
    address verifier; // Address that verified (if any)
    string rejectionReason; // Reason for rejection (if applicable)
}

struct CommunityVote {
    uint256 voteId; // Unique vote identifier
    address initiator; // Address that started the vote
    uint256 startTime; // Vote start timestamp
    uint256 endTime; // Vote end timestamp
    uint256 forVotes; // Total voting power for "invalid"
    uint256 againstVotes; // Total voting power for "valid"
    uint256 totalVotingPower; // Total voting power at snapshot
    VotingStatus status; // Current voting status
    string reason; // Reason for initiating vote
    bool executed; // Whether vote result was executed
}

struct Vote {
    address voter; // Address of voter
    VoteType voteType; // Invalid or Valid
    uint256 votingPower; // Voting power (token balance)
    uint256 timestamp; // When vote was cast
    string reason; // Optional reason for vote
}

// ============ EVENTS ============

interface ICampaignEvents {
    event CampaignCreated(
        uint256 indexed campaignId, address indexed creator, address indexed campaignContract, address tokenContract
    );

    event ContributionMade(
        uint256 indexed campaignId, address indexed contributor, uint256 amount, uint256 tokensReceived, uint256 tier
    );

    event CampaignStateChanged(uint256 indexed campaignId, CampaignState oldState, CampaignState newState);

    event FundsWithdrawn(uint256 indexed campaignId, address indexed creator, uint256 amount);

    event RefundClaimed(uint256 indexed campaignId, address indexed contributor, uint256 amount);

    event TokenLaunched(uint256 indexed campaignId, address indexed pair, uint256 liquidityAdded, uint256 initialPrice);

    event MilestoneCompleted(uint256 indexed campaignId, uint256 milestoneId, string description);

    event BonusTokensMinted(uint256 indexed campaignId, address indexed recipient, uint256 amount, string reason);

    // Medical verification events
    event VerificationUploaded(uint256 indexed campaignId, string documentHash, string description);

    event VerificationStatusChanged(
        uint256 indexed campaignId, VerificationStatus oldStatus, VerificationStatus newStatus, address verifier
    );

    // Community voting events
    event VoteInitiated(
        uint256 indexed campaignId, uint256 indexed voteId, address indexed initiator, string reason, uint256 endTime
    );

    event VoteCast(
        uint256 indexed campaignId,
        uint256 indexed voteId,
        address indexed voter,
        VoteType voteType,
        uint256 votingPower
    );

    event VoteExecuted(
        uint256 indexed campaignId, uint256 indexed voteId, bool passed, uint256 forVotes, uint256 againstVotes
    );

    event CampaignReported(uint256 indexed campaignId, address indexed reporter, string reason);
}
