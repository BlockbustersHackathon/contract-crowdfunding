# Sepolia Testnet Integration Tests

This directory contains Python scripts to test the crowdfunding contract deployed on Sepolia testnet.

## Overview

The test suite covers three main scenarios:

1. **Success with 0% liquidity**: Create campaign, reach funding goal, mint tokens to donors, send USDC to creator
2. **Success with 50% liquidity**: Create campaign, reach funding goal, launch liquidity pool on Uniswap, test token swaps
3. **Campaign failure**: Create campaign, fail to reach goal, test refund mechanism

## Prerequisites

### Software Requirements
- Python 3.8+
- Foundry (forge, cast) installed
- Git

### Testnet Requirements
- Two separate test accounts (never use mainnet keys!):
  - **Creator Account**: Sepolia ETH for gas fees (campaign creation, fund withdrawal)
  - **Donor Account**: Sepolia ETH for gas + Sepolia USDC for contributions

### Getting Testnet Tokens
- **Sepolia ETH**: Get from [Sepolia faucet](https://sepoliafaucet.com/)
- **Sepolia USDC**: The contract uses USDC at `0x408A35083AbE22eC07a0cAB3caB0DA8f57b767Fb`

## Setup

1. **Clone and navigate to the test directory**:
   ```bash
   cd batch/SepoliaTest
   ```

2. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Set up environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your values
   ```

4. **Required environment variables**:
   ```bash
   RPC_URL=https://sepolia.infura.io/v3/YOUR_PROJECT_ID
   CREATOR_PRIVATE_KEY=0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
   DONOR_PRIVATE_KEY=0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
   CROWDFUNDING_FACTORY_ADDRESS=0x3B2f066009d29521cd226221A86C69eD70D56599
   USDC_TOKEN_ADDRESS=0x408A35083AbE22eC07a0cAB3caB0DA8f57b767Fb
   ```

## Usage

### Run Full Test Suite
```bash
python sepolia_test.py
```

### Run Specific Scenario
You can modify the script to run individual scenarios by commenting out others in the `run_all_tests()` method.

## Test Scenarios Detail

### Scenario 1: Success with 0% Liquidity
- Creates a campaign with 0% liquidity allocation
- Contributes the full funding goal (1000 USDC)
- Waits 2 minutes for campaign to end
- Claims tokens as contributor
- Withdraws funds as creator

### Scenario 2: Success with 50% Liquidity
- Creates a campaign with 50% liquidity allocation  
- Contributes the full funding goal
- Waits for campaign to succeed
- Creates liquidity pool on Uniswap V2
- Claims remaining tokens as contributor

### Scenario 3: Failure and Refund
- Creates a campaign
- Contributes only 50% of funding goal
- Waits for campaign to fail (timeout)
- Requests refund of contributed USDC

## Configuration

### Test Parameters
- **Funding Goal**: 1000 USDC (modifiable in TestConfig)
- **Campaign Duration**: 2 minutes (modifiable for different test speeds)
- **Minimum Contribution**: 1 USDC

### Gas Limits
The script uses conservative gas limits:
- Campaign creation: 3,000,000 gas
- Contributions: 300,000 gas
- Token claims: 200,000 gas
- Liquidity pool: 1,000,000 gas

## Troubleshooting

### Common Issues

1. **"Cast command failed"**
   - Check that Foundry is installed: `forge --version`
   - Verify RPC URL is working: `cast block-number --rpc-url $RPC_URL`

2. **"Insufficient balance"**
   - Ensure test account has Sepolia ETH for gas
   - Verify USDC balance: `cast call $USDC_TOKEN_ADDRESS "balanceOf(address)" $YOUR_ADDRESS --rpc-url $RPC_URL`

3. **"Transaction reverted"**
   - Check campaign state and timing
   - Verify contract addresses are correct
   - Increase gas limits if needed

4. **"Campaign creation failed"**
   - Ensure factory contract address is correct
   - Check that creator reserve is exactly 25%
   - Verify campaign duration is within limits (0-180 days)

### Debugging

Enable debug logging by modifying the logging level:
```python
logging.basicConfig(level=logging.DEBUG, ...)
```

### Manual Testing

You can also interact with contracts manually using cast:

```bash
# Check campaign count
cast call $CROWDFUNDING_FACTORY_ADDRESS "getCampaignCount()" --rpc-url $RPC_URL

# Get campaign details
cast call $CROWDFUNDING_FACTORY_ADDRESS "getCampaign(uint256)" 0 --rpc-url $RPC_URL

# Check USDC balance
cast call $USDC_TOKEN_ADDRESS "balanceOf(address)" $YOUR_ADDRESS --rpc-url $RPC_URL
```

## Contract Addresses

### Sepolia Testnet
- **CrowdfundingFactory**: `0x3B2f066009d29521cd226221A86C69eD70D56599`
- **USDC Token**: `0x408A35083AbE22eC07a0cAB3caB0DA8f57b767Fb`
- **Uniswap V2 Router**: `0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3`
- **Uniswap V2 Factory**: `0xF62c03E08ada871A0bEb309762E260a7a6a880E6`

## Security Notes

⚠️ **Important Security Reminders**:
- Never use mainnet private keys for testing
- Test private keys should only hold small amounts of testnet tokens
- Never commit private keys to version control
- Use separate test accounts, not your main accounts

## Support

For issues specific to the testing framework, check:
1. Foundry installation: `forge --version`, `cast --version`
2. Python version: `python --version` (requires 3.8+)
3. Environment variables: Ensure all required vars are set
4. Network connectivity: Test RPC URL with simple cast commands

For contract-specific issues, refer to the main project documentation.