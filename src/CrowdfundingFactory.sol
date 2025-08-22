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
    address public immutable usdcToken;

    mapping(uint256 => Campaign) public campaigns;
    mapping(address => uint256[]) public creatorCampaigns;
    mapping(address => uint256[]) public contributorCampaigns;

    uint256 public campaignCounter;

    uint256 public constant MIN_FUNDING_GOAL = 100e6; // 100 USDC
    uint256 public constant MAX_FUNDING_GOAL = 10000000e6; // 10M USDC
    uint256 public constant MIN_DURATION = 0 days;
    uint256 public constant MAX_DURATION = 180 days;

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
        require(duration >= MIN_DURATION && duration <= MAX_DURATION, "CrowdfundingFactory: Invalid duration");
        require(creatorReservePercentage == 25, "CrowdfundingFactory: Creator reserve too high");
        _;
    }

    constructor(
        address _tokenFactory,
        address _pricingCurve,
        address _dexIntegrator,
        address _usdcToken,
        address _owner
    ) Ownable(_owner) {
        require(_tokenFactory != address(0), "CrowdfundingFactory: Invalid token factory");
        require(_pricingCurve != address(0), "CrowdfundingFactory: Invalid pricing curve");
        require(_dexIntegrator != address(0), "CrowdfundingFactory: Invalid DEX integrator");
        require(_usdcToken != address(0), "CrowdfundingFactory: Invalid USDC token");

        tokenFactory = TokenFactory(_tokenFactory);
        pricingCurve = PricingCurve(_pricingCurve);
        dexIntegrator = DEXIntegrator(_dexIntegrator);
        usdcToken = _usdcToken;
    }

    function createCampaign(
        string memory name,
        string memory metadataURI,
        uint256 fundingGoal,
        uint256 duration,
        uint256 creatorReservePercentage,
        uint256 liquidityPercentage,
        string memory tokenName,
        string memory tokenSymbol
    )
        external
        nonReentrant
        validCampaignParameters(fundingGoal, duration, creatorReservePercentage, liquidityPercentage)
        returns (uint256 campaignId, address campaignAddress)
    {
        require(bytes(name).length > 0, "CrowdfundingFactory: Empty campaign name");
        require(bytes(metadataURI).length > 0, "CrowdfundingFactory: Empty metadata URI");
        require(bytes(tokenName).length > 0, "CrowdfundingFactory: Empty token name");
        require(bytes(tokenSymbol).length > 0, "CrowdfundingFactory: Empty token symbol");

        campaignId = campaignCounter++;

        Campaign campaign = new Campaign(
            msg.sender,
            name,
            metadataURI,
            fundingGoal,
            duration,
            creatorReservePercentage,
            liquidityPercentage,
            address(0), // Will be updated after token creation
            address(pricingCurve),
            address(dexIntegrator),
            usdcToken,
            address(this)
        );

        address tokenAddress = tokenFactory.createToken(tokenName, tokenSymbol, address(campaign), address(campaign));

        campaign.setTokenAddress(tokenAddress);

        campaigns[campaignId] = campaign;
        creatorCampaigns[msg.sender].push(campaignId);

        campaignAddress = address(campaign);

        emit CampaignCreated(campaignId, msg.sender, tokenAddress, fundingGoal, block.timestamp + duration);

        return (campaignId, campaignAddress);
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
}
