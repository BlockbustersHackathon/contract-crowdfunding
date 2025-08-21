#!/bin/bash

# MockUSDC Sepolia Deployment Script
# This script deploys only the MockUSDC contract to Sepolia testnet

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Check if PRIVATE_KEY is provided as environment variable
if [ -z "$PRIVATE_KEY" ]; then
    print_error "PRIVATE_KEY environment variable is required"
    print_info "Usage: PRIVATE_KEY=0x... ./deploy_mockusdc_sepolia.sh"
    print_info "Or: export PRIVATE_KEY=0x... && ./deploy_mockusdc_sepolia.sh"
    exit 1
fi

print_header "Deploying MockUSDC to Sepolia Testnet"
print_info "RPC URL: $RPC_URL"
print_info ""

# Verify private key format
if [[ ! $PRIVATE_KEY =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    print_warning "Private key should be 64 hex characters prefixed with 0x"
fi

# Check if forge is installed
if ! command -v forge &> /dev/null; then
    print_error "Foundry (forge) is required but not installed."
    print_info "Please install Foundry: https://getfoundry.sh/"
    exit 1
fi

# Build contracts first
print_info "Building contracts..."
if ! forge build; then
    print_error "Failed to build contracts"
    exit 1
fi

# Deploy MockUSDC using the Sepolia deployment script
print_header "Deploying MockUSDC to Sepolia"
print_info "This will deploy:"
print_info "  - MockUSDC (USD Coin test token)"
print_info ""

# Deploy and capture output
print_info "Starting MockUSDC deployment..."
forge script script/DeployMockUSDCSepolia.s.sol --rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast

print_info "MockUSDC deployment completed successfully!"
echo ""

echo ""
print_header "=== MockUSDC Deployment Complete ==="
print_info "✅ MockUSDC successfully deployed to Sepolia"
print_info "📋 Contract Address: $MOCKUSDC_ADDR"
print_info "💰 Token: USD Coin (USDC)"
print_info "🔢 Decimals: 6"
print_info "📊 Initial Supply: 1,000,000,000 USDC"
print_info ""
print_info "Next steps:"
print_info "1. Verify contract on Etherscan (if verification failed)"
print_info "2. Use this MockUSDC address in your crowdfunding contracts"
print_info "3. Test token transfers and approvals"
print_info "4. Fund test accounts with MockUSDC for testing"

echo ""
print_info "🎉 MockUSDC deployment successful!"