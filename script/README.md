# Deployment Guide

This directory contains the deployment script for the crowdfunding smart contracts.

## Prerequisites

1. Copy `.env.example` to `.env` and fill in the required values:
   ```bash
   cp .env.example .env
   ```

2. Make sure you have the following environment variables set in `.env`:
   - `PRIVATE_KEY`: Your private key (without 0x prefix)
   - `UNISWAP_ROUTER`: Uniswap V2 Router address for your target network
   - `UNISWAP_FACTORY`: Uniswap V2 Factory address for your target network
   - `USDC_TOKEN`: USDC token address for your target network
   - `FEE_RECIPIENT` (optional): Fee recipient address (defaults to deployer)
   - `RPC_URL`: RPC URL for your target network

## Network Addresses

### Base Mainnet
- USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- Uniswap V2 Router: Check Base documentation for current addresses
- Uniswap V2 Factory: Check Base documentation for current addresses

### Base Sepolia (Testnet)
- Check Base documentation for testnet addresses

## Deployment Commands

### Deploy to local fork
```bash
forge script script/Deploy.s.sol:DeployScript --fork-url $RPC_URL --broadcast
```

### Deploy to testnet
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL --broadcast --verify
```

### Deploy to mainnet
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL --broadcast --verify --legacy
```

## Deployment Order

The script deploys contracts in the following order:
1. `TokenFactory` - Creates campaign tokens
2. `PricingCurve` - Handles token allocation calculations
3. `DEXIntegrator` - Manages liquidity pool creation
4. `CrowdfundingFactory` - Main factory contract

## Verification

After deployment, the contract addresses will be displayed. You can verify the contracts are working by:

1. Checking the deployment addresses in the console output
2. Verifying contracts on the block explorer (if `--verify` flag was used)
3. Testing basic functionality through the factory contract

## Security Notes

- Always test on a testnet before mainnet deployment
- Ensure your private key is secure and never committed to version control
- Double-check all environment variables before deployment
- Consider using a hardware wallet or multi-sig for mainnet deployments