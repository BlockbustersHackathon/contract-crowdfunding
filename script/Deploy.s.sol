// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CrowdfundingFactory.sol";
import "../src/TokenFactory.sol";
import "../src/PricingCurve.sol";
import "../src/DEXIntegrator.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy TokenFactory
        TokenFactory tokenFactory = new TokenFactory();
        console.log("TokenFactory deployed at:", address(tokenFactory));

        // Deploy PricingCurve
        PricingCurve pricingCurve = new PricingCurve();
        console.log("PricingCurve deployed at:", address(pricingCurve));

        // Deploy DEXIntegrator
        // Note: Replace these addresses with actual Uniswap V2 Router and Factory addresses for your target network
        address uniswapRouter = vm.envAddress("UNISWAP_ROUTER");
        address uniswapFactory = vm.envAddress("UNISWAP_FACTORY");

        DEXIntegrator dexIntegrator = new DEXIntegrator(uniswapRouter, uniswapFactory);
        console.log("DEXIntegrator deployed at:", address(dexIntegrator));

        // USDC token address (replace with actual USDC address for your target network)
        address usdcToken = vm.envAddress("USDC_TOKEN");

        // Fee recipient (could be the deployer or a treasury address)
        address feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);

        // Deploy CrowdfundingFactory
        CrowdfundingFactory crowdfundingFactory = new CrowdfundingFactory(
            address(tokenFactory),
            address(pricingCurve),
            address(dexIntegrator),
            usdcToken,
            feeRecipient,
            deployer // owner
        );
        console.log("CrowdfundingFactory deployed at:", address(crowdfundingFactory));

        vm.stopBroadcast();

        // Log all deployed addresses for easy reference
        console.log("\n=== Deployment Summary ===");
        console.log("Deployer:", deployer);
        console.log("TokenFactory:", address(tokenFactory));
        console.log("PricingCurve:", address(pricingCurve));
        console.log("DEXIntegrator:", address(dexIntegrator));
        console.log("CrowdfundingFactory:", address(crowdfundingFactory));
        console.log("USDC Token:", usdcToken);
        console.log("Fee Recipient:", feeRecipient);
    }
}
