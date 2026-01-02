#!/bin/bash

# Test script to query batch contract with different argument formats

CONTRACT="CCNEHMSQQV6RG2T2TQTUWAWEEDBGWVXEVUZ4VWNOP65DN6XWDK3JHPNT"

echo "Testing batch contract queries..."
echo "Contract: $CONTRACT"
echo ""

# Test 1: Check if CoinJoin is enabled
echo "1. Checking if CoinJoin is enabled:"
stellar contract invoke \
  --id "$CONTRACT" \
  --network testnet \
  -- is_coinjoin_enabled

echo ""

# Test 2: Try get_coinjoin_stats with different formats
echo "2. Testing get_coinjoin_stats with different denomination formats:"

# Try with Symbol::short("100") format
echo "Trying denomination '100' (10 XLM):"
stellar contract invoke \
  --id "$CONTRACT" \
  --network testnet \
  -- \
  get_coinjoin_stats \
  --denomination_symbol 100

echo ""

# Try with explicit string
echo "Trying denomination as string:"
stellar contract invoke \
  --id "$CONTRACT" \
  --network testnet \
  -- \
  get_coinjoin_stats \
  --denomination_symbol '"100"'

echo ""

# Try other denominations
for denom in 10 1000 "1K" "10K"; do
    echo "Trying denomination '$denom':"
    stellar contract invoke \
      --id "$CONTRACT" \
      --network testnet \
      -- \
      get_coinjoin_stats \
      --denomination_symbol "$denom"
    echo ""
done