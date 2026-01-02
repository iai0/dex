#!/bin/bash

# SoroSwap Private Swap Queue Monitor (v1)
# Monitors the batch contract private swap queue for XLM-TEST pool testing

# Configuration
CONTRACT_ID="CA4EH6LZRRRFMKF4JFXD42SL2ATCNOXUJKRED7PPF75UWIE6TUOXQCP7"
NETWORK="testnet"
CHECK_INTERVAL=10  # seconds
MIN_PARTICIPANTS=3
LOG_FILE="./private_swap_monitor.log"
ALERT_FILE="./private_swap_alerts.json"

# XLM-pXLM pool monitoring configuration
XLM_PXLM_POOL="CBVXO445IA4SZ4ZBZFRITNP2XSPS2JPBDRMCCNXHN7O646VMJ7KTHWXJ"  # Known pool address
POOL_CACHE_FILE="./pool_cache.json"
POOL_CHECK_INTERVAL=60  # Check for new pools every minute

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
total_swaps_seen=0
monitor_start_time=$(date +%s)
last_queue_size=0
last_pool_check=0
known_pools=""

# Logging function
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Create progress bar for queue status
create_progress_bar() {
    local current=$1
    local total=$2
    local width=20
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    # Create filled and empty parts
    local filled_bar=$(printf "%*s" $filled | tr ' ' '█')
    local empty_bar=$(printf "%*s" $empty | tr ' ' '░')
    
    printf "[${GREEN}${filled_bar}${RED}${empty_bar}${NC}] %d%%" $percentage
}

# Find XLM-pXLM pool from factory
find_xlm_pxlm_pool() {
    # Return the known pool address directly
    echo "$XLM_PXLM_POOL"
}

# Get batch contract statistics
get_batch_stats() {
    # Check if CoinJoin is enabled first
    local enabled=$(stellar contract invoke \
        --id "$CONTRACT_ID" \
        --network "$NETWORK" \
        --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
        -- \
        is_coinjoin_enabled 2>/dev/null)

    if [ $? -eq 0 ]; then
        # Try to get stats for common denominations
        local pending_swaps=0
        local total_swaps=0
        
        # Query all denominations: 10 (1 XLM), 100 (10 XLM), 1000 (100 XLM), 10000 (200 XLM)
        for denom in "10" "100" "1000" "10000"; do
            local stats=$(stellar contract invoke \
                --id "$CONTRACT_ID" \
                --network testnet \
                --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
                -- \
                get_coinjoin_stats \
                --denomination_symbol "{\"symbol\":\"$denom\"}" 2>/dev/null)

            if [ $? -eq 0 ] && [ "$stats" != "" ]; then
                # Parse array format [pool_size, fees, wait_time]
                local pool_size=$(echo "$stats" | grep -o '^\[[0-9]*' | grep -o '[0-9]*')
                if [ -n "$pool_size" ]; then
                    pending_swaps=$((pending_swaps + pool_size))
                fi
            fi
        done
        
        echo "{\"pending_swaps\":$pending_swaps,\"total_swaps\":$total_swaps,\"is_coinjoin_enabled\":$enabled}"
    else
        echo '{"pending_swaps":0,"total_swaps":0,"is_coinjoin_enabled":false}'
    fi
}

# Check pool queue status
check_pool_queue() {
    local pool_address="$1"
    
    # Get pool stats to check queue
    local result=$(stellar contract invoke \
        --id "$pool_address" \
        --network "$NETWORK" \
        --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
        -- \
        get_stats 2>/dev/null)

    if [ $? -eq 0 ]; then
        # Extract queue information (simplified parsing)
        local queue_size=$(echo "$result" | grep -o '"queue_size":[0-9]*' | cut -d':' -f2)
        echo "${queue_size:-0}"
    else
        echo "0"
    fi
}

# Parse batch stats (simplified JSON parsing)
parse_batch_stats() {
    local stats="$1"

    # Extract key values using grep and cut
    local pending_swaps=$(echo "$stats" | grep -o '"pending_swaps":[0-9]*' | cut -d':' -f2)
    local total_swaps=$(echo "$stats" | grep -o '"total_swaps":[0-9]*' | cut -d':' -f2)
    local coinjoin_enabled=$(echo "$stats" | grep -o '"is_coinjoin_enabled":true\|false' | cut -d':' -f2)

    # Set defaults if parsing failed
    pending_swaps=${pending_swaps:-0}
    total_swaps=${total_swaps:-0}
    coinjoin_enabled=${coinjoin_enabled:-true}

    echo "$pending_swaps,$total_swaps,$coinjoin_enabled"
}

# Check if queue is ready for mixing
is_ready_for_mixing() {
    local pending=$1
    local minimum=$2

    [ "$pending" -ge "$minimum" ]
}

# Create alert
create_alert() {
    local alert_type="$1"
    local data="$2"
    local timestamp=$(date -Iseconds)

    local alert="{\"id\":\"$(date +%s)\",\"type\":\"$alert_type\",\"data\":$data,\"timestamp\":\"$timestamp\"}"

    # Add to alerts file
    if [ -f "$ALERT_FILE" ]; then
        # Insert new alert at the beginning
        local temp_file=$(mktemp)
        echo "$alert" > "$temp_file"
        cat "$ALERT_FILE" >> "$temp_file"
        # Keep only last 50 alerts
        head -n 50 "$temp_file" > "$ALERT_FILE"
        rm "$temp_file"
    else
        echo "$alert" > "$ALERT_FILE"
    fi

    log_message "ALERT: $alert_type - $data"
}

# Display queue status
display_queue_status() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}🔍 [$timestamp] Private Swap Queue Status:${NC}"

    # Get current stats
    local stats_result=$(get_batch_stats)
    local parsed_stats=$(parse_batch_stats "$stats_result")

    IFS=',' read -r pending_swaps total_swaps coinjoin_enabled <<< "$parsed_stats"

    # Check for new swaps
    local new_swaps=$((pending_swaps - last_queue_size))

    if [ "$new_swaps" -gt 0 ]; then
        echo -e "${GREEN}💰 +$new_swaps new swap(s) in queue${NC}"
        total_swaps_seen=$((total_swaps_seen + new_swaps))
        create_alert "NEW_SWAPS" "{\"new_swaps\":$new_swaps,\"pending_swaps\":$pending_swaps,\"total_swaps\":$total_swaps}"
    elif [ "$new_swaps" -lt 0 ]; then
        echo -e "${MAGENTA}🔄 Mixing executed! Queue reset${NC}"
        create_alert "MIXING_EXECUTED" "{\"previous_queue_size\":$last_queue_size,\"pending_swaps\":$pending_swaps}"
    fi

    last_queue_size=$pending_swaps

    # Show status
    local status
    if is_ready_for_mixing "$pending_swaps" "$MIN_PARTICIPANTS"; then
        status="${GREEN}READY FOR MIXING${NC}"
        create_alert "READY_FOR_MIXING" "{\"pending_swaps\":$pending_swaps,\"minimum\":$MIN_PARTICIPANTS}"
    else
        status="${YELLOW}WAITING FOR PARTICIPANTS${NC}"
    fi

    # Progress bar
    local progress=$((pending_swaps * 100 / MIN_PARTICIPANTS))
    if [ "$progress" -gt 100 ]; then
        progress=100
    fi
    local progress_bar=$(create_progress_bar "$pending_swaps" "$MIN_PARTICIPANTS")

    echo -e "  Batch Queue: $pending_swaps/$MIN_PARTICIPANTS participants $status $progress_bar"
    echo -e "  Total swaps processed: $total_swaps"
    echo -e "  CoinJoin enabled: $coinjoin_enabled"

    if is_ready_for_mixing "$pending_swaps" "$MIN_PARTICIPANTS"; then
        echo -e "${MAGENTA}🎯 BATCH QUEUE READY FOR AUTOMATIC MIXING!${NC}"
        echo -e "${YELLOW}⚡ The next transaction will trigger mixing${NC}"
    fi

    echo ""
}

# Display XLM-pXLM pool queue status
display_pool_status() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}🏊 [$timestamp] XLM-pXLM Pool Queue Status:${NC}"

    # Find XLM-pXLM pool
    local pool_address=$(find_xlm_pxlm_pool)
    
    if [ -n "$pool_address" ]; then
        echo -e "${CYAN}Monitoring XLM-pXLM Pool:${NC}"
        echo -e "  Pool Address: ${pool_address:0:8}...${pool_address: -8}"
        
        # Get pool queue status
        local queue_size=$(check_pool_queue "$pool_address")
        
        # Show pool status
        local pool_status
        if [ "$queue_size" -ge 1 ]; then
            pool_status="${GREEN}ACTIVE${NC}"
            echo -e "  Queue Size: $queue_size transactions | $pool_status"
            
            if [ "$queue_size" -eq 1 ]; then
                echo -e "    ${YELLOW}⚡ Pool has 1 transaction - ready for processing!${NC}"
                create_alert "POOL_READY" "{\"pool\":\"$pool_address\",\"queue_size\":$queue_size}"
            else
                echo -e "    ${GREEN}📊 Pool has $queue_size transactions pending${NC}"
            fi
        else
            pool_status="${GRAY}IDLE${NC}"
            echo -e "  Queue Size: $queue_size transactions | $pool_status"
            echo -e "    ${YELLOW}⏳ Waiting for transactions in pool${NC}"
        fi
    else
        echo -e "${YELLOW}XLM-pXLM pool not found yet${NC}"
        echo -e "  ${GRAY}Make sure the pool has been deployed with XLM and pXLM tokens${NC}"
    fi
    
    echo ""
}

# Display summary
display_summary() {
    local current_time=$(date +%s)
    local runtime=$((current_time - monitor_start_time))
    local hours=$((runtime / 3600))
    local minutes=$(((runtime % 3600) / 60))
    local seconds=$((runtime % 60))

    echo -e "${CYAN}📊 Monitor Summary:${NC}"
    echo "  Runtime: ${hours}h ${minutes}m ${seconds}s"
    echo "  Total swaps seen: $total_swaps_seen"
    echo "  Current queue size: $last_queue_size"
    echo "  Minimum participants: $MIN_PARTICIPANTS"
    echo "  Log file: $LOG_FILE"
    echo "  Alert file: $ALERT_FILE"

    if [ -f "$ALERT_FILE" ]; then
        local alert_count=$(wc -l < "$ALERT_FILE")
        echo "  Total alerts: $alert_count"
    fi
}

# Show recent alerts
show_alerts() {
    echo -e "${CYAN}🚨 Recent Alerts:${NC}"

    if [ -f "$ALERT_FILE" ]; then
        head -n 10 "$ALERT_FILE" | while IFS= read -r line; do
            local timestamp=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
            local type=$(echo "$line" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
            local data=$(echo "$line" | grep -o '"data":{[^}]*}' | cut -d':' -f2-)

            echo "  $timestamp - $type: $data"
        done
    else
        echo "  No alerts yet."
    fi
}

# Test current queue status (one-time check)
test_queue() {
    echo -e "${CYAN}🧪 Testing Current Queue Status:${NC}"
    display_queue_status
    display_pool_status
}

# Main monitoring loop
monitor_loop() {
    echo -e "${CYAN}🚀 Starting SoroSwap Private Swap Queue Monitor${NC}"
    echo -e "${BLUE}Batch Contract: $CONTRACT_ID${NC}"
    echo -e "${BLUE}Network: $NETWORK${NC}"
    echo -e "${BLUE}Check Interval: ${CHECK_INTERVAL}s${NC}"
    echo -e "${BLUE}Minimum Participants: $MIN_PARTICIPANTS${NC}"
    echo -e "${BLUE}Monitoring: XLM-pXLM Pool Queue${NC}"
    echo ""

    log_message "Private swap monitor started"

    # Show initial status
    display_queue_status
    display_pool_status

    while true; do
        sleep "$CHECK_INTERVAL"
        display_queue_status
        display_pool_status
    done
}

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Stopping monitor...${NC}"
    display_summary
    log_message "Private swap monitor stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main script logic
case "${1:-monitor}" in
    "monitor")
        monitor_loop
        ;;
    "test")
        test_queue
        ;;
    "--stats"|"stats")
        display_summary
        ;;
    "--alerts"|"alerts")
        show_alerts
        ;;
    "--help"|"help"|"-h")
        echo "SoroSwap Private Swap Queue Monitor (v1)"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  monitor        Start monitoring (default)"
        echo "  test           Check current queue status once"
        echo "  --stats        Show monitor statistics"
        echo "  --alerts       Show recent alerts"
        echo "  --help         Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                    # Start monitoring"
        echo "  $0 test              # Check queue status once"
        echo "  $0 --stats            # Show statistics"
        echo "  $0 --alerts           # Show alerts"
        echo ""
        echo "What to expect during testing:"
        echo "  1. Batch Contract: Monitors CoinJoin queue (needs 3 participants)"
        echo "  2. XLM-pXLM Pool: Monitors pool queue (1+ transactions)"
        echo "  3. Pool Queue: Shows transactions waiting in XLM-pXLM pool"
        echo "  4. Batch Queue: Shows swaps waiting for CoinJoin mixing"
        echo "  5. Mixing: When batch has 3+ participants, automatic mixing occurs"
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Use '$0 --help' for usage information"
        exit 1
        ;;
esac