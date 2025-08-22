#!/bin/bash

# Infura Sepolia RPC URL
# Contract address
CONTRACT="0x6B38Bc61C90F80F77F3A65B0EA470259e682951B"

# Example batch: address,amount (amount in USDC's smallest unit, i.e., 6 decimals)
declare -a RECIPIENTS=(
    # "0x870a62A5ea54477DE889d00E74026D5d1d9732fE,1000000000000"   # 1 USDC
    # "0xA77E3Ad20aC9E201225c33d9b95890B8aE3F6d50,1000000000000"   # 5 USDC
    # "0x172c7004852c62A48251c4E0659577ed962A1A0f,1000000000000"   # 5 USDC
    "0x9a81ef5Cc0A23b1592BFD8A10d3E4122E41FABB5,1000000000000"   # 5 USDC
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