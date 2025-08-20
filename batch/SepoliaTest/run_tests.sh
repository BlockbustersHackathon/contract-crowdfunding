#!/bin/bash

# Sepolia Integration Test Runner
# This script sets up and runs the Python test suite

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "sepolia_test.py" ]; then
    print_error "sepolia_test.py not found. Please run from the SepoliaTest directory."
    exit 1
fi

# Check if .env file exists
if [ ! -f ".env" ]; then
    print_error ".env file not found. Please copy .env.example to .env and configure it."
    print_info "Run: cp .env.example .env"
    exit 1
fi

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    if ! command -v python &> /dev/null; then
        print_error "Python is required but not installed."
        exit 1
    else
        PYTHON_CMD=python
    fi
else
    PYTHON_CMD=python3
fi

# Check if Foundry is installed
if ! command -v cast &> /dev/null; then
    print_error "Foundry (cast) is required but not installed."
    print_info "Install from: https://getfoundry.sh/"
    exit 1
fi

# Check Python version
PYTHON_VERSION=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 8 ]); then
    print_error "Python 3.8+ is required. Current version: $PYTHON_VERSION"
    exit 1
fi

print_header "Sepolia Integration Tests"
print_info "Python version: $PYTHON_VERSION"
print_info "Cast version: $(cast --version)"

# Install dependencies if requirements.txt exists and packages aren't installed
if [ -f "requirements.txt" ]; then
    print_info "Checking Python dependencies..."
    if ! $PYTHON_CMD -c "import dotenv" &> /dev/null; then
        print_info "Installing Python dependencies with uv..."
        uv pip install -r requirements.txt
    fi
fi

# Load environment variables and validate
print_info "Validating environment configuration..."

source .env 2>/dev/null || true

if [ -z "$RPC_URL" ]; then
    print_error "RPC_URL not set in .env file"
    exit 1
fi

if [ -z "$CREATOR_PRIVATE_KEY" ]; then
    print_error "CREATOR_PRIVATE_KEY not set in .env file"
    exit 1
fi

if [ -z "$DONOR_PRIVATE_KEY" ]; then
    print_error "DONOR_PRIVATE_KEY not set in .env file"
    exit 1
fi

if [ -z "$CROWDFUNDING_FACTORY_ADDRESS" ]; then
    print_error "CROWDFUNDING_FACTORY_ADDRESS not set in .env file"
    exit 1
fi

if [ -z "$USDC_TOKEN_ADDRESS" ]; then
    print_error "USDC_TOKEN_ADDRESS not set in .env file"
    exit 1
fi

# Test RPC connectivity
print_info "Testing RPC connectivity..."
if ! cast block-number --rpc-url "$RPC_URL" &> /dev/null; then
    print_error "Cannot connect to RPC URL: $RPC_URL"
    print_info "Please check your RPC_URL in .env file"
    exit 1
fi

# Derive account addresses from private keys
CREATOR_ADDRESS=$(cast wallet address "$CREATOR_PRIVATE_KEY" 2>/dev/null || echo "")
if [ -z "$CREATOR_ADDRESS" ]; then
    print_error "Invalid CREATOR_PRIVATE_KEY format"
    exit 1
fi

DONOR_ADDRESS=$(cast wallet address "$DONOR_PRIVATE_KEY" 2>/dev/null || echo "")
if [ -z "$DONOR_ADDRESS" ]; then
    print_error "Invalid DONOR_PRIVATE_KEY format"
    exit 1
fi

print_info "Creator account: $CREATOR_ADDRESS"
print_info "Donor account: $DONOR_ADDRESS"

# Check ETH balances for gas
print_info "Checking account balances..."

# Creator ETH balance
CREATOR_ETH_BALANCE=$(cast balance "$CREATOR_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
CREATOR_ETH_DECIMAL=$(cast to-dec "$CREATOR_ETH_BALANCE" 2>/dev/null || echo "0")

if [ "$CREATOR_ETH_DECIMAL" -lt 50000000000000000 ]; then  # Less than 0.05 ETH
    print_warning "Low Creator ETH balance: $(cast from-wei $CREATOR_ETH_BALANCE) ETH"
    print_warning "Creator needs ETH for campaign creation and fund withdrawal"
fi

# Donor ETH balance
DONOR_ETH_BALANCE=$(cast balance "$DONOR_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
DONOR_ETH_DECIMAL=$(cast to-dec "$DONOR_ETH_BALANCE" 2>/dev/null || echo "0")

if [ "$DONOR_ETH_DECIMAL" -lt 50000000000000000 ]; then  # Less than 0.05 ETH
    print_warning "Low Donor ETH balance: $(cast from-wei $DONOR_ETH_BALANCE) ETH"
    print_warning "Donor needs ETH for contributions and token operations"
fi

# Check USDC balance (donor needs USDC for contributions)
DONOR_USDC_BALANCE=$(cast call "$USDC_TOKEN_ADDRESS" "balanceOf(address)" "$DONOR_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0")
DONOR_USDC_DECIMAL=$(cast to-dec "$DONOR_USDC_BALANCE" 2>/dev/null || echo "0")
DONOR_USDC_FORMATTED=$(echo "scale=6; $DONOR_USDC_DECIMAL / 1000000" | bc -l 2>/dev/null || echo "0")

print_info "Donor USDC balance: $DONOR_USDC_FORMATTED USDC"

if [ "$DONOR_USDC_DECIMAL" -lt 2000000000 ]; then  # Less than 2000 USDC
    print_warning "Low donor USDC balance. You may need more USDC for testing contributions"
fi

# Run the tests
print_header "Running Integration Tests"
print_info "This will create test campaigns with 2-minute durations"
print_info "Total test time: approximately 10-15 minutes"
print_info ""

# Run the Python test suite
if $PYTHON_CMD sepolia_test.py; then
    print_header "All tests completed successfully! ✅"
else
    print_error "Some tests failed ❌"
    exit 1
fi

print_info "Test run completed!"