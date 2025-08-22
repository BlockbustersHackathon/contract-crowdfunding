#!/usr/bin/env python3
"""
Quick test script to verify the cast wallet address fix
"""

import os
from dotenv import load_dotenv
from cast_interactor import CastInteractor

# Load environment variables
load_dotenv()

def test_wallet_address():
    """Test that wallet address derivation works"""
    creator_key = os.getenv("CREATOR_PRIVATE_KEY")
    donor_key = os.getenv("DONOR_PRIVATE_KEY")
    rpc_url = os.getenv("RPC_URL")
    
    if not all([creator_key, donor_key, rpc_url]):
        print("❌ Missing environment variables")
        return False
    
    try:
        # Test creator account
        creator_cast = CastInteractor(rpc_url, creator_key)
        creator_address = creator_cast.get_account_address()
        
        if creator_address and creator_address.startswith("0x"):
            print(f"✅ Creator address: {creator_address}")
        else:
            print("❌ Failed to get creator address")
            return False
            
        # Test donor account  
        donor_cast = CastInteractor(rpc_url, donor_key)
        donor_address = donor_cast.get_account_address()
        
        if donor_address and donor_address.startswith("0x"):
            print(f"✅ Donor address: {donor_address}")
        else:
            print("❌ Failed to get donor address") 
            return False
            
        print("✅ Cast wallet address fix working correctly!")
        return True
        
    except Exception as e:
        print(f"❌ Error testing wallet address: {e}")
        return False

if __name__ == "__main__":
    test_wallet_address()