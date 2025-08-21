// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../test/mocks/MockUSDC.sol";

contract DeployMockUSDCSepoliaScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Mock USDC
        MockUSDC mockUSDC = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUSDC));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== MockUSDC Sepolia Deployment Summary ===");
        console.log("Deployer:", deployer);
        console.log("Contract Name: USD Coin");
        console.log("Symbol: USDC");
        console.log("Decimals: 6");
        console.log("Initial Supply: 1,000,000,000 USDC");
        console.log("Contract Address:", address(mockUSDC));
        console.log("Owner:", deployer);
        console.log("\nContract can be verified on Etherscan:");
    }
}