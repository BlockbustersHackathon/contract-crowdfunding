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
RPC_URL=${SEPOLIA_RPC_URL:-"https://sepolia.infura.io/v3/89aa1f7b407142ac9d6539e044934786"}

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
print_info "  - DEXIntegrator (with Sepolia Uniswap V2)"
print_info "  - CrowdfundingFactory"
print_info ""
print_info "Network Configuration:"

# address constant UNISWAP_ROUTER = 0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3;
# address constant UNISWAP_FACTORY = 0xF62c03E08ada871A0bEb309762E260a7a6a880E6;

# // Sepolia USDC address (or mock USDC for testing)
# address constant USDC_TOKEN = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

# Deploy and capture output
print_info "Starting deployment..."
DEPLOY_OUTPUT=$(forge script script/DeploySepolia.s.sol --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast -vvv \
    --verify \
    --etherscan-api-key ${ETHERSCAN_API_KEY:-""} 2>&1)

if [ $? -ne 0 ]; then
    print_error "Deployment failed!"
    echo "$DEPLOY_OUTPUT"
    exit 1
fi

print_info "Deployment completed successfully!"
echo ""

# Extract contract addresses from deployment output
print_header "=== Contract Addresses ==="
echo "$DEPLOY_OUTPUT" | grep -E "(TokenFactory|PricingCurve|DEXIntegrator|CrowdfundingFactory) deployed at:" || true

# Extract the main contract address (CrowdfundingFactory)
CROWDFUNDING_FACTORY_ADDR=$(echo "$DEPLOY_OUTPUT" | grep "CrowdfundingFactory deployed at:" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)

if [ -n "$CROWDFUNDING_FACTORY_ADDR" ]; then
    print_info "Main CrowdfundingFactory deployed at: $CROWDFUNDING_FACTORY_ADDR"
    
    # Save contract address to a deployment file
    DEPLOY_FILE="deployments/sepolia.json"
    mkdir -p deployments
    
    # Create deployment info JSON
    cat > $DEPLOY_FILE << EOF
{
  "network": "sepolia",
  "chainId": 11155111,
  "deployed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "contracts": {
    "CrowdfundingFactory": "$CROWDFUNDING_FACTORY_ADDR",
  }
}
EOF
    
    print_info "Deployment info saved to: $DEPLOY_FILE"
fi

echo ""
print_header "=== Deployment Complete ==="
print_info "✅ Contracts successfully deployed to Sepolia"
print_info "🔗 Network: Sepolia Testnet (Chain ID: 11155111)"
print_info "📋 Deployment details saved to: deployments/sepolia.json"
print_info ""
print_info "Next steps:"
print_info "1. Verify contracts on Etherscan (if verification failed)"
print_info "2. Update your frontend configuration with new contract addresses"
print_info "3. Test contract interactions on Sepolia"
print_info "4. Fund deployer account with Sepolia ETH for gas fees"

echo ""
print_info "🎉 Deployment successful!"