# Multi-Account Testing Implementation

## Overview

The Python test suite has been updated to use separate Creator and Donor accounts for more realistic testing scenarios. This better simulates real-world usage where campaigns are created by one party and funded by different parties.

## Changes Made

### 1. Configuration Updates

#### Environment Variables (`.env.example`)
- **Before**: Single `PRIVATE_KEY` for all operations
- **After**: Separate `CREATOR_PRIVATE_KEY` and `DONOR_PRIVATE_KEY`

```bash
# Before
PRIVATE_KEY=0x1234...

# After  
CREATOR_PRIVATE_KEY=0x1234...  # Creates campaigns, withdraws funds
DONOR_PRIVATE_KEY=0xabcd...    # Makes contributions, claims tokens
```

#### TestConfig Class (`sepolia_test.py`)
- **Before**: Single `private_key` field
- **After**: Separate `creator_private_key` and `donor_private_key` fields

### 2. Account Separation

#### CastInteractor Instances
- **Before**: Single `self.cast` for all operations
- **After**: 
  - `self.creator_cast` - Campaign management operations
  - `self.donor_cast` - Contribution and token operations
  - `self.uniswap` - Uses donor_cast (they hold the tokens)

#### Operation Mapping
| Operation | Account Used | Rationale |
|-----------|--------------|-----------|
| `create_campaign()` | Creator | Only creator can create campaigns |
| `contribute_to_campaign()` | Donor | Donor makes the contributions |
| `claim_tokens()` | Donor | Donor claims tokens after contributing |
| `withdraw_funds()` | Creator | Only creator can withdraw campaign funds |
| `create_liquidity_pool()` | Creator | Anyone can call, but using creator for consistency |
| `refund_contribution()` | Donor | Donor requests refund of their contribution |
| `token_swap()` | Donor | Donor has the tokens to swap |

### 3. Validation Updates

#### Pre-flight Checks (`run_tests.sh`)
- **Before**: Single account balance validation
- **After**: Dual account validation
  - Creator ETH balance (for gas)
  - Donor ETH balance (for gas) 
  - Donor USDC balance (for contributions)

#### Test Output
- **Before**: Single test account address
- **After**: Both creator and donor addresses shown in logs

### 4. Realistic Test Scenarios

#### Scenario 1: Success with 0% Liquidity
1. **Creator** creates campaign with 0% liquidity
2. **Donor** contributes full funding goal (1000 USDC)
3. Campaign succeeds automatically
4. **Donor** claims tokens
5. **Creator** withdraws funds

#### Scenario 2: Success with 50% Liquidity + Uniswap
1. **Creator** creates campaign with 50% liquidity  
2. **Donor** contributes full funding goal
3. Campaign succeeds
4. **Creator** creates liquidity pool (launches on Uniswap)
5. **Donor** claims remaining tokens
6. **Donor** swaps some tokens for USDC on Uniswap

#### Scenario 3: Failure + Refund
1. **Creator** creates campaign
2. **Donor** contributes partial amount (50% of goal)
3. Campaign fails due to timeout
4. **Donor** requests and receives full refund

## Benefits of Multi-Account Testing

### 1. **Realistic Simulation**
- Mirrors real-world usage where different parties interact with the contract
- Tests proper access controls and permissions
- Validates that only authorized accounts can perform specific operations

### 2. **Better Access Control Testing** 
- Ensures `onlyCreator` modifiers work correctly
- Validates that donors can only perform donor operations
- Tests that unauthorized operations fail appropriately

### 3. **Improved Token Flow Validation**
- Confirms tokens are minted to the correct account (donor)
- Verifies funds flow to the correct account (creator)  
- Tests token swaps work with the account that actually holds tokens

### 4. **Enhanced Security Testing**
- Prevents accidental bypassing of access controls
- Tests that refunds go to the original contributor
- Validates that withdrawals only work for campaign creators

## Required Setup

### Account Requirements
1. **Creator Account**:
   - Sepolia ETH for gas fees (~0.05 ETH minimum)
   - Creates campaigns and withdraws funds

2. **Donor Account**:
   - Sepolia ETH for gas fees (~0.05 ETH minimum)
   - Sepolia USDC for contributions (2000+ USDC recommended)
   - Receives tokens and can swap them

### Environment Configuration
```bash
# Sepolia RPC endpoint
RPC_URL=https://sepolia.infura.io/v3/YOUR_PROJECT_ID

# Account private keys (TEST ACCOUNTS ONLY!)
CREATOR_PRIVATE_KEY=0x...
DONOR_PRIVATE_KEY=0x...

# Updated contract addresses
CROWDFUNDING_FACTORY_ADDRESS=0x3B2f066009d29521cd226221A86C69eD70D56599
USDC_TOKEN_ADDRESS=0x408A35083AbE22eC07a0cAB3caB0DA8f57b767Fb
```

## Migration Guide

### For Existing Users
1. **Update Environment File**:
   ```bash
   # Copy your existing PRIVATE_KEY to CREATOR_PRIVATE_KEY
   CREATOR_PRIVATE_KEY=0xYOUR_EXISTING_KEY
   
   # Add a new test account for DONOR_PRIVATE_KEY
   DONOR_PRIVATE_KEY=0xNEW_DONOR_KEY
   ```

2. **Fund Both Accounts**:
   - Creator: Sepolia ETH for gas
   - Donor: Sepolia ETH + USDC for contributions

3. **Update Contract Addresses**:
   - Use the new factory address: `0x3B2f066009d29521cd226221A86C69eD70D56599`
   - Use the new USDC address: `0x408A35083AbE22eC07a0cAB3caB0DA8f57b767Fb`

### Running Tests
No changes to the execution process:
```bash
./run_tests.sh
```

The script now validates both accounts automatically and provides detailed balance information for each account.

## Security Notes

⚠️ **Critical Reminders**:
- **Never use mainnet private keys** for testing
- Both accounts should only hold small amounts of testnet tokens
- Use completely separate test accounts from your main accounts
- Keep private keys secure and never commit them to version control
- The multi-account setup provides better security validation but requires careful key management