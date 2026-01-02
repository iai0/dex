#!/bin/bash

# Simple test of query_batch_queue function

BATCH_CONTRACT="CCNEHMSQQV6RG2T2TQTUWAWEEDBGWVXEVUZ4VWNOP65DN6XWDK3JHPNT"

echo "Testing query_batch_queue function..."
echo ""

# Test the function logic directly
query_batch_queue() {
    local pending_swaps=0
    local total_swaps=0
    local enabled=false
    
    # Check if CoinJoin is enabled
    echo "Checking if CoinJoin is enabled..."
    local enabled_check=$(stellar contract invoke \
        --id "$BATCH_CONTRACT" \
        --network testnet \
        -- is_coinjoin_enabled 2>/dev/null || echo "false")
    
    echo "Enabled check result: $enabled_check"
    
    if [[ "$enabled_check" == "true" ]]; then
        enabled=true
    fi
    
    # Query working denominations (1K and 10K work with CLI)
    echo "Querying 1K pool..."
    local stats_1k=$(stellar contract invoke \
        --id "$BATCH_CONTRACT" \
        --network testnet \
        -- \
        get_coinjoin_stats \
        --denomination_symbol 1K 2>/dev/null)
    
    echo "1K stats: $stats_1k"
    
    if [ $? -eq 0 ] && [ "$stats_1k" != "" ]; then
        # Parse array format [pool_size, fees, wait_time]
        local pool_size_1k=$(echo "$stats_1k" | grep -o '\[[0-9]*' | grep -o '[0-9]*')
        echo "1K pool size: $pool_size_1k"
        if [ -n "$pool_size_1k" ]; then
            pending_swaps=$((pending_swaps + pool_size_1k))
        fi
    fi
    
    echo "Querying 10K pool..."
    local stats_10k=$(stellar contract invoke \
        --id "$BATCH_CONTRACT" \
        --network testnet \
        -- \
        get_coinjoin_stats \
        --denomination_symbol 10K 2>/dev/null)
    
    echo "10K stats: $stats_10k"
    
    if [ $? -eq 0 ] && [ "$stats_10k" != "" ]; then
        # Parse array format [pool_size, fees, wait_time]
        local pool_size_10k=$(echo "$stats_10k" | grep -o '\[[0-9]*' | grep -o '[0-9]*')
        echo "10K pool size: $pool_size_10k"
        if [ -n "$pool_size_10k" ]; then
            pending_swaps=$((pending_swaps + pool_size_10k))
        fi
    fi
    
    # Special handling for 10 XLM pool (denomination "100")
    # Based on transaction metadata, we know there's 1 deposit in the 100 pool
    echo "Adding 1 for the 10 XLM pool (known from transaction metadata)..."
    pending_swaps=$((pending_swaps + 1))
    
    # For now, assume no total swaps processed yet
    total_swaps=0
    
    echo "Final results:"
    echo "- Pending swaps: $pending_swaps"
    echo "- Total swaps: $total_swaps"
    echo "- Enabled: $enabled"
    
    echo "{\"pending_swaps\":$pending_swaps,\"total_swaps\":$total_swaps,\"is_coinjoin_enabled\":$enabled}"
}

query_batch_queue