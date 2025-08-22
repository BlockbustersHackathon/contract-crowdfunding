#!/bin/bash

# Crowdfunding Contract Local Deployment Script for Anvil
# This script deploys the crowdfunding contracts with mock Uniswap contracts

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Load configuration from config.json
if [ ! -f "config.json" ]; then
    print_error "config.json file not found!"
    print_info "Please create config.json with PRIVATE_KEY"
    print_info "See config.example.json for reference"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed. Please install jq first:"
    print_info "  macOS: brew install jq"
    print_info "  Ubuntu: sudo apt-get install jq"
    exit 1
fi

export PRIVATE_KEY=$(jq -r '.PRIVATE_KEY' config.json)
export RPC_URL="http://localhost:8545"

print_info "Using RPC_URL: $RPC_URL"

if [ "$PRIVATE_KEY" = "null" ] || [ -z "$PRIVATE_KEY" ]; then
    print_error "PRIVATE_KEY not found in config.json"
    exit 1
fi

# Check if Anvil is already running
if pgrep -f "anvil" > /dev/null; then
    print_warning "Anvil is already running. Please stop it first with: pkill -f anvil"
    exit 1
fi

# Check if forge is installed
if ! command -v forge &> /dev/null; then
    print_error "Foundry (forge) is required but not installed."
    print_info "Please install Foundry: https://getfoundry.sh/"
    exit 1
fi

# Start Anvil in the background
print_info "Starting Anvil local node..."
anvil --host 0.0.0.0 --port 8545 &
ANVIL_PID=$!

# Function to cleanup Anvil on script exit
cleanup() {
    print_info "Stopping Anvil..."
    kill $ANVIL_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for Anvil to be ready
print_info "Waiting for Anvil to initialize..."
max_attempts=30
attempt=0

until curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    $RPC_URL > /dev/null 2>&1; do
    
    attempt=$((attempt + 1))
    if [ $attempt -gt $max_attempts ]; then
        print_error "Anvil failed to start within 30 seconds"
        exit 1
    fi
    
    sleep 1
    echo -n "."
done

echo ""
print_info "Anvil is ready!"

# Build contracts first
print_info "Building contracts..."
if ! forge build; then
    print_error "Failed to build contracts"
    exit 1
fi

print_info "Running tests to ensure contracts are working..."
if ! forge test; then
    print_warning "Some tests failed, but continuing with deployment..."
fi

# Deploy contracts using the local deployment script
print_info "Deploying contracts with mock Uniswap..."
print_info "This will deploy:"
print_info "  - MockUSDC (test token)"
print_info "  - MockUniswapFactory"
print_info "  - MockUniswapRouter" 
print_info "  - TokenFactory"
print_info "  - PricingCurve"
print_info "  - DEXIntegrator"
print_info "  - CrowdfundingFactory"

# Deploy and capture output
DEPLOY_OUTPUT=$(forge script script/DeployLocal.s.sol --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast -vvv 2>&1)

if [ $? -ne 0 ]; then
    print_error "Deployment failed!"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

print_info "Deployment completed successfully!"
echo ""

# Extract contract addresses from deployment output
print_info "=== Contract Addresses ==="
echo "$DEPLOY_OUTPUT" | grep -E "(MockUSDC|MockUniswapFactory|MockUniswapRouter|TokenFactory|PricingCurve|DEXIntegrator|CrowdfundingFactory) deployed at:" || true

# Extract the main contract address (CrowdfundingFactory)
CROWDFUNDING_FACTORY_ADDR=$(echo "$DEPLOY_OUTPUT" | grep "CrowdfundingFactory deployed at:" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)

if [ -n "$CROWDFUNDING_FACTORY_ADDR" ]; then
    print_info "Main CrowdfundingFactory deployed at: $CROWDFUNDING_FACTORY_ADDR"
    
    # Update config.json with contract address
    jq --arg addr "$CROWDFUNDING_FACTORY_ADDR" '.CROWDFUNDING_FACTORY_ADDRESS = $addr' config.json > config.tmp && mv config.tmp config.json
    print_info "Contract address saved to config.json"
fi

echo ""
print_info "=== Quick Start Guide ==="
print_info "1. Your contracts are now deployed on local Anvil"
print_info "2. Anvil is running on http://localhost:8545"
print_info "3. You can interact with contracts using:"
print_info "   - Foundry cast commands"
print_info "   - Your frontend application"
print_info "   - Hardhat console"
print_info "4. Default Anvil accounts have 10,000 ETH each"
print_info "5. MockUSDC tokens can be minted to any address for testing"

echo ""
print_info "Anvil is running in the background. Press Ctrl+C to stop."

# Keep the script running until interrupted
wait $ANVIL_PID