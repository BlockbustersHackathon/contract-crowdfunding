#!/bin/bash

# Contract address
CONTRACT="0x341b91B5C76807A812E6Ef13bBaF3Fc4b2C8f96B"
# Your private key (never commit this to source control!)

# Example batch: address,amount (amount in USDC's smallest unit, i.e., 6 decimals)
declare -a RECIPIENTS=(
    "0x870a62A5ea54477DE889d00E74026D5d1d9732fE,1000000000000"
    "0xA77E3Ad20aC9E201225c33d9b95890B8aE3F6d50,1000000000000"    
)

for entry in "${RECIPIENTS[@]}"; do
    IFS=',' read -r TO AMOUNT <<< "$entry"
    echo "Minting $AMOUNT to $TO"
    cast send $CONTRACT "mint(address,uint256)" $TO $AMOUNT \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY
    sleep 1
done