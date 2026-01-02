#!/bin/bash

# Test different argument formats for get_coinjoin_stats

CONTRACT="CCNEHMSQQV6RG2T2TQTUWAWEEDBGWVXEVUZ4VWNOP65DN6XWDK3JHPNT"

echo "Testing argument formats for get_coinjoin_stats..."
echo ""

# Test formats that work
echo "1. Testing '1K' format (works):"
stellar contract invoke \
  --id "$CONTRACT" \
  --network testnet \
  -- \
  get_coinjoin_stats \
  --denomination_symbol 1K

echo ""

# Try '100' with different approaches
echo "2. Testing '100' as string:"
stellar contract invoke \
  --id "$CONTRACT" \
  --network testnet \
  -- \
  get_coinjoin_stats \
  --denomination_symbol '"100"'

echo ""

echo "3. Testing '100' with different flag:"
stellar contract invoke \
  --id "$CONTRACT" \
  --network testnet \
  -- \
  get_coinjoin_stats \
  --denomination-symbol 100

echo ""

echo "4. Testing '100' with quotes:"
stellar contract invoke \
  --id "$CONTRACT" \
  --network testnet \
  -- \
  get_coinjoin_stats \
  --denomination-symbol '"100"'

echo ""

echo "5. Testing other denominations:"
for denom in 10 "10K"; do
    echo "Testing '$denom':"
    stellar contract invoke \
      --id "$CONTRACT" \
      --network testnet \
      -- \
      get_coinjoin_stats \
      --denomination_symbol "$denom"
    echo ""
done