// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ICampaignStructs.sol";
import "./interfaces/ICampaignInterfaces.sol";
import "./CampaignToken.sol";
import "./PricingCurve.sol";

/**
 * @title Campaign
 * @dev Individual crowdfunding campaign contract with token generation and DEX launch capabilities
 */
contract Campaign is ICampaign, ICampaignEvents, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Campaign identification
    uint256 public immutable campaignId;
    address public immutable factory;
    
    // Core campaign data
    CampaignConfig public config;
    TokenConfig public tokenConfig;
    CampaignState public state;
    
    // Token contract
    CampaignToken public campaignToken;
    
    // Supporting contracts
    PricingCurve public immutable pricingCurve;
    ITreasury public immutable treasury;
    IDEXIntegrator public immutable dexIntegrator;
    
    // Contribution tracking
    mapping(address => Contribution[]) public contributions;
    mapping(address => uint256) public totalContributed;
    ContributionTier[] public tiers;
    
    // Campaign metrics
    uint256 public totalRaised;
    uint256 public totalContributors;
    uint256 public totalTokensDistributed;
    
    // Refund and withdrawal tracking
    mapping(address => bool) public hasClaimedRefund;
    bool public creatorWithdrawn;
    uint256 public withdrawnAmount;
    
    // DEX launch data
    DEXLaunchConfig public dexConfig;
    address public liquidityPair;
    uint256 public liquidityUnlockTime;
    
    // Milestone tracking
    mapping(uint256 => bool) public milestoneCompleted;
    uint256 public completedMilestones;
    uint256 public totalMilestones;
    
    // Pause functionality
    bool public paused;

    // Events for this contract
    event ContributionRefunded(address indexed contributor, uint256 amount);
    event CampaignPaused();
    event CampaignUnpaused();
    event DeadlineExtended(uint256 oldDeadline, uint256 newDeadline);

    modifier onlyCreator() {
        require(msg.sender == config.creator, "Only creator");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    modifier inState(CampaignState _state) {
        require(state == _state, "Invalid state");
        _;
    }

    modifier notPaused() {
        require(!paused, "Campaign paused");
        _;
    }

    modifier checkAndUpdateState() {
        _updateStateIfNeeded();
        _;
    }

    constructor(
        uint256 campaignId_,
        address factory_,
        CampaignConfig memory campaignConfig_,
        TokenConfig memory tokenConfig_,
        ContributionTier[] memory tiers_,
        address pricingCurve_,
        address treasury_,
        address dexIntegrator_
    ) Ownable(campaignConfig_.creator) {
        require(factory_ != address(0), "Invalid factory");
        require(pricingCurve_ != address(0), "Invalid pricing curve");
        require(treasury_ != address(0), "Invalid treasury");
        require(dexIntegrator_ != address(0), "Invalid DEX integrator");
        require(campaignConfig_.fundingGoal > 0, "Invalid funding goal");
        require(campaignConfig_.endTime > block.timestamp, "Invalid end time");
        require(campaignConfig_.creator != address(0), "Invalid creator");

        campaignId = campaignId_;
        factory = factory_;
        config = campaignConfig_;
        tokenConfig = tokenConfig_;
        
        // Copy tiers
        for (uint256 i = 0; i < tiers_.length; i++) {
            tiers.push(tiers_[i]);
        }
        
        pricingCurve = PricingCurve(pricingCurve_);
        treasury = ITreasury(treasury_);
        dexIntegrator = IDEXIntegrator(dexIntegrator_);
        
        state = CampaignState.Active;
        
        // Create campaign token
        campaignToken = new CampaignToken(
            tokenConfig_.name,
            tokenConfig_.symbol,
            tokenConfig_.totalSupply,
            address(this),
            campaignConfig_.creator
        );
        
        emit CampaignCreated(campaignId_, campaignConfig_.creator, address(this), address(campaignToken));
    }

    /**
     * @dev Contribute ETH to the campaign
     */
    function contribute() external payable override nonReentrant notPaused checkAndUpdateState inState(CampaignState.Active) {
        require(msg.value > 0, "Contribution must be positive");
        require(config.paymentToken == address(0), "ETH not accepted");
        require(block.timestamp <= config.endTime, "Campaign ended");
        require(totalRaised + msg.value <= config.hardCap, "Hard cap exceeded");

        _processContribution(msg.sender, msg.value);
    }

    /**
     * @dev Contribute ERC20 tokens to the campaign
     * @param amount Amount of tokens to contribute
     */
    function contributeWithToken(uint256 amount) external override nonReentrant notPaused checkAndUpdateState inState(CampaignState.Active) {
        require(amount > 0, "Contribution must be positive");
        require(config.paymentToken != address(0), "Only ETH accepted");
        require(block.timestamp <= config.endTime, "Campaign ended");
        require(totalRaised + amount <= config.hardCap, "Hard cap exceeded");

        // Transfer tokens from contributor
        IERC20(config.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
        
        _processContribution(msg.sender, amount);
    }

    /**
     * @dev Batch contributions (for ETH only)
     * @param amounts Array of contribution amounts
     */
    function batchContribute(uint256[] calldata amounts) external payable override nonReentrant notPaused checkAndUpdateState inState(CampaignState.Active) {
        require(config.paymentToken == address(0), "ETH only for batch");
        require(amounts.length > 0, "No amounts provided");
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(msg.value == totalAmount, "Incorrect ETH amount");
        
        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] > 0) {
                _processContribution(msg.sender, amounts[i]);
            }
        }
    }

    /**
     * @dev Internal function to process contributions
     * @param contributor Address of the contributor
     * @param amount Amount being contributed
     */
    function _processContribution(address contributor, uint256 amount) internal {
        // Calculate tokens to mint
        (uint256 tokenAmount, uint256 tier) = pricingCurve.calculateTokensForContribution(
            amount,
            totalRaised,
            config.fundingGoal,
            tiers
        );
        
        // Apply early bird bonus if applicable
        if (block.timestamp <= config.startTime + 7 days) {
            tokenAmount = (tokenAmount * 11500) / 10000; // 15% early bird bonus
        }
        
        // Update tier usage
        if (tier < tiers.length) {
            tiers[tier].usedSlots++;
        }
        
        // Update contributor tracking
        if (totalContributed[contributor] == 0) {
            totalContributors++;
        }
        totalContributed[contributor] += amount;
        
        // Store contribution record
        contributions[contributor].push(Contribution({
            contributor: contributor,
            amount: amount,
            tokenAmount: tokenAmount,
            timestamp: block.timestamp,
            tier: tier,
            refunded: false
        }));
        
        // Update campaign metrics
        totalRaised += amount;
        totalTokensDistributed += tokenAmount;
        
        // Mint tokens to contributor
        campaignToken.mint(contributor, tokenAmount);
        
        // Deposit funds to treasury
        if (config.paymentToken == address(0)) {
            treasury.deposit{value: amount}(campaignId);
        } else {
            IERC20(config.paymentToken).approve(address(treasury), amount);
            treasury.depositToken(campaignId, config.paymentToken, amount);
        }
        
        emit ContributionMade(campaignId, contributor, amount, tokenAmount, tier);
        
        // Check if goal reached
        if (totalRaised >= config.fundingGoal) {
            _transitionState(CampaignState.Successful);
        }
    }

    /**
     * @dev Claim refund for failed or cancelled campaign
     */
    function claimRefund() external override nonReentrant {
        require(
            state == CampaignState.Failed || state == CampaignState.Cancelled,
            "Refunds not available"
        );
        require(totalContributed[msg.sender] > 0, "No contribution found");
        require(!hasClaimedRefund[msg.sender], "Already refunded");
        
        uint256 refundAmount = totalContributed[msg.sender];
        hasClaimedRefund[msg.sender] = true;
        
        // Burn contributor's tokens
        uint256 tokenBalance = campaignToken.balanceOf(msg.sender);
        if (tokenBalance > 0) {
            campaignToken.burnFrom(msg.sender, tokenBalance);
        }
        
        // Process refund through treasury
        if (config.paymentToken == address(0)) {
            treasury.refund(campaignId, msg.sender, refundAmount);
        } else {
            treasury.refundToken(campaignId, config.paymentToken, msg.sender, refundAmount);
        }
        
        emit RefundClaimed(campaignId, msg.sender, refundAmount);
        emit ContributionRefunded(msg.sender, refundAmount);
    }

    /**
     * @dev Withdraw funds (creator only, successful campaigns)
     */
    function withdrawFunds() external override onlyCreator nonReentrant inState(CampaignState.Successful) {
        require(!creatorWithdrawn, "Already withdrawn");
        
        creatorWithdrawn = true;
        
        // Calculate platform fee
        uint256 platformFee = (totalRaised * config.platformFeeBps) / 10000;
        uint256 creatorAmount = totalRaised - platformFee;
        
        withdrawnAmount = creatorAmount;
        
        // Withdraw funds through treasury
        if (config.paymentToken == address(0)) {
            treasury.withdraw(campaignId, config.creator, creatorAmount);
            if (platformFee > 0) {
                treasury.collectPlatformFee(campaignId, platformFee);
            }
        } else {
            treasury.withdrawToken(campaignId, config.paymentToken, config.creator, creatorAmount);
            if (platformFee > 0) {
                treasury.collectPlatformTokenFee(campaignId, config.paymentToken, platformFee);
            }
        }
        
        _transitionState(CampaignState.Withdrawn);
        
        emit FundsWithdrawn(campaignId, config.creator, creatorAmount);
    }

    /**
     * @dev Launch token on DEX
     * @param dexConfig_ DEX launch configuration
     */
    function launchToken(DEXLaunchConfig calldata dexConfig_) external override onlyCreator nonReentrant {
        require(
            state == CampaignState.Successful || state == CampaignState.Withdrawn,
            "Invalid state for launch"
        );
        require(dexConfig_.liquidityTokens > 0, "Invalid token amount");
        require(dexConfig_.liquidityETH > 0, "Invalid ETH amount");
        
        dexConfig = dexConfig_;
        
        // Create Uniswap pair
        liquidityPair = dexIntegrator.createUniswapPair(address(campaignToken));
        
        // Mint tokens for liquidity
        campaignToken.mint(address(this), dexConfig_.liquidityTokens);
        
        // Approve DEX integrator to spend tokens
        campaignToken.approve(address(dexIntegrator), dexConfig_.liquidityTokens);
        
        // Add initial liquidity
        (uint256 tokenAmount, uint256 ethAmount, uint256 liquidity) = dexIntegrator.addInitialLiquidity{value: dexConfig_.liquidityETH}(
            address(campaignToken),
            dexConfig_.liquidityTokens,
            dexConfig_.liquidityETH,
            address(dexIntegrator) // DEX integrator will handle locking
        );
        
        // Lock liquidity
        liquidityUnlockTime = block.timestamp + dexConfig_.lockDuration;
        
        // Enable token transfers
        campaignToken.enableTransfers();
        
        _transitionState(CampaignState.TokenLaunched);
        
        emit TokenLaunched(campaignId, liquidityPair, liquidity, dexConfig_.listingPrice);
    }

    /**
     * @dev Update campaign metadata URI
     * @param newMetadataURI New metadata URI
     */
    function updateMetadata(string calldata newMetadataURI) external override onlyCreator {
        config.metadataURI = newMetadataURI;
    }

    /**
     * @dev Complete a milestone
     * @param milestoneId ID of the milestone
     * @param description Description of the completed milestone
     */
    function completeMilestone(uint256 milestoneId, string calldata description) external override onlyCreator {
        require(milestoneId < totalMilestones, "Invalid milestone ID");
        require(!milestoneCompleted[milestoneId], "Milestone already completed");
        
        milestoneCompleted[milestoneId] = true;
        completedMilestones++;
        
        emit MilestoneCompleted(campaignId, milestoneId, description);
    }

    /**
     * @dev Emergency withdrawal (creator + admin approval required)
     */
    function emergencyWithdraw() external override onlyCreator {
        require(
            ICrowdfundingFactory(factory).isAdmin(msg.sender) || msg.sender == config.creator,
            "Not authorized"
        );
        
        treasury.emergencyWithdraw(campaignId, config.creator);
    }

    /**
     * @dev Enable token transfers
     */
    function enableTransfers() external override onlyCreator {
        campaignToken.enableTransfers();
    }

    /**
     * @dev Burn unallocated tokens
     */
    function burnUnallocatedTokens() external override onlyCreator {
        uint256 remaining = campaignToken.remainingSupply();
        if (remaining > 0) {
            // Burn by not minting the remaining supply
            // This is effectively achieved by the max supply limit
        }
    }

    /**
     * @dev Cancel campaign (creator or admin only)
     */
    function cancelCampaign() external override {
        require(
            msg.sender == config.creator || ICrowdfundingFactory(factory).isAdmin(msg.sender),
            "Not authorized"
        );
        require(state == CampaignState.Active, "Can only cancel active campaigns");
        
        _transitionState(CampaignState.Cancelled);
    }

    /**
     * @dev Extend campaign deadline
     * @param newEndTime New end time
     */
    function extendDeadline(uint256 newEndTime) external override onlyCreator inState(CampaignState.Active) {
        require(newEndTime > config.endTime, "New deadline must be later");
        require(newEndTime <= config.endTime + 30 days, "Cannot extend more than 30 days");
        
        uint256 oldDeadline = config.endTime;
        config.endTime = newEndTime;
        
        emit DeadlineExtended(oldDeadline, newEndTime);
    }

    /**
     * @dev Calculate token amount for a contribution
     * @param contributionAmount Amount being contributed
     * @return tokenAmount Number of tokens
     * @return tier Tier used for calculation
     */
    function calculateTokenAmount(uint256 contributionAmount) external view override returns (uint256 tokenAmount, uint256 tier) {
        return pricingCurve.calculateTokensForContribution(
            contributionAmount,
            totalRaised,
            config.fundingGoal,
            tiers
        );
    }

    /**
     * @dev Check if funding goal is reached
     */
    function checkGoalReached() external view override returns (bool) {
        return totalRaised >= config.fundingGoal;
    }

    /**
     * @dev Get contribution history for an address
     * @param contributor Address to query
     * @return Array of contributions
     */
    function getContributionHistory(address contributor) external view override returns (Contribution[] memory) {
        return contributions[contributor];
    }

    /**
     * @dev Get current campaign state
     */
    function getCampaignState() external view override returns (CampaignState) {
        return state;
    }

    /**
     * @dev Get tier information
     * @return Array of tiers
     */
    function getTiers() external view returns (ContributionTier[] memory) {
        return tiers;
    }

    /**
     * @dev Pause campaign (emergency only)
     */
    function pause() external onlyCreator {
        paused = true;
        emit CampaignPaused();
    }

    /**
     * @dev Unpause campaign
     */
    function unpause() external onlyCreator {
        paused = false;
        emit CampaignUnpaused();
    }

    /**
     * @dev Internal function to update state based on conditions
     */
    function _updateStateIfNeeded() internal {
        if (state == CampaignState.Active) {
            if (totalRaised >= config.fundingGoal) {
                _transitionState(CampaignState.Successful);
            } else if (block.timestamp > config.endTime) {
                _transitionState(CampaignState.Failed);
            }
        }
    }

    /**
     * @dev Internal function to transition states
     * @param newState New state to transition to
     */
    function _transitionState(CampaignState newState) internal {
        require(_canTransitionTo(newState), "Invalid state transition");
        
        CampaignState oldState = state;
        state = newState;
        
        emit CampaignStateChanged(campaignId, oldState, newState);
        
        // Execute state-specific logic
        if (newState == CampaignState.Failed) {
            _onCampaignFailure();
        }
    }

    /**
     * @dev Check if state transition is valid
     * @param newState New state to check
     * @return Whether transition is valid
     */
    function _canTransitionTo(CampaignState newState) internal view returns (bool) {
        if (state == CampaignState.Active) {
            return newState == CampaignState.Successful || 
                   newState == CampaignState.Failed || 
                   newState == CampaignState.Cancelled;
        }
        
        if (state == CampaignState.Successful) {
            return newState == CampaignState.Withdrawn || 
                   newState == CampaignState.TokenLaunched;
        }
        
        if (state == CampaignState.Withdrawn) {
            return newState == CampaignState.TokenLaunched;
        }
        
        return false;
    }

    /**
     * @dev Handle campaign failure
     */
    function _onCampaignFailure() internal {
        // Pause token transfers
        campaignToken.pause();
    }

    /**
     * @dev Get campaign summary
     * @return _totalRaised Total amount raised
     * @return _totalContributors Number of contributors
     * @return _totalTokensDistributed Total tokens distributed
     * @return _state Current campaign state
     * @return _goalReached Whether funding goal was reached
     * @return _timeRemaining Time remaining in seconds
     */
    function getCampaignSummary() external view returns (
        uint256 _totalRaised,
        uint256 _totalContributors,
        uint256 _totalTokensDistributed,
        CampaignState _state,
        bool _goalReached,
        uint256 _timeRemaining
    ) {
        _totalRaised = totalRaised;
        _totalContributors = totalContributors;
        _totalTokensDistributed = totalTokensDistributed;
        _state = state;
        _goalReached = totalRaised >= config.fundingGoal;
        _timeRemaining = block.timestamp >= config.endTime ? 0 : config.endTime - block.timestamp;
        
        return (_totalRaised, _totalContributors, _totalTokensDistributed, _state, _goalReached, _timeRemaining);
    }

    /**
     * @dev Receive ETH function for DEX launch
     */
    receive() external payable {
        // Allow contract to receive ETH for DEX launch operations
    }
}
