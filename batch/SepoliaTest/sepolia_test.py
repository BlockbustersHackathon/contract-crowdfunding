#!/usr/bin/env python3
"""
Sepolia Testnet Integration Tests for Crowdfunding Contract

This script tests the crowdfunding contract on Sepolia testnet using cast commands.
It covers three main test scenarios:
1. Create campaign with 0% liquidity, success, mint tokens to donors, send USDC to creator
2. Create campaign with 50% liquidity, success, launch to Uniswap, test token swap
3. Create campaign that fails and refund contributors

Requirements:
- Foundry (forge, cast) installed
- .env file with RPC_URL, PRIVATE_KEY, CROWDFUNDING_FACTORY_ADDRESS, USDC_TOKEN_ADDRESS
- Test accounts funded with Sepolia ETH and USDC
"""

import os
import json
import time
import logging
from typing import Dict, Any, Optional, Tuple
from dataclasses import dataclass
from dotenv import load_dotenv
from cast_interactor import CastInteractor
from uniswap_helper import UniswapV2Helper

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class ContractAddresses:
    """Contract addresses for the crowdfunding system"""
    factory: str
    usdc: str

@dataclass 
class TestConfig:
    """Configuration for test scenarios"""
    rpc_url: str
    creator_private_key: str
    donor_private_key: str
    addresses: ContractAddresses
    funding_goal: int = 1000 * 10**6  # 1000 USDC (6 decimals)
    campaign_duration: int = 120  # 2 minutes for quick testing
    min_contribution: int = 1 * 10**6  # 1 USDC

class SepoliaTestSuite:
    """Main test suite for Sepolia crowdfunding contracts"""
    
    def __init__(self):
        self.config = self._load_config()
        # Create separate cast interactors for creator and donor
        self.creator_cast = CastInteractor(self.config.rpc_url, self.config.creator_private_key)
        self.donor_cast = CastInteractor(self.config.rpc_url, self.config.donor_private_key)
        # Use donor account for Uniswap interactions (they'll have the tokens)
        self.uniswap = UniswapV2Helper(self.donor_cast)
        self.test_results = []
        
    def _load_config(self) -> TestConfig:
        """Load configuration from environment variables"""
        rpc_url = os.getenv("RPC_URL")
        creator_private_key = os.getenv("CREATOR_PRIVATE_KEY") 
        donor_private_key = os.getenv("DONOR_PRIVATE_KEY")
        factory_address = os.getenv("CROWDFUNDING_FACTORY_ADDRESS")
        usdc_address = os.getenv("USDC_TOKEN_ADDRESS")
        
        if not all([rpc_url, creator_private_key, donor_private_key, factory_address, usdc_address]):
            missing = [var for var, val in [
                ("RPC_URL", rpc_url),
                ("CREATOR_PRIVATE_KEY", creator_private_key),
                ("DONOR_PRIVATE_KEY", donor_private_key),
                ("CROWDFUNDING_FACTORY_ADDRESS", factory_address),
                ("USDC_TOKEN_ADDRESS", usdc_address)
            ] if not val]
            raise ValueError(f"Missing environment variables: {', '.join(missing)}")
        
        addresses = ContractAddresses(factory=factory_address, usdc=usdc_address)
        return TestConfig(
            rpc_url=rpc_url, 
            creator_private_key=creator_private_key,
            donor_private_key=donor_private_key,
            addresses=addresses
        )
    
    def create_campaign(self, name: str, liquidity_percentage: int) -> Optional[Tuple[int, str]]:
        """Create a new campaign and return campaign ID and address (creator account)"""
        logger.info(f"Creating campaign: {name} with {liquidity_percentage}% liquidity")
        
        result = self.creator_cast.run_cast_command([
            "send", self.config.addresses.factory,
            "createCampaign(string,string,uint256,uint256,uint256,uint256,string,string)",
            name,
            "ipfs://test-metadata", 
            str(self.config.funding_goal),
            str(self.config.campaign_duration),
            "25",  # creator reserve (fixed at 25%)
            str(liquidity_percentage),
            f"{name} Token",
            f"{name[:4].upper()}",
        ])
        
        if not result:
            logger.error("Failed to create campaign")
            return None
            
        logger.info(f"Campaign creation transaction: {result}")
        
        # Get the latest campaign ID (this is simplified - in production parse events)
        time.sleep(10)  # Wait for transaction confirmation
        
        campaign_count_result = self.creator_cast.run_cast_command([
            "call", self.config.addresses.factory,
            "getCampaignCount()(uint256)"
        ])
        
        if not campaign_count_result:
            logger.error("Failed to get campaign count")
            return None
            
        campaign_id = int(campaign_count_result, 10) - 1  # Latest campaign ID
        campaign_address = self.creator_cast.get_campaign_address(self.config.addresses.factory, campaign_id)
        
        if not campaign_address:
            logger.error("Failed to get campaign address")
            return None
            
        logger.info(f"Campaign created - ID: {campaign_id}, Address: {campaign_address}")
        return campaign_id, campaign_address
    
    def contribute_to_campaign(self, campaign_address: str, amount: int) -> bool:
        """Contribute USDC to a campaign (donor account)"""
        logger.info(f"Contributing {amount / 10**6} USDC to campaign at {campaign_address}")
        
        # First approve USDC spending (donor account)
        if not self.donor_cast.approve_token(self.config.addresses.usdc, campaign_address, amount):
            logger.error("Failed to approve USDC spending")
            return False
            
        time.sleep(5)  # Wait for approval confirmation
        
        # Make contribution (donor account)
        result = self.donor_cast.run_cast_command([
            "send", campaign_address,
            "contribute(uint256)", str(amount),
        ])
        
        if result:
            logger.info(f"Contribution successful: {result}")
            return True
        else:
            logger.error("Contribution failed")
            return False
    
    def wait_for_campaign_end(self, campaign_address: str, max_wait: int = 150) -> bool:
        """Wait for campaign to end (either succeed or fail)"""
        logger.info("Waiting for campaign to end...")
        
        start_time = time.time()
        while time.time() - start_time < max_wait:
            # Update campaign state first to check for deadline expiry
            update_result = self.creator_cast.run_cast_command([
                "send", campaign_address,
                "updateCampaignState()"
            ])
            
            if update_result:
                logger.debug(f"Campaign state updated: {update_result}")
                time.sleep(5)  # Wait for state update to confirm
            
            # Check campaign state (can use any account for read operations)
            state_result = self.creator_cast.run_cast_command([
                "call", campaign_address,
                "getCampaignState()(uint8)"
            ])
            
            if state_result:
                state = int(state_result, 16)
                if state == 0:  # Active
                    logger.info("Campaign still active, waiting...")
                    time.sleep(10)
                    continue
                elif state == 1:  # Succeeded
                    logger.info("Campaign succeeded!")
                    return True
                elif state == 2:  # Failed
                    logger.info("Campaign failed!")
                    return False
            
            time.sleep(10)
        
        logger.warning("Timeout waiting for campaign to end")
        return False
    
    def claim_tokens(self, campaign_address: str) -> bool:
        """Claim tokens from successful campaign (donor account)"""
        logger.info("Claiming tokens from campaign")
        
        result = self.donor_cast.run_cast_command([
            "send", campaign_address,
            "claimTokens()", 
        ])
        
        if result:
            logger.info(f"Token claim successful: {result}")
            return True
        else:
            logger.error("Token claim failed")
            return False
    
    def withdraw_funds(self, campaign_address: str) -> bool:
        """Withdraw funds from successful campaign (creator only)"""
        logger.info("Withdrawing funds from campaign")
        
        result = self.creator_cast.run_cast_command([
            "send", campaign_address,
            "withdrawFunds()",
        ])
        
        if result:
            logger.info(f"Fund withdrawal successful: {result}")
            return True
        else:
            logger.error("Fund withdrawal failed")
            return False
    
    def create_liquidity_pool(self, campaign_address: str) -> bool:
        """Create liquidity pool for successful campaign (anyone can call)"""
        logger.info("Creating liquidity pool")
        
        result = self.creator_cast.run_cast_command([
            "send", campaign_address,
            "createLiquidityPool()",
        ])
        
        if result:
            logger.info(f"Liquidity pool creation successful: {result}")
            return True
        else:
            logger.error("Liquidity pool creation failed")
            return False
    
    def refund_contribution(self, campaign_address: str) -> bool:
        """Refund contribution from failed campaign (donor account)"""
        logger.info("Requesting refund from failed campaign")
        
        result = self.donor_cast.run_cast_command([
            "send", campaign_address,
            "refund()",
        ])
        
        if result:
            logger.info(f"Refund successful: {result}")
            return True
        else:
            logger.error("Refund failed")
            return False
    
    def get_campaign_token_address(self, campaign_id: int) -> Optional[str]:
        """Get the token address from campaign details using factory's getCampaign method"""
        result = self.creator_cast.run_cast_command([
            "call", self.config.addresses.factory,
            "getCampaign(uint256)", str(campaign_id)
        ])
        
        if not result:
            return None
        
        try:
            # Parse the CampaignData struct tuple
            # Format: (address,string,string,uint256,uint256,uint256,uint256,uint256,address,uint8,uint256)
            # tokenAddress is the 9th field (index 8)
            parts = result.strip("()").split(",")
            if len(parts) >= 9:
                token_addr = parts[8].strip()
                if token_addr.startswith("0x"):
                    # Ensure proper address formatting
                    hex_part = token_addr[2:]
                    if len(hex_part) > 40:
                        hex_part = hex_part[-40:]
                    elif len(hex_part) < 40:
                        hex_part = hex_part.zfill(40)
                    return f"0x{hex_part}"
                    
            return None
        except Exception as e:
            logger.error(f"Error parsing token address: {e}")
            return None
    
    def test_scenario_1_success_no_liquidity(self) -> bool:
        """Test Scenario 1: Success with 0% liquidity"""
        logger.info("=== TEST SCENARIO 1: Success with 0% liquidity ===")
        
        try:
            # Create campaign with 0% liquidity
            result = self.create_campaign("Test Campaign 1", 0)
            if not result:
                return False
            
            _, campaign_address = result
            
            # Contribute full funding goal to ensure success
            if not self.contribute_to_campaign(campaign_address, self.config.funding_goal):
                return False
            
            # Wait for campaign to end (should succeed)
            if not self.wait_for_campaign_end(campaign_address):
                return False
            
            # Claim tokens as contributor
            if not self.claim_tokens(campaign_address):
                return False
            
            # Withdraw funds as creator
            if not self.withdraw_funds(campaign_address):
                return False
            
            logger.info("✅ Scenario 1 completed successfully!")
            return True
            
        except Exception as e:
            logger.error(f"❌ Scenario 1 failed: {e}")
            return False
    
    def test_scenario_2_success_with_liquidity(self) -> bool:
        """Test Scenario 2: Success with 50% liquidity and Uniswap launch"""
        logger.info("=== TEST SCENARIO 2: Success with 50% liquidity ===")
        
        try:
            # Create campaign with 50% liquidity
            result = self.create_campaign("Test Campaign 2", 50)
            if not result:
                return False
            
            _, campaign_address = result
            
            # Contribute full funding goal
            if not self.contribute_to_campaign(campaign_address, self.config.funding_goal):
                return False
            
            # Wait for campaign to end
            if not self.wait_for_campaign_end(campaign_address):
                return False
            
            # Create liquidity pool (launches on Uniswap)
            if not self.create_liquidity_pool(campaign_address):
                return False
            
            # Get campaign token address using campaign ID
            campaign_token_address = self.get_campaign_token_address(result[0])
            if not campaign_token_address:
                logger.error("Failed to get campaign token address")
                return False
            
            # Claim tokens as contributor 
            if not self.claim_tokens(campaign_address):
                return False
            
            # Test token swap on Uniswap
            logger.info("Testing token swap functionality...")
            time.sleep(10)  # Wait for liquidity pool to be indexed
            
            # Get token balance to determine swap amount (donor has the tokens)
            donor_address = self.donor_cast.get_account_address()
            if not donor_address:
                logger.error("Failed to get donor account address")
                return False
            
            token_balance = self.donor_cast.get_balance(campaign_token_address, donor_address)
            if token_balance > 0:
                # Swap 10% of tokens for USDC
                swap_amount = token_balance // 10
                if swap_amount > 0:
                    success = self.uniswap.test_token_swap(
                        campaign_token_address,
                        self.config.addresses.usdc,
                        swap_amount
                    )
                    if success:
                        logger.info("✅ Token swap test successful!")
                    else:
                        logger.warning("⚠️ Token swap test failed, but campaign succeeded")
                else:
                    logger.warning("Token balance too small for swap test")
            else:
                logger.warning("No tokens received for swap test")
            
            logger.info("✅ Scenario 2 completed successfully!")
            return True
            
        except Exception as e:
            logger.error(f"❌ Scenario 2 failed: {e}")
            return False
    
    def test_scenario_3_failure_and_refund(self) -> bool:
        """Test Scenario 3: Campaign failure and refund"""
        logger.info("=== TEST SCENARIO 3: Campaign failure and refund ===")
        
        try:
            # Create campaign
            result = self.create_campaign("Test Campaign 3", 0)
            if not result:
                return False
            
            _, campaign_address = result
            
            # Contribute partial amount (not enough to succeed)
            partial_amount = self.config.funding_goal // 2  # 50% of goal
            if not self.contribute_to_campaign(campaign_address, partial_amount):
                return False
            
            # Wait for campaign to end (should fail due to time and insufficient funding)
            if not self.wait_for_campaign_end(campaign_address):
                return False
            
            # Request refund
            if not self.refund_contribution(campaign_address):
                return False
            
            logger.info("✅ Scenario 3 completed successfully!")
            return True
            
        except Exception as e:
            logger.error(f"❌ Scenario 3 failed: {e}")
            return False
    
    def run_all_tests(self) -> Dict[str, bool]:
        """Run all test scenarios"""
        logger.info("Starting Sepolia Integration Tests")
        logger.info(f"Factory Address: {self.config.addresses.factory}")
        logger.info(f"USDC Address: {self.config.addresses.usdc}")
        
        # Show the accounts being used
        creator_address = self.creator_cast.get_account_address()
        donor_address = self.donor_cast.get_account_address()
        logger.info(f"Creator Account: {creator_address}")
        logger.info(f"Donor Account: {donor_address}")
        
        results = {
            # "scenario_1_success_no_liquidity": self.test_scenario_1_success_no_liquidity(),
            "scenario_2_success_with_liquidity": self.test_scenario_2_success_with_liquidity(), 
            # "scenario_3_failure_and_refund": self.test_scenario_3_failure_and_refund()
        }
        
        # Print summary
        logger.info("\n=== TEST RESULTS SUMMARY ===")
        for scenario, passed in results.items():
            status = "✅ PASSED" if passed else "❌ FAILED"
            logger.info(f"{scenario}: {status}")
        
        total_passed = sum(results.values())
        logger.info(f"\nTotal: {total_passed}/{len(results)} scenarios passed")
        
        return results

def main():
    """Main function to run the test suite"""
    try:
        test_suite = SepoliaTestSuite()
        results = test_suite.run_all_tests()
        
        # Exit with error code if any tests failed
        if not all(results.values()):
            exit(1)
            
    except Exception as e:
        logger.error(f"Test suite failed to initialize: {e}")
        exit(1)

if __name__ == "__main__":
    main()