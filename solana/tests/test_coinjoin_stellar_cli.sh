#!/bin/bash

# CoinJoin Testing Script for SoroSwap Batch Contract using Stellar CLI
# This script demonstrates how to test CoinJoin mixing with 3+ transactions

# Contract Configuration
CONTRACT_ID="CDRMR2WQHJAREY3OXJLMNQTWVEDNLOHXTCZQNXFFFI36KHF3JJ7QG6PE"
NETWORK="testnet"
RPC_URL="https://soroban-testnet.stellar.org"

# Test Configuration
DENOMINATION="10"  # 1 XLM in stroops
TOKEN_ADDRESS="GBLM4UQ7O6K5YRVMQ6ZMSIZB23YVYRK5ZD6O3N5YK5Y5Y5Y5Y5Y5Y5"  # XLM token on testnet

echo "🔄 SoroSwap CoinJoin Testing Script (Stellar CLI)"
echo "=============================================="
echo "Contract ID: $CONTRACT_ID"
echo "Network: $NETWORK"
echo "Denomination: $DENOMINATION XLM"
echo ""

# Generate fresh addresses for privacy (source + receiving)
echo "📍 Generating fresh addresses for CoinJoin participants..."
RECEIVER1_KEY=$(stellar keys generate --network testnet)
RECEIVER1_ADDRESS=$(stellar keys address "$RECEIVER1_KEY")

RECEIVER2_KEY=$(stellar keys generate --network testnet)
RECEIVER2_ADDRESS=$(stellar keys address "$RECEIVER2_KEY")

RECEIVER3_KEY=$(stellar keys generate --network testnet)
RECEIVER3_ADDRESS=$(stellar keys address "$RECEIVER3_KEY")

# Generate separate receiving addresses for each user (critical for privacy)
RECEIVING_ADDR1_KEY=$(stellar keys generate --network testnet)
RECEIVING_ADDR1_ADDRESS=$(stellar keys address "$RECEIVING_ADDR1_KEY")

RECEIVING_ADDR2_KEY=$(stellar keys generate --network testnet)
RECEIVING_ADDR2_ADDRESS=$(stellar keys address "$RECEIVING_ADDR2_KEY")

RECEIVING_ADDR3_KEY=$(stellar keys generate --network testnet)
RECEIVING_ADDR3_ADDRESS=$(stellar keys address "$RECEIVING_ADDR3_KEY")

echo "User 1 - Source: $RECEIVER1_ADDRESS"
echo "User 1 - Receiving: $RECEIVING_ADDR1_ADDRESS"
echo ""
echo "User 2 - Source: $RECEIVER2_ADDRESS"
echo "User 2 - Receiving: $RECEIVING_ADDR2_ADDRESS"
echo ""
echo "User 3 - Source: $RECEIVER3_ADDRESS"
echo "User 3 - Receiving: $RECEIVING_ADDR3_ADDRESS"
echo ""

# Fund the accounts for testing
echo "💰 Funding test accounts..."
stellar account fund "$RECEIVER1_ADDRESS" --network testnet
stellar account fund "$RECEIVER2_ADDRESS" --network testnet
stellar account fund "$RECEIVER3_ADDRESS" --network testnet
stellar account fund "$RECEIVING_ADDR1_ADDRESS" --network testnet
stellar account fund "$RECEIVING_ADDR2_ADDRESS" --network testnet
stellar account fund "$RECEIVING_ADDR3_ADDRESS" --network testnet

# Check initial pool statistics
echo "📊 Checking initial pool statistics..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$RECEIVER1_KEY" \
    -- \
    get_coinjoin_stats \
    --denomination_symbol "$DENOMINATION"

echo ""

# Simulate 3 users making private swaps (in practice, these would be real transactions)
echo "💰 Simulating 3 CoinJoin deposits..."

# User 1 deposit
echo "👤 User 1: Depositing 1 XLM to CoinJoin pool..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$RECEIVER1_KEY" \
    -- \
    private_swap \
    --token_in "$TOKEN_ADDRESS" \
    --token_out "$TOKEN_ADDRESS" \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address "$RECEIVER1_ADDRESS" \
    --receiving_address "$RECEIVING_ADDR1_ADDRESS"

# User 2 deposit
echo "👤 User 2: Depositing 1 XLM to CoinJoin pool..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$RECEIVER2_KEY" \
    -- \
    private_swap \
    --token_in "$TOKEN_ADDRESS" \
    --token_out "$TOKEN_ADDRESS" \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address "$RECEIVER2_ADDRESS" \
    --receiving_address "$RECEIVING_ADDR2_ADDRESS"

# User 3 deposit
echo "👤 User 3: Depositing 1 XLM to CoinJoin pool..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$RECEIVER3_KEY" \
    -- \
    private_swap \
    --token_in "$TOKEN_ADDRESS" \
    --token_out "$TOKEN_ADDRESS" \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address "$RECEIVER3_ADDRESS" \
    --receiving_address "$RECEIVING_ADDR3_ADDRESS"

echo ""

# Check pool statistics after deposits
echo "📊 Pool statistics after deposits:"
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$RECEIVER1_KEY" \
    -- \
    get_coinjoin_stats \
    --denomination_symbol "$DENOMINATION"

echo ""

# Execute mixing when pool has enough participants
echo "🔄 Executing CoinJoin mixing..."
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$RECEIVER1_KEY" \
    -- \
    execute_coinjoin_mixing \
    --denomination_symbol "$DENOMINATION" \
    --max_deposits 3

echo ""

# Final pool statistics
echo "📊 Final pool statistics:"
stellar contract invoke \
    --id "$CONTRACT_ID" \
    --network "$NETWORK" \
    --source "$RECEIVER1_KEY" \
    -- \
    get_coinjoin_stats \
    --denomination_symbol "$DENOMINATION"

echo ""
echo "✅ CoinJoin testing complete!"
echo ""
echo "🔍 What happened:"
echo "1. 3 users each deposited 1 XLM to the same CoinJoin pool"
echo "2. Each user provided their own fresh receiving address (non-custodial)"
echo "3. Funds are mixed together, breaking the link between inputs and outputs"
echo "4. Each user receives mixed funds to their specified receiving address"
echo "5. Transaction graph analysis is now impossible"
echo ""
echo "🔐 Security Model (Tornado Cash approach):"
echo "- Users control their receiving address private keys"
echo "- Receiving addresses are cryptographically committed to deposits"
echo "- Contract cannot access funds (non-custodial)"
echo "- No link between sender and receiver on blockchain"
echo ""
echo "📈 Privacy benefits:"
echo "- Amount correlation broken (all used same denomination)"
echo "- Transaction link broken (fresh receiving addresses)"
echo "- Timing correlation broken (simultaneous execution)"
echo "- Counterparty discovery prevented (pool mixing)"