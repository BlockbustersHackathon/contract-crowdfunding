# Sepolia Crowdfunding Contract Testing Guide

## Overview

This testing suite provides comprehensive integration tests for the crowdfunding contract deployed on Sepolia testnet. The tests are designed to validate all major functionality including campaign creation, contributions, token minting, liquidity pool creation, and token swapping.

## Files Structure

```
batch/SepoliaTest/
├── sepolia_test.py          # Main test suite
├── cast_interactor.py       # Cast command wrapper
├── uniswap_helper.py        # Uniswap V2 interaction helper
├── run_tests.sh             # Test runner script
├── requirements.txt         # Python dependencies
├── .env.example             # Environment configuration template
├── README.md                # Setup instructions
└── TESTING_GUIDE.md         # This file
```

## Test Scenarios

### Scenario 1: Success with 0% Liquidity
**Objective**: Test traditional crowdfunding model where all funds go to creator

**Steps**:
1. Create campaign with 0% liquidity allocation
2. Contribute full funding goal (1000 USDC) 
3. Wait for campaign duration to expire (2 minutes)
4. Verify campaign state transitions to "Succeeded"
5. Claim tokens as contributor (should receive proportional token allocation)
6. Withdraw funds as creator (should receive full USDC amount)

**Expected Results**:
- ✅ Campaign successfully created
- ✅ Contribution accepted and recorded
- ✅ Campaign succeeds when goal is reached
- ✅ Tokens minted and claimable by contributors
- ✅ Funds withdrawable by creator
- ✅ No liquidity pool created

### Scenario 2: Success with 50% Liquidity + Uniswap Launch
**Objective**: Test token launch model with liquidity pool creation

**Steps**:
1. Create campaign with 50% liquidity allocation
2. Contribute full funding goal (1000 USDC)
3. Wait for campaign to succeed
4. Create liquidity pool (launches on Uniswap V2)
5. Verify liquidity pool exists and has reserves
6. Claim remaining tokens as contributor
7. Test token swap functionality (swap tokens for USDC)

**Expected Results**:
- ✅ Campaign successfully created with liquidity parameter
- ✅ Contribution successful
- ✅ Liquidity pool creation successful
- ✅ Uniswap pair created with token/USDC liquidity
- ✅ Token swap functionality works
- ✅ Remaining funds sent to creator
- ✅ Creator receives reduced USDC amount (after liquidity allocation)

### Scenario 3: Campaign Failure + Refund
**Objective**: Test failure scenario and refund mechanism

**Steps**:
1. Create campaign with any liquidity setting
2. Contribute partial amount (50% of funding goal)
3. Wait for campaign duration to expire without reaching goal
4. Verify campaign state transitions to "Failed"
5. Request refund as contributor
6. Verify USDC is returned to contributor

**Expected Results**:
- ✅ Campaign created successfully
- ✅ Partial contribution accepted
- ✅ Campaign fails when deadline reached without goal
- ✅ Refund mechanism works correctly
- ✅ Contributor receives full USDC refund
- ✅ No tokens minted or funds withdrawn

## Configuration Parameters

### Campaign Settings
```python
funding_goal = 1000 * 10**6      # 1000 USDC (6 decimals)
campaign_duration = 120          # 2 minutes for quick testing  
min_contribution = 1 * 10**6     # 1 USDC minimum
creator_reserve = 25             # 25% fixed creator reserve
```

### Gas Limits
```python
campaign_creation = 3_000_000    # High limit for contract deployment
contribution = 300_000           # Standard ERC20 transfer + logic
token_claim = 200_000           # Token minting operation
liquidity_pool = 1_000_000      # Uniswap pair creation
refund = 200_000                # USDC transfer back
```

### Contract Addresses (Sepolia)
```
CrowdfundingFactory: 0x7a7a0c9E9D463ACC1Bbcc9b99609D93cc083d546
USDC Token:          0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
Uniswap V2 Router:   0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3
Uniswap V2 Factory:  0xF62c03E08ada871A0bEb309762E260a7a6a880E6
```

## Pre-Test Setup

### Account Requirements
1. **Sepolia ETH**: Minimum 0.1 ETH for gas fees
2. **Sepolia USDC**: Minimum 2000 USDC for testing contributions
3. **Private Key**: Test account private key (never use mainnet keys!)

### Environment Setup
```bash
# Copy environment template
cp .env.example .env

# Edit with your values
RPC_URL=https://sepolia.infura.io/v3/YOUR_PROJECT_ID
PRIVATE_KEY=0xYOUR_TEST_PRIVATE_KEY
CROWDFUNDING_FACTORY_ADDRESS=0x7a7a0c9E9D463ACC1Bbcc9b99609D93cc083d546
USDC_TOKEN_ADDRESS=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
```

## Running Tests

### Quick Start
```bash
# Run all tests with validation
./run_tests.sh
```

### Manual Execution
```bash
# Install dependencies
pip install -r requirements.txt

# Run tests
python sepolia_test.py
```

### Individual Scenario Testing
Modify the `run_all_tests()` method in `sepolia_test.py` to comment out scenarios you don't want to run.

## Expected Output

### Successful Test Run
```
2025-01-20 10:00:00,000 - INFO - Starting Sepolia Integration Tests
2025-01-20 10:00:00,000 - INFO - Factory Address: 0x7a7a0c9E9D463ACC1Bbcc9b99609D93cc083d546
2025-01-20 10:00:00,000 - INFO - USDC Address: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238

2025-01-20 10:00:00,000 - INFO - === TEST SCENARIO 1: Success with 0% liquidity ===
2025-01-20 10:00:05,000 - INFO - Creating campaign: Test Campaign 1 with 0% liquidity
2025-01-20 10:00:15,000 - INFO - Campaign created - ID: 0, Address: 0x...
2025-01-20 10:00:20,000 - INFO - Contributing 1000.0 USDC to campaign...
2025-01-20 10:02:30,000 - INFO - Campaign succeeded!
2025-01-20 10:02:35,000 - INFO - Token claim successful
2025-01-20 10:02:40,000 - INFO - Fund withdrawal successful
2025-01-20 10:02:40,000 - INFO - ✅ Scenario 1 completed successfully!

[Similar output for scenarios 2 and 3...]

2025-01-20 10:10:00,000 - INFO - === TEST RESULTS SUMMARY ===
2025-01-20 10:10:00,000 - INFO - scenario_1_success_no_liquidity: ✅ PASSED
2025-01-20 10:10:00,000 - INFO - scenario_2_success_with_liquidity: ✅ PASSED
2025-01-20 10:10:00,000 - INFO - scenario_3_failure_and_refund: ✅ PASSED
2025-01-20 10:10:00,000 - INFO - Total: 3/3 scenarios passed
```

## Troubleshooting

### Common Issues

#### "Cast command failed"
- **Cause**: Foundry not installed or not in PATH
- **Solution**: Install Foundry: `curl -L https://foundry.sh | bash`

#### "Transaction reverted" 
- **Cause**: Insufficient gas, wrong parameters, or contract state issues
- **Solution**: Check gas limits, verify contract addresses, check campaign timing

#### "Insufficient balance"
- **Cause**: Not enough Sepolia ETH or USDC
- **Solution**: Get more testnet tokens from faucets

#### "No Uniswap pair found"
- **Cause**: Liquidity pool creation failed or indexing delay
- **Solution**: Wait longer after pool creation, verify DEX integrator setup

#### "Token swap failed"
- **Cause**: Insufficient liquidity, slippage too high, or approval issues
- **Solution**: Check pair reserves, increase slippage tolerance, verify approvals

### Debug Mode
Enable detailed logging:
```python
logging.basicConfig(level=logging.DEBUG, ...)
```

### Manual Verification
Verify results on Sepolia Etherscan:
- Check transaction receipts
- Verify contract interactions
- Confirm token balances
- Check Uniswap pair creation

## Advanced Testing

### Custom Parameters
Modify test parameters in `TestConfig`:
```python
funding_goal = 5000 * 10**6      # 5000 USDC goal
campaign_duration = 300          # 5 minutes
liquidity_percentage = 75        # 75% liquidity allocation
```

### Additional Test Cases
Consider adding tests for:
- Multiple contributors to same campaign
- Campaign deadline extension
- Edge cases (exactly reaching goal, maximum contributions)
- Gas optimization testing
- Error condition handling

### Load Testing
Run multiple campaigns simultaneously:
```python
# Create multiple campaigns in parallel
for i in range(5):
    create_campaign(f"Load Test {i}", 20)
```

## Security Considerations

⚠️ **Important Warnings**:
- Only use testnet tokens and accounts
- Never commit private keys to version control
- Use separate test accounts from your main accounts
- Verify all contract addresses before testing
- Monitor gas usage to avoid unexpected costs

## Maintenance

### Regular Updates
- Keep Foundry updated: `foundryup`
- Update Python dependencies: `pip install -r requirements.txt --upgrade`
- Verify contract addresses haven't changed
- Check for Sepolia network updates

### Adding New Tests
1. Add new test method to `SepoliaTestSuite`
2. Update `run_all_tests()` to include new test
3. Add documentation for new scenario
4. Test thoroughly before committing