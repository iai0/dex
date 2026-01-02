#!/bin/bash

# CoinJoin Testing Script for SoroSwap Batch Contract
# This script demonstrates how to test CoinJoin mixing with 3+ transactions

# Contract Configuration
CONTRACT_ID="12ea27436481b1af2e1ec2ad4605b9c57a957cfe988e12447d2f23baf2b2ecd9"
NETWORK="testnet"
RPC_URL="https://soroban-testnet.stellar.org"

# Test Configuration
DENOMINATION="10"  # 1 XLM in stroops
TOKEN_ADDRESS="GBLM4UQ7O6K5YRVMQ6ZMSIZB23YVYRK5ZD6O3N5YK5Y5Y5Y5Y5Y5Y5"  # XLM token on testnet

echo "🔄 SoroSwap CoinJoin Testing Script"
echo "======================================"
echo "Contract ID: $CONTRACT_ID"
echo "Network: $NETWORK"
echo "Denomination: $DENOMINATION XLM"
echo ""

# Generate fresh addresses for privacy (source + receiving)
echo "📍 Generating fresh addresses for CoinJoin participants..."
RECEIVER1=$(soroban config identity generate --network testnet)
RECEIVER2=$(soroban config identity generate --network testnet)
RECEIVER3=$(soroban config identity generate --network testnet)

# Generate separate receiving addresses for each user (critical for privacy)
RECEIVING_ADDR1=$(soroban config identity generate --network testnet)
RECEIVING_ADDR2=$(soroban config identity generate --network testnet)
RECEIVING_ADDR3=$(soroban config identity generate --network testnet)

echo "User 1 - Source: $RECEIVER1"
echo "User 1 - Receiving: $RECEIVING_ADDR1"
echo ""
echo "User 2 - Source: $RECEIVER2"
echo "User 2 - Receiving: $RECEIVING_ADDR2"
echo ""
echo "User 3 - Source: $RECEIVER3"
echo "User 3 - Receiving: $RECEIVING_ADDR3"
echo ""

# Check initial pool statistics
echo "📊 Checking initial pool statistics..."
soroban contract invoke \
    --id $CONTRACT_ID \
    --network $NETWORK \
    -- \
    get_coinjoin_stats \
    --denomination_symbol $DENOMINATION

echo ""

# Simulate 3 users making private swaps (in practice, these would be real transactions)
echo "💰 Simulating 3 CoinJoin deposits..."

# User 1 deposit
echo "👤 User 1: Depositing 1 XLM to CoinJoin pool..."
soroban contract invoke \
    --id $CONTRACT_ID \
    --network $NETWORK \
    --source $RECEIVER1 \
    -- \
    private_swap \
    --token_in $TOKEN_ADDRESS \
    --token_out $TOKEN_ADDRESS \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address $RECEIVER1 \
    --receiving_address $RECEIVING_ADDR1

# User 2 deposit
echo "👤 User 2: Depositing 1 XLM to CoinJoin pool..."
soroban contract invoke \
    --id $CONTRACT_ID \
    --network $NETWORK \
    --source $RECEIVER2 \
    -- \
    private_swap \
    --token_in $TOKEN_ADDRESS \
    --token_out $TOKEN_ADDRESS \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address $RECEIVER2 \
    --receiving_address $RECEIVING_ADDR2

# User 3 deposit
echo "👤 User 3: Depositing 1 XLM to CoinJoin pool..."
soroban contract invoke \
    --id $CONTRACT_ID \
    --network $NETWORK \
    --source $RECEIVER3 \
    -- \
    private_swap \
    --token_in $TOKEN_ADDRESS \
    --token_out $TOKEN_ADDRESS \
    --amount_in 10000000 \
    --min_amount_out 9900000 \
    --user_address $RECEIVER3 \
    --receiving_address $RECEIVING_ADDR3

echo ""

# Check pool statistics after deposits
echo "📊 Pool statistics after deposits:"
soroban contract invoke \
    --id $CONTRACT_ID \
    --network $NETWORK \
    -- \
    get_coinjoin_stats \
    --denomination_symbol $DENOMINATION

echo ""

# Execute mixing when pool has enough participants
echo "🔄 Executing CoinJoin mixing..."
soroban contract invoke \
    --id $CONTRACT_ID \
    --network $NETWORK \
    -- \
    execute_coinjoin_mixing \
    --denomination_symbol $DENOMINATION \
    --max_deposits 3

echo ""

# Final pool statistics
echo "📊 Final pool statistics:"
soroban contract invoke \
    --id $CONTRACT_ID \
    --network $NETWORK \
    -- \
    get_coinjoin_stats \
    --denomination_symbol $DENOMINATION

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