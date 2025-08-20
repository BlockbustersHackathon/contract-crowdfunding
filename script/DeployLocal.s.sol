// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CrowdfundingFactory.sol";
import "../src/TokenFactory.sol";
import "../src/PricingCurve.sol";
import "../src/DEXIntegrator.sol";
import "../test/mocks/MockUSDC.sol";
import "../test/mocks/MockUniswapRouter.sol";
import "../test/mocks/MockUniswapFactory.sol";

contract DeployLocalScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Mock Contracts First
        console.log("=== Deploying Mock Contracts ===");

        // Deploy Mock USDC
        MockUSDC mockUSDC = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUSDC));

        // Deploy Mock Uniswap Factory
        MockUniswapFactory mockFactory = new MockUniswapFactory();
        console.log("MockUniswapFactory deployed at:", address(mockFactory));

        // Deploy Mock Uniswap Router
        MockUniswapRouter mockRouter = new MockUniswapRouter();
        console.log("MockUniswapRouter deployed at:", address(mockRouter));

        console.log("\n=== Deploying Core Contracts ===");

        // Deploy TokenFactory
        TokenFactory tokenFactory = new TokenFactory();
        console.log("TokenFactory deployed at:", address(tokenFactory));

        // Deploy PricingCurve
        PricingCurve pricingCurve = new PricingCurve();
        console.log("PricingCurve deployed at:", address(pricingCurve));

        // Deploy DEXIntegrator with mock addresses
        DEXIntegrator dexIntegrator = new DEXIntegrator(address(mockRouter), address(mockFactory));
        console.log("DEXIntegrator deployed at:", address(dexIntegrator));

        // Deploy CrowdfundingFactory
        CrowdfundingFactory crowdfundingFactory = new CrowdfundingFactory(
            address(tokenFactory),
            address(pricingCurve),
            address(dexIntegrator),
            address(mockUSDC),
            deployer // owner
        );
        console.log("CrowdfundingFactory deployed at:", address(crowdfundingFactory));

        vm.stopBroadcast();

        // Log all deployed addresses for easy reference
        console.log("\n=== Deployment Summary ===");
        console.log("Deployer:", deployer);
        console.log("MockUSDC:", address(mockUSDC));
        console.log("MockUniswapFactory:", address(mockFactory));
        console.log("MockUniswapRouter:", address(mockRouter));
        console.log("TokenFactory:", address(tokenFactory));
        console.log("PricingCurve:", address(pricingCurve));
        console.log("DEXIntegrator:", address(dexIntegrator));
        console.log("CrowdfundingFactory:", address(crowdfundingFactory));
    }
}
