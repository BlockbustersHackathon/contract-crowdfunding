// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICampaignStructs.sol";
import "./interfaces/ICampaignInterfaces.sol";
import "./CampaignToken.sol";
import "./PricingCurve.sol";
import "./DEXIntegrator.sol";

contract Campaign is ICampaign, ICampaignEvents, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    CampaignData public campaignData;
    CampaignToken public campaignToken;
    PricingCurve public immutable pricingCurve;
    DEXIntegrator public immutable dexIntegrator;
    IERC20 public immutable usdcToken;

    mapping(address => Contribution) public contributions;
    mapping(address => bool) public hasContributed;
    address[] public contributors;

    uint256 public constant MIN_CONTRIBUTION = 1e6; // 1 USDC (6 decimals)
    uint256 public constant TOTAL_SUPPLY = 1e27; // 1 billion tokens (18 decimals)
    uint256 public constant CREATOR_RESERVE_PERCENTAGE = 25; // 25% fixed
    uint256 public constant MAX_LIQUIDITY_PERCENTAGE = 80; // 80% max
    uint256 public constant EXTENSION_LIMIT = 30 days;

    modifier onlyCreator() {
        require(msg.sender == campaignData.creator, "Campaign: Only creator can call");
        _;
    }

    modifier onlyActiveState() {
        require(campaignData.state == CampaignState.Active, "Campaign: Campaign not active");
        _;
    }

    modifier campaignNotExpired() {
        require(block.timestamp <= campaignData.deadline, "Campaign: Campaign expired");
        _;
    }

    constructor(
        address _creator,
        string memory _metadataURI,
        uint256 _fundingGoal,
        uint256 _duration,
        uint256 _creatorReservePercentage,
        uint256 _liquidityPercentage,
        address _tokenAddress,
        address _pricingCurve,
        address _dexIntegrator,
        address _usdcToken,
        address _owner
    ) Ownable(_owner) {
        require(_creator != address(0), "Campaign: Invalid creator address");
        require(_fundingGoal > 0, "Campaign: Funding goal must be greater than zero");
        require(_duration > 0, "Campaign: Duration must be greater than zero");
        require(_creatorReservePercentage == CREATOR_RESERVE_PERCENTAGE, "Campaign: Creator reserve must be 25%");
        require(_liquidityPercentage <= MAX_LIQUIDITY_PERCENTAGE, "Campaign: Liquidity percentage too high");
        require(_pricingCurve != address(0), "Campaign: Invalid pricing curve address");
        require(_dexIntegrator != address(0), "Campaign: Invalid DEX integrator address");
        require(_usdcToken != address(0), "Campaign: Invalid USDC token address");

        campaignData = CampaignData({
            creator: _creator,
            metadataURI: _metadataURI,
            fundingGoal: _fundingGoal,
            deadline: block.timestamp + _duration,
            totalRaised: 0,
            creatorReservePercentage: _creatorReservePercentage,
            liquidityPercentage: _liquidityPercentage,
            tokenAddress: _tokenAddress,
            state: CampaignState.Active,
            createdAt: block.timestamp
        });

        pricingCurve = PricingCurve(_pricingCurve);
        dexIntegrator = DEXIntegrator(_dexIntegrator);
        usdcToken = IERC20(_usdcToken);
    }

    function contribute(uint256 amount) external nonReentrant onlyActiveState campaignNotExpired {
        require(amount >= MIN_CONTRIBUTION, "Campaign: Contribution below minimum");
        require(msg.sender != campaignData.creator, "Campaign: Creator cannot contribute");

        uint256 tokenAllocation = pricingCurve.calculateTokenAllocation(amount, campaignData.fundingGoal);

        usdcToken.safeTransferFrom(msg.sender, address(this), amount);

        if (!hasContributed[msg.sender]) {
            contributors.push(msg.sender);
            hasContributed[msg.sender] = true;
        }

        contributions[msg.sender].contributor = msg.sender;
        contributions[msg.sender].amount += amount;
        contributions[msg.sender].timestamp = block.timestamp;
        contributions[msg.sender].tokenAllocation += tokenAllocation;

        campaignData.totalRaised += amount;

        emit ContributionMade(0, msg.sender, amount, tokenAllocation);

        updateCampaignState();
    }

    function claimTokens() external nonReentrant {
        require(hasContributed[msg.sender], "Campaign: No contribution found");
        require(!contributions[msg.sender].claimed, "Campaign: Tokens already claimed");
        require(campaignData.state == CampaignState.Succeeded, "Campaign: Cannot claim tokens yet");

        uint256 tokenAmount = contributions[msg.sender].tokenAllocation;
        require(tokenAmount > 0, "Campaign: No tokens to claim");

        contributions[msg.sender].claimed = true;

        campaignToken.mint(msg.sender, tokenAmount);

        emit TokensClaimed(0, msg.sender, tokenAmount);
    }

    function withdrawFunds() external nonReentrant onlyCreator {
        require(campaignData.state == CampaignState.Succeeded, "Campaign: Campaign must be successful");
        require(campaignData.totalRaised > 0, "Campaign: No funds to withdraw");

        uint256 amount = campaignData.totalRaised;
        _mintCreatorReserve();

        usdcToken.safeTransfer(campaignData.creator, amount);

        emit FundsWithdrawn(0, campaignData.creator, amount);
    }

    function refund() external nonReentrant {
        require(hasContributed[msg.sender], "Campaign: No contribution found");
        require(campaignData.state == CampaignState.Failed, "Campaign: Refunds not available");

        uint256 amount = contributions[msg.sender].amount;
        require(amount > 0, "Campaign: No funds to refund");

        contributions[msg.sender].amount = 0;

        usdcToken.safeTransfer(msg.sender, amount);

        emit RefundIssued(0, msg.sender, amount);
    }

    function createLiquidityPool() external nonReentrant onlyCreator {
        require(campaignData.state == CampaignState.Succeeded, "Campaign: Campaign must be successful");
        require(campaignData.liquidityPercentage > 0, "Campaign: No liquidity allocation");

        uint256 usdcForLiquidity = (campaignData.totalRaised * campaignData.liquidityPercentage) / 100;
        require(usdcForLiquidity > 0, "Campaign: No USDC for liquidity");

        // Mint creator reserve excluding liquidity portion
        _mintCreatorReserveWithoutLiquidity();

        // Calculate and mint tokens for liquidity pool
        uint256 totalCreatorTokens = (TOTAL_SUPPLY * CREATOR_RESERVE_PERCENTAGE) / 100;
        uint256 tokensForLiquidity = (totalCreatorTokens * campaignData.liquidityPercentage) / 100;

        campaignToken.mint(address(this), tokensForLiquidity);

        IERC20(address(campaignToken)).approve(address(dexIntegrator), tokensForLiquidity);
        usdcToken.approve(address(dexIntegrator), usdcForLiquidity);

        (uint256 tokenAmount, uint256 usdcAmount,) =
            dexIntegrator.addLiquidity(address(campaignToken), tokensForLiquidity, address(usdcToken), usdcForLiquidity);

        uint256 remainingUSDC = campaignData.totalRaised - usdcAmount;
        if (remainingUSDC > 0) {
            usdcToken.safeTransfer(campaignData.creator, remainingUSDC);
        }

        emit LiquidityPoolCreated(0, address(dexIntegrator), tokenAmount, usdcAmount);
    }

    function extendDeadline(uint256 newDeadline) external onlyCreator onlyActiveState {
        require(newDeadline > campaignData.deadline, "Campaign: New deadline must be later");
        require(newDeadline <= campaignData.deadline + EXTENSION_LIMIT, "Campaign: Extension exceeds limit");

        campaignData.deadline = newDeadline;
    }

    function updateCampaignState() public {
        if (campaignData.state != CampaignState.Active) {
            return;
        }

        CampaignState previousState = campaignData.state;

        if (campaignData.totalRaised >= campaignData.fundingGoal) {
            campaignData.state = CampaignState.Succeeded;
            emit CampaignSucceeded(0, campaignData.totalRaised);
        } else if (block.timestamp > campaignData.deadline) {
            campaignData.state = CampaignState.Failed;
            emit CampaignFailed(0, campaignData.totalRaised);
        }

        if (campaignData.state != previousState) {
            emit CampaignStateChanged(0, previousState, campaignData.state);
        }
    }

    function _mintCreatorReserve() internal {
        uint256 creatorTokens = (TOTAL_SUPPLY * CREATOR_RESERVE_PERCENTAGE) / 100;

        if (creatorTokens > 0) {
            campaignToken.mint(campaignData.creator, creatorTokens);
        }
    }

    function _mintCreatorReserveWithoutLiquidity() internal {
        uint256 totalCreatorTokens = (TOTAL_SUPPLY * CREATOR_RESERVE_PERCENTAGE) / 100;
        uint256 tokensForLiquidity = (totalCreatorTokens * campaignData.liquidityPercentage) / 100;
        uint256 creatorTokensToKeep = totalCreatorTokens - tokensForLiquidity;

        if (creatorTokensToKeep > 0) {
            campaignToken.mint(campaignData.creator, creatorTokensToKeep);
        }
    }

    function _calculateTotalTokenSupply() internal pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    // View functions
    function getCampaignDetails() external view returns (CampaignData memory) {
        return campaignData;
    }

    function getContribution(address contributor) external view returns (Contribution memory) {
        return contributions[contributor];
    }

    function calculateTokenAllocation(uint256 contributionAmount) external view returns (uint256) {
        return pricingCurve.calculateTokenAllocation(contributionAmount, campaignData.fundingGoal);
    }

    function getCampaignState() external view returns (CampaignState) {
        return campaignData.state;
    }

    function getContributors() external view returns (address[] memory) {
        return contributors;
    }

    function getContributorCount() external view returns (uint256) {
        return contributors.length;
    }

    function setTokenAddress(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(0), "Campaign: Invalid token address");
        campaignData.tokenAddress = _tokenAddress;
        campaignToken = CampaignToken(_tokenAddress);
    }

    // Remove receive function since we're not accepting ETH anymore
}
