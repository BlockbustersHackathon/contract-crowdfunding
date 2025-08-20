// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CrowdfundingFactory.sol";
import "../src/TokenFactory.sol";
import "../src/PricingCurve.sol";
import "../src/DEXIntegrator.sol";

contract DeploySepoliaScript is Script {
    // Sepolia Uniswap V2 addresses
    address constant UNISWAP_ROUTER = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;
    address constant UNISWAP_FACTORY = 0xF62c03E08ada871A0bEb309762E260a7a6a880E6;
    
    // Sepolia USDC address (or mock USDC for testing)
    address constant USDC_TOKEN = 0x408A35083AbE22eC07a0cAB3caB0DA8f57b767Fb;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== Deploying to Sepolia ===");
        console.log("Deployer:", deployer);
        console.log("Uniswap Router:", UNISWAP_ROUTER);
        console.log("Uniswap Factory:", UNISWAP_FACTORY);
        console.log("USDC Token:", USDC_TOKEN);
        console.log("");

        // Deploy TokenFactory
        TokenFactory tokenFactory = new TokenFactory();
        console.log("TokenFactory deployed at:", address(tokenFactory));

        // Deploy PricingCurve
        PricingCurve pricingCurve = new PricingCurve();
        console.log("PricingCurve deployed at:", address(pricingCurve));

        // Deploy DEXIntegrator with Sepolia Uniswap addresses
        DEXIntegrator dexIntegrator = new DEXIntegrator(UNISWAP_ROUTER, UNISWAP_FACTORY);
        console.log("DEXIntegrator deployed at:", address(dexIntegrator));

        // Deploy CrowdfundingFactory
        CrowdfundingFactory crowdfundingFactory = new CrowdfundingFactory(
            address(tokenFactory),
            address(pricingCurve),
            address(dexIntegrator),
            USDC_TOKEN,
            deployer // owner
        );
        console.log("CrowdfundingFactory deployed at:", address(crowdfundingFactory));

        vm.stopBroadcast();

        // Log all deployed addresses for easy reference
        console.log("\n=== Sepolia Deployment Summary ===");
        console.log("Network: Sepolia");
        console.log("Deployer:", deployer);
        console.log("TokenFactory:", address(tokenFactory));
        console.log("PricingCurve:", address(pricingCurve));
        console.log("DEXIntegrator:", address(dexIntegrator));
        console.log("CrowdfundingFactory:", address(crowdfundingFactory));
        console.log("USDC Token:", USDC_TOKEN);
        console.log("Uniswap Router:", UNISWAP_ROUTER);
        console.log("Uniswap Factory:", UNISWAP_FACTORY);
    }
}