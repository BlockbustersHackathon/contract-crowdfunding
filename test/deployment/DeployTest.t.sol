// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/CrowdfundingFactory.sol";
import "../../src/TokenFactory.sol";
import "../../src/PricingCurve.sol";
import "../../src/DEXIntegrator.sol";
import "../mocks/MockUSDC.sol";
import "../mocks/MockUniswapRouter.sol";
import "../mocks/MockUniswapFactory.sol";

contract DeployTest is Test {
    TokenFactory public tokenFactory;
    PricingCurve public pricingCurve;
    DEXIntegrator public dexIntegrator;
    CrowdfundingFactory public crowdfundingFactory;
    MockUSDC public usdc;
    MockUniswapRouter public uniswapRouter;
    MockUniswapFactory public uniswapFactory;

    address public deployer = address(0x1);
    address public feeRecipient = address(0x2);

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy mock contracts
        usdc = new MockUSDC();
        uniswapFactory = new MockUniswapFactory();
        uniswapRouter = new MockUniswapRouter();

        // Deploy core contracts in the same order as the deployment script
        tokenFactory = new TokenFactory();
        pricingCurve = new PricingCurve();
        dexIntegrator = new DEXIntegrator(address(uniswapRouter), address(uniswapFactory));

        crowdfundingFactory = new CrowdfundingFactory(
            address(tokenFactory), address(pricingCurve), address(dexIntegrator), address(usdc), feeRecipient, deployer
        );

        vm.stopPrank();
    }

    function testDeploymentAddresses() public view {
        // Verify all contracts were deployed successfully
        assertNotEq(address(tokenFactory), address(0), "TokenFactory not deployed");
        assertNotEq(address(pricingCurve), address(0), "PricingCurve not deployed");
        assertNotEq(address(dexIntegrator), address(0), "DEXIntegrator not deployed");
        assertNotEq(address(crowdfundingFactory), address(0), "CrowdfundingFactory not deployed");
    }

    function testCrowdfundingFactoryConfiguration() public view {
        // Verify CrowdfundingFactory is properly configured
        assertEq(address(crowdfundingFactory.tokenFactory()), address(tokenFactory), "TokenFactory address mismatch");
        assertEq(address(crowdfundingFactory.pricingCurve()), address(pricingCurve), "PricingCurve address mismatch");
        assertEq(address(crowdfundingFactory.dexIntegrator()), address(dexIntegrator), "DEXIntegrator address mismatch");
        assertEq(crowdfundingFactory.usdcToken(), address(usdc), "USDC token address mismatch");
        assertEq(crowdfundingFactory.feeRecipient(), feeRecipient, "Fee recipient mismatch");
        assertEq(crowdfundingFactory.owner(), deployer, "Owner mismatch");
    }

    function testDEXIntegratorConfiguration() public view {
        // Verify DEXIntegrator is properly configured
        assertEq(address(dexIntegrator.uniswapRouter()), address(uniswapRouter), "Uniswap router mismatch");
        assertEq(address(dexIntegrator.uniswapFactory()), address(uniswapFactory), "Uniswap factory mismatch");
    }

    function testBasicFunctionality() public {
        vm.startPrank(deployer);

        // Test creating a campaign to ensure deployment is functional
        uint256 campaignId = crowdfundingFactory.createCampaign(
            "ipfs://test-metadata",
            1000e6, // 1000 USDC funding goal
            30 days,
            25, // 25% creator reserve
            20, // 20% liquidity
            "Test Token",
            "TEST"
        );

        assertEq(campaignId, 0, "First campaign should have ID 0");
        assertEq(crowdfundingFactory.getCampaignCount(), 1, "Campaign count should be 1");

        vm.stopPrank();
    }
}
