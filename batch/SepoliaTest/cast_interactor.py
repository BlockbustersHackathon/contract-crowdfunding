#!/usr/bin/env python3
"""
Cast Interactor Module

This module provides a wrapper class for interacting with Ethereum contracts
using Foundry's cast command-line tool.
"""

import subprocess
import logging
from typing import Optional

logger = logging.getLogger(__name__)

class CastInteractor:
    """Wrapper class for interacting with contracts using cast"""
    
    def __init__(self, rpc_url: str, private_key: str):
        self.rpc_url = rpc_url
        self.private_key = private_key
        
    def run_cast_command(self, command: list, decode_output: bool = True) -> Optional[str]:
        """Execute a cast command and return the result"""
        import inspect
        frame = inspect.currentframe()
        caller_frame = frame.f_back
        filename = caller_frame.f_code.co_filename.split('/')[-1]
        line_number = caller_frame.f_lineno
        
        full_command = ["cast"] + command + ["--rpc-url", self.rpc_url]
        
        # Add private key for transactions
        if any(cmd in command for cmd in ["send", "call"]):
            if "send" in command:
                full_command.extend(["--private-key", self.private_key])
        
        try:
            logger.debug(f"[{filename}:{line_number}] Executing: {' '.join(full_command[:3])} ...")  # Don't log private key
            result = subprocess.run(full_command, capture_output=True, text=True, timeout=60)
            
            if result.returncode != 0:
                logger.error(f"[{filename}:{line_number}] Cast command failed: {result.stderr}")
                return None
                
            output = result.stdout.strip()
            logger.debug(f"[{filename}:{line_number}] Cast result: {output}")
            return output
            
        except subprocess.TimeoutExpired:
            logger.error(f"[{filename}:{line_number}] Cast command timed out")
            return None
        except Exception as e:
            logger.error(f"[{filename}:{line_number}] Error executing cast command: {e}")
            return None
    
    def get_balance(self, token_address: str, account: str) -> int:
        """Get ERC20 token balance"""
        result = self.run_cast_command([
            "call", token_address, 
            "balanceOf(address)(uint256)", account
        ])
        return int(result, 16) if result else 0
    
    def approve_token(self, token_address: str, spender: str, amount: int) -> bool:
        """Approve token spending"""
        result = self.run_cast_command([
            "send", token_address,
            "approve(address,uint256)", spender, str(amount),
        ])
        return result is not None
    
    def get_campaign_details(self, factory_address: str, campaign_id: int) -> Optional[dict]:
        """Get campaign details from factory"""
        result = self.run_cast_command([
            "call", factory_address,
            "getCampaign(uint256)", str(campaign_id)
        ])
        
        if not result:
            return None
            
        try:
            # Parse the tuple result
            # This is a simplified parser - in production you'd want more robust parsing
            return {"raw": result}
        except Exception as e:
            logger.error(f"Error parsing campaign details: {e}")
            return None
    
    def get_campaign_address(self, factory_address: str, campaign_id: int) -> Optional[str]:
        """Get campaign contract address"""
        result = self.run_cast_command([
            "call", factory_address,
            "getCampaignAddress(uint256)", str(campaign_id)
        ])
        
        if result and result.startswith("0x"):
            # Ensure address is properly formatted (42 chars total: 0x + 40 hex chars)
            hex_part = result[2:]  # Remove 0x prefix
            if len(hex_part) > 40:
                # If longer than 40 chars, take the last 40 chars (remove leading zeros from padding)
                hex_part = hex_part[-40:]
            elif len(hex_part) < 40:
                # If shorter than 40 chars, pad with leading zeros
                hex_part = hex_part.zfill(40)
            return f"0x{hex_part}"
        return result
    
    def get_account_address(self) -> Optional[str]:
        """Get account address from private key"""
        # wallet address command doesn't need --rpc-url
        full_command = ["cast", "wallet", "address", self.private_key]
        
        try:
            logger.debug("Executing: cast wallet address ...")  # Don't log private key
            result = subprocess.run(full_command, capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                logger.error(f"Cast wallet command failed: {result.stderr}")
                return None
                
            output = result.stdout.strip()
            logger.debug(f"Account address: {output}")
            return output
            
        except subprocess.TimeoutExpired:
            logger.error("Cast wallet command timed out")
            return None
        except Exception as e:
            logger.error(f"Error executing cast wallet command: {e}")
            return None