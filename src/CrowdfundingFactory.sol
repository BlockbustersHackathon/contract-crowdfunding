// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICampaignStructs.sol";
import "./interfaces/ICampaignInterfaces.sol";
import "./Campaign.sol";
import "./Treasury.sol";
import "./PricingCurve.sol";
import "./DEXIntegrator.sol";

/**
 * @title CrowdfundingFactory
 * @dev Main factory contract for creating and managing crowdfunding campaigns
 */
contract CrowdfundingFactory is ICrowdfundingFactory, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Supporting contracts
    Treasury public immutable treasury;
    PricingCurve public immutable pricingCurve;
    DEXIntegrator public immutable dexIntegrator;
    
    // Campaign registry
    mapping(uint256 => address) public campaigns;
    mapping(address => uint256[]) public creatorCampaigns;
    mapping(address => uint256[]) public contributorCampaigns;
    
    // Token registry
    mapping(address => address) public tokenToCampaign;
    mapping(string => bool) public tokenSymbolUsed;
    
    // Platform settings
    mapping(address => bool) public approvedPaymentTokens;
    mapping(address => bool) public verifiedCreators;
    mapping(address => uint256) public creatorReputation;
    
    // Fee management
    mapping(address => uint256) public accumulatedFees;
    uint256 public defaultPlatformFeeBps = 250; // 2.5%
    address public feeRecipient;
    
    // Access control
    mapping(address => bool) public admins;
    mapping(address => bool) public pausers;
    bool public factoryPaused;
    
    // Statistics
    uint256 public totalCampaigns;
    uint256 public totalRaisedPlatform;
    uint256 public totalTokensCreated;
    
    // Campaign creation fee
    uint256 public campaignCreationFee = 0.01 ether;
    
    // Events
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        address indexed campaignContract,
        address tokenContract
    );
    event FactoryPaused();
    event FactoryUnpaused();
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event CreatorVerified(address indexed creator);
    event CreatorUnverified(address indexed creator);
    event PaymentTokenApproved(address indexed token);
    event PaymentTokenRemoved(address indexed token);
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event CampaignCreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    modifier onlyAdmin() {
        require(admins[msg.sender] || msg.sender == owner(), "Only admin");
        _;
    }

    modifier onlyPauser() {
        require(pausers[msg.sender] || admins[msg.sender] || msg.sender == owner(), "Only pauser");
        _;
    }

    modifier notPaused() {
        require(!factoryPaused, "Factory is paused");
        _;
    }

    modifier validCampaignConfig(CampaignConfig calldata config) {
        require(config.creator != address(0), "Invalid creator");
        require(config.fundingGoal > 0, "Invalid funding goal");
        require(config.endTime > block.timestamp, "Invalid end time");
        require(config.endTime <= block.timestamp + 365 days, "End time too far");
        require(config.hardCap >= config.fundingGoal, "Hard cap < funding goal");
        require(bytes(config.name).length > 0, "Name required");
        require(config.platformFeeBps <= 1000, "Fee too high"); // Max 10%
        
        // Validate payment token
        if (config.paymentToken != address(0)) {
            require(approvedPaymentTokens[config.paymentToken], "Payment token not approved");
        }
        _;
    }

    modifier validTokenConfig(TokenConfig calldata tokenConfig) {
        require(bytes(tokenConfig.name).length > 0, "Token name required");
        require(bytes(tokenConfig.symbol).length > 0, "Token symbol required");
        require(!tokenSymbolUsed[tokenConfig.symbol], "Symbol already used");
        require(tokenConfig.totalSupply > 0, "Invalid total supply");
        require(
            tokenConfig.creatorAllocation + tokenConfig.treasuryAllocation + tokenConfig.backersAllocation <= 10000,
            "Total allocation > 100%"
        );
        _;
    }

    constructor(
        address treasury_,
        address pricingCurve_,
        address payable dexIntegrator_,
        address feeRecipient_
    ) Ownable(msg.sender) {
        require(treasury_ != address(0), "Invalid treasury");
        require(pricingCurve_ != address(0), "Invalid pricing curve");
        require(dexIntegrator_ != address(0), "Invalid DEX integrator");
        require(feeRecipient_ != address(0), "Invalid fee recipient");
        
        treasury = Treasury(treasury_);
        pricingCurve = PricingCurve(pricingCurve_);
        dexIntegrator = DEXIntegrator(dexIntegrator_);
        feeRecipient = feeRecipient_;
        
        // Add deployer as admin
        admins[msg.sender] = true;
        pausers[msg.sender] = true;
        
        // Approve ETH as payment method (address(0))
        approvedPaymentTokens[address(0)] = true;
    }

    /**
     * @dev Create a new crowdfunding campaign
     * @param campaignConfig Campaign configuration
     * @param tokenConfig Token configuration
     * @param tiers Contribution tiers
     * @return campaignAddress Address of the created campaign
     * @return tokenAddress Address of the created token
     */
    function createCampaign(
        CampaignConfig calldata campaignConfig,
        TokenConfig calldata tokenConfig,
        ContributionTier[] calldata tiers
    ) external payable override nonReentrant notPaused 
      validCampaignConfig(campaignConfig)
      validTokenConfig(tokenConfig)
      returns (address campaignAddress, address tokenAddress) {
        
        // Check campaign creation fee
        require(msg.value >= campaignCreationFee, "Insufficient creation fee");
        
        // Validate tiers
        require(tiers.length > 0, "At least one tier required");
        _validateTiers(tiers);
        
        // Increment campaign counter
        uint256 campaignId = totalCampaigns++;
        
        // Use default platform fee if not specified
        CampaignConfig memory config = campaignConfig;
        if (config.platformFeeBps == 0) {
            config.platformFeeBps = uint16(defaultPlatformFeeBps);
        }
        
        // Deploy campaign contract
        Campaign campaign = new Campaign(
            campaignId,
            address(this),
            config,
            tokenConfig,
            tiers,
            address(pricingCurve),
            address(treasury),
            address(dexIntegrator)
        );
        
        campaignAddress = address(campaign);
        tokenAddress = address(campaign.campaignToken());
        
        // Register campaign
        campaigns[campaignId] = campaignAddress;
        creatorCampaigns[config.creator].push(campaignId);
        tokenToCampaign[tokenAddress] = campaignAddress;
        tokenSymbolUsed[tokenConfig.symbol] = true;
        
        // Update statistics
        totalTokensCreated++;
        
        // Send creation fee to fee recipient
        if (msg.value > 0) {
            payable(feeRecipient).transfer(msg.value);
        }
        
        emit CampaignCreated(campaignId, config.creator, campaignAddress, tokenAddress);
        
        return (campaignAddress, tokenAddress);
    }

    /**
     * @dev Pause the factory (emergency only)
     */
    function pauseFactory() external override onlyPauser {
        factoryPaused = true;
        emit FactoryPaused();
    }

    /**
     * @dev Unpause the factory
     */
    function unpauseFactory() external onlyAdmin {
        factoryPaused = false;
        emit FactoryUnpaused();
    }

    /**
     * @dev Update platform fee percentage
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint16 newFeeBps) external override onlyAdmin {
        require(newFeeBps <= 1000, "Fee too high"); // Max 10%
        
        uint256 oldFee = defaultPlatformFeeBps;
        defaultPlatformFeeBps = newFeeBps;
        
        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    /**
     * @dev Withdraw accumulated platform fees
     * @param token Token address (address(0) for ETH)
     */
    function withdrawPlatformFees(address token) external override {
        require(msg.sender == feeRecipient, "Only fee recipient");
        
        if (token == address(0)) {
            // Withdraw ETH fees
            uint256 balance = address(this).balance;
            require(balance > 0, "No ETH fees to withdraw");
            
            payable(feeRecipient).transfer(balance);
        } else {
            // Withdraw ERC20 fees
            uint256 balance = IERC20(token).balanceOf(address(this));
            require(balance > 0, "No token fees to withdraw");
            
            IERC20(token).safeTransfer(feeRecipient, balance);
        }
    }

    /**
     * @dev Verify a campaign creator
     * @param creator Address to verify
     */
    function verifyCreator(address creator) external override onlyAdmin {
        require(creator != address(0), "Invalid creator address");
        
        verifiedCreators[creator] = true;
        creatorReputation[creator] += 100; // Boost reputation
        
        emit CreatorVerified(creator);
    }

    /**
     * @dev Unverify a campaign creator
     * @param creator Address to unverify
     */
    function unverifyCreator(address creator) external onlyAdmin {
        require(creator != address(0), "Invalid creator address");
        
        verifiedCreators[creator] = false;
        
        emit CreatorUnverified(creator);
    }

    /**
     * @dev Approve an ERC20 token for payments
     * @param token Token address to approve
     */
    function approvePaymentToken(address token) external override onlyAdmin {
        require(token != address(0), "Cannot approve zero address");
        
        approvedPaymentTokens[token] = true;
        
        emit PaymentTokenApproved(token);
    }

    /**
     * @dev Remove approval for an ERC20 token
     * @param token Token address to remove
     */
    function removePaymentToken(address token) external onlyAdmin {
        require(token != address(0), "Cannot remove ETH");
        
        approvedPaymentTokens[token] = false;
        
        emit PaymentTokenRemoved(token);
    }

    /**
     * @dev Get campaigns created by a specific creator
     * @param creator Creator address
     * @return Array of campaign IDs
     */
    function getCampaignsByCreator(address creator) external view override returns (uint256[] memory) {
        return creatorCampaigns[creator];
    }

    /**
     * @dev Get campaign details by ID
     * @param campaignId Campaign ID
     * @return campaignAddress Address of the campaign contract
     * @return tokenAddress Address of the campaign token
     */
    function getCampaignDetails(uint256 campaignId) external view override returns (address campaignAddress, address tokenAddress) {
        campaignAddress = campaigns[campaignId];
        require(campaignAddress != address(0), "Campaign not found");
        
        Campaign campaign = Campaign(payable(campaignAddress));
        tokenAddress = address(campaign.campaignToken());
        
        return (campaignAddress, tokenAddress);
    }

    /**
     * @dev Check if an address is an admin
     * @param account Address to check
     * @return Whether the address is an admin
     */
    function isAdmin(address account) external view override returns (bool) {
        return admins[account] || account == owner();
    }

    /**
     * @dev Add a new admin
     * @param admin Address to add as admin
     */
    function addAdmin(address admin) external onlyOwner {
        require(admin != address(0), "Invalid admin address");
        require(!admins[admin], "Already admin");
        
        admins[admin] = true;
        pausers[admin] = true; // Admins can also pause
        
        emit AdminAdded(admin);
    }

    /**
     * @dev Remove an admin
     * @param admin Address to remove from admin
     */
    function removeAdmin(address admin) external onlyOwner {
        require(admin != address(0), "Invalid admin address");
        require(admins[admin], "Not an admin");
        require(admin != owner(), "Cannot remove owner");
        
        admins[admin] = false;
        pausers[admin] = false;
        
        emit AdminRemoved(admin);
    }

    /**
     * @dev Update campaign creation fee
     * @param newFee New creation fee in wei
     */
    function updateCampaignCreationFee(uint256 newFee) external onlyAdmin {
        uint256 oldFee = campaignCreationFee;
        campaignCreationFee = newFee;
        
        emit CampaignCreationFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Update fee recipient address
     * @param newRecipient New fee recipient address
     */
    function updateFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev Get platform statistics
     * @return _totalCampaigns Total number of campaigns created
     * @return _totalRaisedPlatform Total amount raised across all campaigns
     * @return _totalTokensCreated Total number of tokens created
     */
    function getPlatformStats() external view returns (
        uint256 _totalCampaigns,
        uint256 _totalRaisedPlatform,
        uint256 _totalTokensCreated
    ) {
        return (totalCampaigns, totalRaisedPlatform, totalTokensCreated);
    }

    /**
     * @dev Get campaign information by address
     * @param campaignAddress Campaign contract address
     * @return campaignId Campaign ID
     * @return tokenAddress Token contract address
     */
    function getCampaignInfo(address campaignAddress) external view returns (uint256 campaignId, address tokenAddress) {
        require(campaignAddress != address(0), "Invalid campaign address");
        
        Campaign campaign = Campaign(payable(campaignAddress));
        campaignId = campaign.campaignId();
        tokenAddress = address(campaign.campaignToken());
        
        return (campaignId, tokenAddress);
    }

    /**
     * @dev Check if a token symbol is available
     * @param symbol Token symbol to check
     * @return Whether the symbol is available
     */
    function isSymbolAvailable(string calldata symbol) external view returns (bool) {
        return !tokenSymbolUsed[symbol];
    }

    /**
     * @dev Get creator reputation score
     * @param creator Creator address
     * @return Reputation score
     */
    function getCreatorReputation(address creator) external view returns (uint256) {
        return creatorReputation[creator];
    }

    /**
     * @dev Internal function to validate contribution tiers
     * @param tiers Array of tiers to validate
     */
    function _validateTiers(ContributionTier[] calldata tiers) internal pure {
        for (uint256 i = 0; i < tiers.length; i++) {
            require(tiers[i].minContribution > 0, "Invalid min contribution");
            require(tiers[i].availableSlots > 0, "Invalid available slots");
            require(tiers[i].bonusMultiplier >= 10000, "Bonus cannot be negative");
            require(tiers[i].bonusMultiplier <= 15000, "Bonus too high"); // Max 50% bonus
            
            // Check tier ordering (higher tiers should have higher minimums)
            if (i > 0) {
                require(
                    tiers[i].minContribution >= tiers[i-1].minContribution,
                    "Tiers must be ordered by min contribution"
                );
            }
        }
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Token address to recover
     * @param to Address to send tokens to
     * @param amount Amount to recover
     */
    function emergencyTokenRecovery(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient");
        
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev Receive ETH function for fees
     */
    receive() external payable {
        // Allow contract to receive ETH fees
    }
}
