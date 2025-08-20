#!/bin/bash

# Infura Sepolia RPC URL
RPC_URL="https://sepolia.infura.io/v3/89aa1f7b407142ac9d6539e044934786"
# Contract address
CONTRACT="0x408A35083AbE22eC07a0cAB3caB0DA8f57b767Fb"
# Your private key (never commit this to source control!)

# Example batch: address,amount (amount in USDC's smallest unit, i.e., 6 decimals)
declare -a RECIPIENTS=(
    "0x870a62A5ea54477DE889d00E74026D5d1d9732fE,1000000000000"   # 1 USDC
    "0xA77E3Ad20aC9E201225c33d9b95890B8aE3F6d50,1000000000000"   # 5 USDC
)
#0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef 

#0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
for entry in "${RECIPIENTS[@]}"; do
    IFS=',' read -r TO AMOUNT <<< "$entry"
    echo "Minting $AMOUNT to $TO"
    cast send $CONTRACT "mint(address,uint256)" $TO $AMOUNT \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY
done