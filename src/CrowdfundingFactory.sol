// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Campaign.sol";
import "./TokenFactory.sol";
import "./PricingCurve.sol";
import "./DEXIntegrator.sol";
import "./interfaces/ICampaignStructs.sol";
import "./interfaces/ICampaignInterfaces.sol";

contract CrowdfundingFactory is ICrowdfundingFactory, ICampaignEvents, Ownable, ReentrancyGuard {
    TokenFactory public immutable tokenFactory;
    PricingCurve public immutable pricingCurve;
    DEXIntegrator public immutable dexIntegrator;
    
    mapping(uint256 => Campaign) public campaigns;
    mapping(address => uint256[]) public creatorCampaigns;
    mapping(address => uint256[]) public contributorCampaigns;
    
    uint256 public campaignCounter;
    uint256 public platformFeePercentage = 250; // 2.5%
    address public feeRecipient;
    
    uint256 public constant MIN_FUNDING_GOAL = 0.1 ether;
    uint256 public constant MAX_FUNDING_GOAL = 10000 ether;
    uint256 public constant MIN_DURATION = 1 days;
    uint256 public constant MAX_DURATION = 180 days;
    uint256 public constant MAX_PLATFORM_FEE = 1000; // 10%
    
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    
    modifier validCampaignParameters(
        uint256 fundingGoal,
        uint256 duration,
        uint256 creatorReservePercentage,
        uint256 liquidityPercentage
    ) {
        require(
            fundingGoal >= MIN_FUNDING_GOAL && fundingGoal <= MAX_FUNDING_GOAL,
            "CrowdfundingFactory: Invalid funding goal"
        );
        require(
            duration >= MIN_DURATION && duration <= MAX_DURATION,
            "CrowdfundingFactory: Invalid duration"
        );
        require(
            creatorReservePercentage <= 50,
            "CrowdfundingFactory: Creator reserve too high"
        );
        require(
            liquidityPercentage <= 80,
            "CrowdfundingFactory: Liquidity percentage too high"
        );
        _;
    }
    
    constructor(
        address _tokenFactory,
        address _pricingCurve,
        address _dexIntegrator,
        address _feeRecipient,
        address _owner
    ) Ownable(_owner) {
        require(_tokenFactory != address(0), "CrowdfundingFactory: Invalid token factory");
        require(_pricingCurve != address(0), "CrowdfundingFactory: Invalid pricing curve");
        require(_dexIntegrator != address(0), "CrowdfundingFactory: Invalid DEX integrator");
        require(_feeRecipient != address(0), "CrowdfundingFactory: Invalid fee recipient");
        
        tokenFactory = TokenFactory(_tokenFactory);
        pricingCurve = PricingCurve(_pricingCurve);
        dexIntegrator = DEXIntegrator(_dexIntegrator);
        feeRecipient = _feeRecipient;
    }
    
    function createCampaign(
        string memory metadataURI,
        uint256 fundingGoal,
        uint256 duration,
        uint256 creatorReservePercentage,
        uint256 liquidityPercentage,
        bool allowEarlyWithdrawal,
        string memory tokenName,
        string memory tokenSymbol
    ) external nonReentrant validCampaignParameters(
        fundingGoal,
        duration,
        creatorReservePercentage,
        liquidityPercentage
    ) returns (uint256 campaignId) {
        require(bytes(metadataURI).length > 0, "CrowdfundingFactory: Empty metadata URI");
        require(bytes(tokenName).length > 0, "CrowdfundingFactory: Empty token name");
        require(bytes(tokenSymbol).length > 0, "CrowdfundingFactory: Empty token symbol");
        
        campaignId = campaignCounter++;
        
        Campaign campaign = new Campaign(
            msg.sender,
            metadataURI,
            fundingGoal,
            duration,
            creatorReservePercentage,
            liquidityPercentage,
            allowEarlyWithdrawal,
            address(0), // Will be updated after token creation
            address(pricingCurve),
            address(dexIntegrator),
            address(this)
        );
        
        address tokenAddress = tokenFactory.createToken(
            tokenName,
            tokenSymbol,
            address(campaign),
            address(campaign)
        );
        
        campaign.setTokenAddress(tokenAddress);
        
        campaigns[campaignId] = campaign;
        creatorCampaigns[msg.sender].push(campaignId);
        
        emit CampaignCreated(
            campaignId,
            msg.sender,
            tokenAddress,
            fundingGoal,
            block.timestamp + duration
        );
        
        return campaignId;
    }
    
    function getCampaign(uint256 campaignId) external view returns (CampaignData memory) {
        require(campaignId < campaignCounter, "CrowdfundingFactory: Campaign does not exist");
        return campaigns[campaignId].getCampaignDetails();
    }
    
    function getCampaignsByCreator(address creator) external view returns (uint256[] memory) {
        return creatorCampaigns[creator];
    }
    
    function getCampaignCount() external view returns (uint256) {
        return campaignCounter;
    }
    
    function getCampaignAddress(uint256 campaignId) external view returns (address) {
        require(campaignId < campaignCounter, "CrowdfundingFactory: Campaign does not exist");
        return address(campaigns[campaignId]);
    }
    
    // Admin functions
    function setPlatformFee(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= MAX_PLATFORM_FEE, "CrowdfundingFactory: Fee too high");
        
        uint256 oldFee = platformFeePercentage;
        platformFeePercentage = newFeePercentage;
        
        emit PlatformFeeUpdated(oldFee, newFeePercentage);
    }
    
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "CrowdfundingFactory: Invalid fee recipient");
        
        address oldRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;
        
        emit FeeRecipientUpdated(oldRecipient, newFeeRecipient);
    }
    
    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "CrowdfundingFactory: No fees to withdraw");
        
        payable(feeRecipient).transfer(balance);
    }
    
    // Emergency functions
    function pauseCampaign(uint256 campaignId) external onlyOwner {
        require(campaignId < campaignCounter, "CrowdfundingFactory: Campaign does not exist");
        // Implementation would depend on adding pause functionality to Campaign contract
    }
    
    function emergencyWithdraw() external onlyOwner {
        // Emergency function for critical situations
        payable(owner()).transfer(address(this).balance);
    }
    
    receive() external payable {
        // Accept ETH for platform fees
    }
}