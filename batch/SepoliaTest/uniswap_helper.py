#!/usr/bin/env python3
"""
Uniswap V2 Helper for Sepolia Testing

This module provides helper functions for testing token swaps on Uniswap V2
after a successful campaign launches its liquidity pool.
"""

import logging
from typing import Optional, Tuple
from cast_interactor import CastInteractor

logger = logging.getLogger(__name__)

class UniswapV2Helper:
    """Helper class for Uniswap V2 interactions on Sepolia"""
    
    # Sepolia Uniswap V2 addresses
    ROUTER_ADDRESS = "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3"
    FACTORY_ADDRESS = "0xF62c03E08ada871A0bEb309762E260a7a6a880E6"
    
    def __init__(self, cast: CastInteractor):
        self.cast = cast
    
    def get_pair_address(self, token_a: str, token_b: str) -> Optional[str]:
        """Get the pair address for two tokens"""
        result = self.cast.run_cast_command([
            "call", self.FACTORY_ADDRESS,
            "getPair(address,address)(address)", token_a, token_b
        ])
        
        if result and result != "0x0000000000000000000000000000000000000000":
            # Format address properly
            clean_addr = result[2:].zfill(40)
            return f"0x{clean_addr}"
        return None
    
    def get_reserves(self, pair_address: str) -> Optional[Tuple[int, int]]:
        """Get reserves from a Uniswap pair"""
        result = self.cast.run_cast_command([
            "call", pair_address,
            "getReserves()(uint112,uint112,uint32)"
        ])
        
        if not result:
            return None
        
        try:
            # Parse the tuple result - this is simplified
            # In production, you'd want more robust tuple parsing
            parts = result.strip("()").split(",")
            if len(parts) >= 2:
                reserve0 = int(parts[0].strip(), 16)
                reserve1 = int(parts[1].strip(), 16)
                return reserve0, reserve1
        except Exception as e:
            logger.error(f"Error parsing reserves: {e}")
        
        return None
    
    def get_amount_out(self, amount_in: int, reserve_in: int, reserve_out: int) -> int:
        """Calculate output amount for a swap (simplified Uniswap formula)"""
        if reserve_in == 0 or reserve_out == 0:
            return 0
        
        # Uniswap V2 formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
        amount_in_with_fee = amount_in * 997
        numerator = amount_in_with_fee * reserve_out
        denominator = reserve_in * 1000 + amount_in_with_fee
        
        return numerator // denominator if denominator > 0 else 0
    
    def swap_tokens_for_usdc(self, token_address: str, usdc_address: str, 
                           token_amount: int, min_usdc_out: int = 0) -> bool:
        """Swap campaign tokens for USDC on Uniswap V2"""
        logger.info(f"Swapping {token_amount} tokens for USDC")
        
        # First approve router to spend tokens
        if not self.cast.approve_token(token_address, self.ROUTER_ADDRESS, token_amount):
            logger.error("Failed to approve token spending for router")
            return False
        
        # Get current account address
        account_result = self.cast.run_cast_command([
            "wallet", "address", self.cast.private_key
        ])
        
        if not account_result:
            logger.error("Failed to get account address")
            return False
        
        account_address = account_result.strip()
        
        # Calculate deadline (current time + 10 minutes)
        import time
        deadline = int(time.time()) + 600
        
        # Execute swap
        result = self.cast.run_cast_command([
            "send", self.ROUTER_ADDRESS,
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            str(token_amount),
            str(min_usdc_out),
            f"[{token_address},{usdc_address}]",  # Path
            account_address,  # Recipient
            str(deadline),
        ])
        
        if result:
            logger.info(f"Token swap successful: {result}")
            return True
        else:
            logger.error("Token swap failed")
            return False
    
    def add_liquidity(self, token_a: str, token_b: str, amount_a: int, 
                     amount_b: int, min_a: int = 0, min_b: int = 0) -> bool:
        """Add liquidity to a Uniswap V2 pair"""
        logger.info(f"Adding liquidity: {amount_a} tokenA + {amount_b} tokenB")
        
        # Approve both tokens
        if not self.cast.approve_token(token_a, self.ROUTER_ADDRESS, amount_a):
            return False
        
        if not self.cast.approve_token(token_b, self.ROUTER_ADDRESS, amount_b):
            return False
        
        # Get account address
        account_result = self.cast.run_cast_command([
            "wallet", "address", self.cast.private_key
        ])
        
        if not account_result:
            return False
        
        account_address = account_result.strip()
        
        # Calculate deadline
        import time
        deadline = int(time.time()) + 600
        
        # Add liquidity
        result = self.cast.run_cast_command([
            "send", self.ROUTER_ADDRESS,
            "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)",
            token_a, token_b,
            str(amount_a), str(amount_b),
            str(min_a), str(min_b),
            account_address,
            str(deadline),
        ])
        
        return result is not None
    
    def test_token_swap(self, campaign_token_address: str, usdc_address: str, 
                       swap_amount: int) -> bool:
        """Test swapping campaign tokens for USDC"""
        logger.info("Testing token swap functionality")
        
        try:
            # Check if pair exists
            pair_address = self.get_pair_address(campaign_token_address, usdc_address)
            if not pair_address:
                logger.error("No Uniswap pair found for campaign token")
                return False
            
            logger.info(f"Found Uniswap pair at: {pair_address}")
            
            # Get reserves to verify liquidity
            reserves = self.get_reserves(pair_address)
            if not reserves:
                logger.error("Could not get pair reserves")
                return False
            
            reserve0, reserve1 = reserves
            logger.info(f"Pair reserves: {reserve0}, {reserve1}")
            
            if reserve0 == 0 or reserve1 == 0:
                logger.error("Pair has no liquidity")
                return False
            
            # Determine which reserve is which token
            token0_result = self.cast.run_cast_command([
                "call", pair_address, "token0()(address)"
            ])
            
            if not token0_result:
                logger.error("Could not get token0 address")
                return False
            
            token0 = token0_result.lower()
            is_token0_campaign_token = campaign_token_address.lower() == token0
            
            if is_token0_campaign_token:
                token_reserve = reserve0
                usdc_reserve = reserve1
            else:
                token_reserve = reserve1
                usdc_reserve = reserve0
            
            # Calculate expected USDC output
            expected_usdc_out = self.get_amount_out(swap_amount, token_reserve, usdc_reserve)
            min_usdc_out = int(expected_usdc_out * 0.95)  # 5% slippage tolerance
            
            logger.info(f"Expected USDC out: {expected_usdc_out / 10**6:.6f} USDC")
            logger.info(f"Minimum USDC out: {min_usdc_out / 10**6:.6f} USDC")
            
            # Execute the swap
            return self.swap_tokens_for_usdc(
                campaign_token_address, 
                usdc_address, 
                swap_amount, 
                min_usdc_out
            )
            
        except Exception as e:
            logger.error(f"Token swap test failed: {e}")
            return False