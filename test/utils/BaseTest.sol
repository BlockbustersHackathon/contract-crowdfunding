// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/CrowdfundingFactory.sol";
import "../../src/Campaign.sol";
import "../../src/CampaignToken.sol";
import "../../src/TokenFactory.sol";
import "../../src/PricingCurve.sol";
import "../../src/DEXIntegrator.sol";
import "../mocks/MockUniswapRouter.sol";
import "../mocks/MockUniswapFactory.sol";

contract BaseTest is Test {
    // Common test constants
    uint256 constant INITIAL_BALANCE = 100 ether;
    uint256 constant FUNDING_GOAL = 10 ether;
    uint256 constant CAMPAIGN_DURATION = 30 days;
    uint256 constant MIN_CONTRIBUTION = 0.001 ether;
    uint256 constant CREATOR_RESERVE = 20; // 20%
    uint256 constant LIQUIDITY_PERCENTAGE = 30; // 30%

    // Test accounts
    address deployer = makeAddr("deployer");
    address creator = makeAddr("creator");
    address contributor1 = makeAddr("contributor1");
    address contributor2 = makeAddr("contributor2");
    address contributor3 = makeAddr("contributor3");
    address maliciousUser = makeAddr("maliciousUser");
    address feeRecipient = makeAddr("feeRecipient");

    // Contract instances
    CrowdfundingFactory public factory;
    TokenFactory public tokenFactory;
    PricingCurve public pricingCurve;
    DEXIntegrator public dexIntegrator;
    MockUniswapRouter public mockRouter;
    MockUniswapFactory public mockUniswapFactory;

    function setUp() public virtual {
        vm.startPrank(deployer);

        // Deploy mock Uniswap contracts
        mockRouter = new MockUniswapRouter();
        mockUniswapFactory = new MockUniswapFactory();

        // Deploy core contracts
        tokenFactory = new TokenFactory();
        pricingCurve = new PricingCurve();
        dexIntegrator = new DEXIntegrator(address(mockRouter), address(mockUniswapFactory));

        // Deploy main factory
        factory = new CrowdfundingFactory(
            address(tokenFactory), address(pricingCurve), address(dexIntegrator), feeRecipient, deployer
        );

        vm.stopPrank();

        // Fund test accounts
        vm.deal(creator, INITIAL_BALANCE);
        vm.deal(contributor1, INITIAL_BALANCE);
        vm.deal(contributor2, INITIAL_BALANCE);
        vm.deal(contributor3, INITIAL_BALANCE);
        vm.deal(maliciousUser, INITIAL_BALANCE);
    }

    // Helper functions
    function createTestCampaign() internal returns (uint256 campaignId) {
        vm.prank(creator);
        campaignId = factory.createCampaign(
            "ipfs://test-metadata",
            FUNDING_GOAL,
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            true, // allowEarlyWithdrawal
            "Test Token",
            "TEST"
        );
    }

    function createTestCampaignWithGoalRequired() internal returns (uint256 campaignId) {
        vm.prank(creator);
        campaignId = factory.createCampaign(
            "ipfs://test-metadata",
            FUNDING_GOAL,
            CAMPAIGN_DURATION,
            CREATOR_RESERVE,
            LIQUIDITY_PERCENTAGE,
            false, // allowEarlyWithdrawal - goal required
            "Test Token",
            "TEST"
        );
    }

    function getCampaign(uint256 campaignId) internal view returns (Campaign) {
        return Campaign(payable(factory.getCampaignAddress(campaignId)));
    }

    function contributeToCompaign(uint256 campaignId, address contributor, uint256 amount) internal {
        Campaign campaign = getCampaign(campaignId);
        vm.prank(contributor);
        campaign.contribute{value: amount}();
    }

    function fastForwardToDeadline(uint256 campaignId) internal {
        CampaignData memory data = factory.getCampaign(campaignId);
        vm.warp(data.deadline + 1);
    }

    function fastForwardTime(uint256 timeIncrease) internal {
        vm.warp(block.timestamp + timeIncrease);
    }

    function assertCampaignState(uint256 campaignId, CampaignState expectedState) internal {
        Campaign campaign = getCampaign(campaignId);
        campaign.updateCampaignState();
        assertEq(uint256(campaign.getCampaignState()), uint256(expectedState));
    }

    // Custom assertions
    function assertContributionExists(uint256 campaignId, address contributor, uint256 expectedAmount) internal {
        Campaign campaign = getCampaign(campaignId);
        Contribution memory contribution = campaign.getContribution(contributor);
        assertEq(contribution.amount, expectedAmount);
        assertEq(contribution.contributor, contributor);
    }

    function assertTokenBalance(address token, address account, uint256 expectedBalance) internal {
        assertEq(IERC20(token).balanceOf(account), expectedBalance);
    }
}
