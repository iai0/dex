#!/bin/bash

# CoinJoin Testing Script for SoroSwap Batch Contract using Stellar CLI (Fixed)
# Uses existing darkstar identities for testing

# Contract Configuration
CONTRACT_ID="CDRMR2WQHJAREY3OXJLMNQTWVEDNLOHXTCZQNXFFFI36KHF3JJ7QG6PE"
NETWORK="testnet"

# Test Configuration - Using existing darkstar identities
DARKSTAR1="GADKZY72YJJIIOTXX27PCRIKA6MRYYMGNCECOVWDJ4TZLQUJL7UFNM2H"
DARKSTAR2="GCKABQLKLXF6JWUGT2JBZ3WYLPT77XCYL2MNB355VMQJ3Y37XDZD5BOD"
DARKSTAR3="GDQDUWAVMMVUZZTKEYAHYJWHB5NWG4NOGGB25IQZ5DH44EZIFQYX3K45"

# Get secret keys
SECRET1=$(stellar keys secret darkstar1)
SECRET2=$(stellar keys secret darkstar2)
SECRET3=$(stellar keys secret darkstar3)

# Token address (using native XLM for simplicity)
TOKEN_ADDRESS="native"

echo "🔄 SoroSwap CoinJoin Testing Script (Fixed)"
echo "=========================================="
echo "Contract ID: $CONTRACT_ID"
echo "Network: $NETWORK"
echo "Test Accounts: darkstar1, darkstar2, darkstar3"
echo ""

# Check initial pool statistics
echo "📊 Checking initial pool statistics..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET1" \
    -- \
    get_coinjoin_stats \
    --denomination_symbol '"10"'

echo ""

# Test 1: Check if contract is properly initialized
echo "🔍 Checking contract initialization..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET1" \
    -- \
    get_owner

echo ""

# Test 2: Try a simple private_swap with darkstar1
echo "💰 Testing private_swap with darkstar1..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET1" \
    -- \
    private_swap \
    --token_in "$TOKEN_ADDRESS" \
    --token_out "$TOKEN_ADDRESS" \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address "$DARKSTAR1" \
    --receiving_address "$DARKSTAR2"

echo ""

# Check pool statistics after first deposit
echo "📊 Pool statistics after first deposit:"
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET1" \
    -- \
    get_coinjoin_stats \
    --denomination_symbol '"10"'

echo ""

# Test 3: Second deposit with darkstar2
echo "💰 Testing private_swap with darkstar2..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET2" \
    -- \
    private_swap \
    --token_in "$TOKEN_ADDRESS" \
    --token_out "$TOKEN_ADDRESS" \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address "$DARKSTAR2" \
    --receiving_address "$DARKSTAR3"

echo ""

# Test 4: Third deposit with darkstar3
echo "💰 Testing private_swap with darkstar3..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET3" \
    -- \
    private_swap \
    --token_in "$TOKEN_ADDRESS" \
    --token_out "$TOKEN_ADDRESS" \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address "$DARKSTAR3" \
    --receiving_address "$DARKSTAR1"

echo ""

# Check pool statistics after all deposits
echo "📊 Pool statistics after all deposits:"
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET1" \
    -- \
    get_coinjoin_stats \
    --denomination_symbol '"10"'

echo ""

# Test 5: Execute CoinJoin mixing
echo "🔄 Executing CoinJoin mixing..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET1" \
    -- \
    execute_coinjoin_mixing \
    --denomination_symbol '"10"' \
    --max_deposits 3

echo ""

# Final pool statistics
echo "📊 Final pool statistics:"
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$SECRET1" \
    -- \
    get_coinjoin_stats \
    --denomination_symbol '"10"'

echo ""
echo "✅ CoinJoin testing complete!"
echo ""
echo "📝 Test Summary:"
echo "- Used existing darkstar1, darkstar2, darkstar3 identities"
echo "- Tested private_swap functionality"
echo "- Tested execute_coinjoin_mixing functionality"
echo "- Verified pool statistics throughout the process"
echo ""
echo "🔗 Explorer Links:"
echo "- Contract: https://stellar.expert/explorer/testnet/contract/$CONTRACT_ID"
echo "- darkstar1: https://stellar.expert/explorer/testnet/account/$DARKSTAR1"
echo "- darkstar2: https://stellar.expert/explorer/testnet/account/$DARKSTAR2"
echo "- darkstar3: https://stellar.expert/explorer/testnet/account/$DARKSTAR3"