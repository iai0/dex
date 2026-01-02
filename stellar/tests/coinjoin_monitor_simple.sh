#!/bin/bash

# SoroSwap CoinJoin Queue Monitor (Simple Version)
# Monitors the CoinJoin contract queue and alerts when ready for mixing

# Configuration
CONTRACT_ID="CDRMR2WQHJAREY3OXJLMNQTWVEDNLOHXTCZQNXFFFI36KHF3JJ7QG6PE"
NETWORK="testnet"
CHECK_INTERVAL=10  # seconds
MIN_POOL_SIZE=3
LOG_FILE="./coinjoin_monitor.log"
ALERT_FILE="./coinjoin_alerts.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
total_deposits_found=0
monitor_start_time=$(date +%s)

# Initialize last_deposits counters
last_deposits_10=0
last_deposits_100=0
last_deposits_1K=0
last_deposits_10K=0

# Logging function
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Create progress bar
create_progress_bar() {
    local current=$1
    local total=$2
    local width=20
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "[${GREEN}%*s${RED}%*s${NC}] %d%%" $filled | tr ' ' '█' $empty | tr ' ' '░' $percentage
}

# Get pool statistics for a denomination
get_pool_stats() {
    local denomination=$1
    
    # Use stellar CLI to get pool stats
    local result=$(stellar contract invoke \
        --id "$CONTRACT_ID" \
        --network "$NETWORK" \
        --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
        -- \
        get_coinjoin_stats \
        --denomination_symbol "$denomination" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "$result"
    else
        echo "0,3,0"  # Default: 0 deposits, 3 minimum, 0 fee
    fi
}

# Parse pool stats
parse_pool_stats() {
    local stats="$1"
    # Extract numbers from the result (simplified parsing)
    local deposits=$(echo "$stats" | grep -o '[0-9]\+' | head -1)
    local minimum=$(echo "$stats" | grep -o '[0-9]\+' | head -2 | tail -1)
    local fee=$(echo "$stats" | grep -o '[0-9]\+' | head -3 | tail -1)
    
    # Set defaults if parsing failed
    deposits=${deposits:-0}
    minimum=${minimum:-3}
    fee=${fee:-0}
    
    echo "$deposits,$minimum,$fee"
}

# Check if pool is ready for mixing
is_ready_for_mixing() {
    local deposits=$1
    local minimum=$2
    
    [ "$deposits" -ge "$minimum" ]
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

# Monitor single denomination
monitor_denomination() {
    local denomination=$1
    local description=$2
    
    echo -n "  ${BLUE}${description} (${denomination}XLM):${NC} "
    
    # Get current stats
    local stats_result=$(get_pool_stats "$denomination")
    local parsed_stats=$(parse_pool_stats "$stats_result")
    
    IFS=',' read -r deposits minimum fee <<< "$parsed_stats"
    
    # Check for new deposits
    local last_known=0
    case "$denomination" in
        "10") last_known=$last_deposits_10 ;;
        "100") last_known=$last_deposits_100 ;;
        "1K") last_known=$last_deposits_1K ;;
        "10K") last_known=$last_deposits_10K ;;
    esac
    
    local new_deposits=$((deposits - last_known))
    
    if [ "$new_deposits" -gt 0 ]; then
        echo -e "${GREEN}💰 +$new_deposits new deposit(s)${NC} "
        total_deposits_found=$((total_deposits_found + new_deposits))
        create_alert "NEW_DEPOSITS" "{\"denomination\":\"$denomination\",\"new_deposits\":$new_deposits,\"total_deposits\":$deposits}"
        
        # Update the appropriate counter
        case "$denomination" in
            "10") last_deposits_10=$deposits ;;
            "100") last_deposits_100=$deposits ;;
            "1K") last_deposits_1K=$deposits ;;
            "10K") last_deposits_10K=$deposits ;;
        esac
    fi
    
    # Show status
    local status
    if is_ready_for_mixing "$deposits" "$minimum"; then
        status="${GREEN}READY${NC}"
        create_alert "READY_FOR_MIXING" "{\"denomination\":\"$denomination\",\"deposits\":$deposits,\"minimum\":$minimum}"
    else
        status="${YELLOW}WAITING${NC}"
    fi
    
    # Progress bar
    local progress=$((deposits * 100 / minimum))
    if [ "$progress" -gt 100 ]; then
        progress=100
    fi
    local progress_bar=$(create_progress_bar "$deposits" "$minimum")
    
    echo "$deposits/$minimum deposits $status $progress_bar"
}

# Display summary
display_summary() {
    local total_deposits=0
    local ready_pools=0
    
    echo -e "${CYAN}📊 Queue Summary:${NC}"
    
    # Check each denomination
    for denom in "10" "100" "1K" "10K"; do
        local stats_result=$(get_pool_stats "$denom")
        local parsed_stats=$(parse_pool_stats "$stats_result")
        IFS=',' read -r deposits minimum fee <<< "$parsed_stats"
        
        total_deposits=$((total_deposits + deposits))
        
        if is_ready_for_mixing "$deposits" "$minimum"; then
            ready_pools=$((ready_pools + 1))
            echo -e "  ${GREEN}✅ ${denom}XLM: $deposits deposits (READY)${NC}"
        else
            echo -e "  ${YELLOW}⏳ ${denom}XLM: $deposits deposits (waiting)${NC}"
        fi
    done
    
    echo -e "  ${BLUE}Total Deposits: $total_deposits${NC}"
    echo -e "  ${GREEN}Ready Pools: $ready_pools${NC}"
    
    if [ "$ready_pools" -gt 0 ]; then
        echo -e "${MAGENTA}🎯 POOLS READY FOR MIXING!${NC}"
        echo -e "${YELLOW}⚡ Execute with: ./coinjoin_monitor_simple.sh --mix${NC}"
    fi
}

# Execute mixing for ready pools
execute_mixing() {
    echo -e "${MAGENTA}🔄 Executing CoinJoin mixing...${NC}"
    
    for denom in "10" "100" "1K" "10K"; do
        local stats_result=$(get_pool_stats "$denom")
        local parsed_stats=$(parse_pool_stats "$stats_result")
        IFS=',' read -r deposits minimum fee <<< "$parsed_stats"
        
        if is_ready_for_mixing "$deposits" "$minimum"; then
            echo -e "${YELLOW}Executing mixing for ${denom}XLM pool ($deposits deposits)...${NC}"
            
            # Execute mixing command
            stellar contract invoke \
                --id "$CONTRACT_ID" \
                --network "$NETWORK" \
                --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
                -- \
                execute_coinjoin_mixing \
                --denomination_symbol "$denom" \
                --max_deposits 10
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ Mixing executed for ${denom}XLM${NC}"
                create_alert "MIXING_EXECUTED" "{\"denomination\":\"$denom\",\"deposits\":$deposits}"
            else
                echo -e "${RED}❌ Failed to execute mixing for ${denom}XLM${NC}"
            fi
        fi
    done
}

# Show statistics
show_stats() {
    local current_time=$(date +%s)
    local runtime=$((current_time - monitor_start_time))
    local hours=$((runtime / 3600))
    local minutes=$(((runtime % 3600) / 60))
    local seconds=$((runtime % 60))
    
    echo -e "${CYAN}📈 Monitor Statistics:${NC}"
    echo "  Runtime: ${hours}h ${minutes}m ${seconds}s"
    echo "  Total Deposits Found: $total_deposits_found"
    echo "  Log File: $LOG_FILE"
    echo "  Alert File: $ALERT_FILE"
    
    if [ -f "$ALERT_FILE" ]; then
        local alert_count=$(wc -l < "$ALERT_FILE")
        echo "  Total Alerts: $alert_count"
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

# Main monitoring loop
monitor_loop() {
    echo -e "${CYAN}🚀 Starting SoroSwap CoinJoin Queue Monitor${NC}"
    echo -e "${BLUE}Contract: $CONTRACT_ID${NC}"
    echo -e "${BLUE}Network: $NETWORK${NC}"
    echo -e "${BLUE}Check Interval: ${CHECK_INTERVAL}s${NC}"
    echo ""
    
    log_message "Monitor started"
    
    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${CYAN}🔍 [$timestamp] Checking CoinJoin queue...${NC}"
        
        # Monitor each denomination
        monitor_denomination "10" "1 XLM"
        monitor_denomination "100" "10 XLM"
        monitor_denomination "1K" "100 XLM"
        monitor_denomination "10K" "1000 XLM"
        
        echo ""
        display_summary
        echo ""
        
        sleep "$CHECK_INTERVAL"
    done
}

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Stopping monitor...${NC}"
    show_stats
    log_message "Monitor stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main script logic
case "${1:-monitor}" in
    "monitor")
        monitor_loop
        ;;
    "--mix"|"mix")
        execute_mixing
        ;;
    "--stats"|"stats")
        show_stats
        ;;
    "--alerts"|"alerts")
        show_alerts
        ;;
    "--help"|"help"|"-h")
        echo "SoroSwap CoinJoin Queue Monitor"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  monitor        Start monitoring (default)"
        echo "  --mix          Execute mixing for ready pools"
        echo "  --stats        Show monitor statistics"
        echo "  --alerts       Show recent alerts"
        echo "  --help         Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                    # Start monitoring"
        echo "  $0 --mix              # Execute mixing"
        echo "  $0 --stats            # Show statistics"
        echo "  $0 --alerts           # Show alerts"
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Use '$0 --help' for usage information"
        exit 1
        ;;
esac