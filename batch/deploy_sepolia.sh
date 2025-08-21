#!/bin/bash

# Crowdfunding Contract Sepolia Deployment Script
# This script deploys the crowdfunding contracts to Sepolia testnet

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
    print_info "Usage: PRIVATE_KEY=0x... ./deploy_sepolia.sh"
    print_info "Or: export PRIVATE_KEY=0x... && ./deploy_sepolia.sh"
    exit 1
fi

# Sepolia RPC URL (you can override this with SEPOLIA_RPC_URL env var)

print_header "Deploying to Sepolia Testnet"
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

print_info "Running tests to ensure contracts are working..."
if ! forge test; then
    print_warning "Some tests failed, but continuing with deployment..."
fi

# Deploy contracts using the Sepolia deployment script
print_header "Deploying contracts to Sepolia"
print_info "This will deploy:"
print_info "  - TokenFactory"
print_info "  - PricingCurve"
print_info "  - DEXIntegrator (with Sepolia Uniswap V3)"
print_info "  - CrowdfundingFactory"
print_info ""
print_info "Network Configuration:"


# Deploy and capture output
print_info "Starting deployment..."
forge script script/DeploySepolia.s.sol --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast -vvv \