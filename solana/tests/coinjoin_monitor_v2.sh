#!/bin/bash

# SoroSwap Private Swap Queue Monitor (v2) - Enhanced with detailed participant info
# Monitors the batch contract private swap queue with detailed participant analysis

# Configuration
CONTRACT_ID="CDBULXZAKJRTZ7LXSY6LQ4NBRE3TXO4LPHQXJAAPIDI2S7NCM5UYRDFA"
NETWORK="testnet"
CHECK_INTERVAL=10  # seconds
MIN_PARTICIPANTS=3
LOG_FILE="./private_swap_monitor_v2.log"

# Pool addresses
XLM_TOKEN="CDLZFC3SYJYDZT7K67VZ75HPJVIEUVNIXF47ZG2FB2RMQQVU2HHGCYSC"
PXLM_TOKEN="CDT3QTGDXGCTL6DITG4QH5WSCSMVFE5EKKMSW4PVQQUSPVAHD5H2YHM4"
XLM_PXLM_POOL="CDJVFZPFB64MDCHTDILL3MAUCIJPNNGRTHKWKRQQ4HB6XOON742SN4VK"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Global variables
monitor_start_time=$(date +%s)
previous_reserve0=0
previous_reserve1=0
last_swap_detected=""

# Logging function
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Get pool reserves and calculate exchange rate
get_pool_info() {
    local pool_address="$1"

    # Get reserves
    local reserves=$(stellar contract invoke \
        --id "$pool_address" \
        --network "$NETWORK" \
        --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
        -- \
        get_reserves 2>&1 | grep -o '\[.*\]')

    if [ -n "$reserves" ]; then
        # Parse reserves ["reserve0","reserve1"] - remove quotes, brackets
        local clean=$(echo "$reserves" | sed 's/"//g' | sed 's/\[//g' | sed 's/\]//g')
        local reserve0=$(echo "$clean" | cut -d',' -f1)
        local reserve1=$(echo "$clean" | cut -d',' -f2)

        # Calculate exchange rate: 1 XLM = ? pXLM
        # rate = reserve1 / reserve0 (assuming XLM is token0)
        if [ -n "$reserve0" ] && [ "$reserve0" -gt 0 ]; then
            # Using bc for decimal calculation
            local rate=$(echo "scale=6; $reserve1 / $reserve0" | bc)
            echo "$reserve0,$reserve1,$rate"
        else
            echo "0,0,0"
        fi
    else
        echo "0,0,0"
    fi
}

# Get detailed queue information from contract storage
# This requires reading the CoinJoin pool data structure
get_queue_details() {
    local denomination="$1"

    # This is a simplified version - in production you'd need to query contract storage
    # For now, we'll use the get_coinjoin_stats to get pool size
    local stats=$(stellar contract invoke \
        --id "$CONTRACT_ID" \
        --network "$NETWORK" \
        --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
        -- \
        get_coinjoin_stats \
        --denomination_symbol "{\"symbol\":\"$denomination\"}" 2>&1 | grep -o '\[.*\]')

    if [ -n "$stats" ]; then
        # Parse [pool_size, fees, wait_time]
        local pool_size=$(echo "$stats" | grep -o '^\[[0-9]*' | grep -o '[0-9]*')
        local fees=$(echo "$stats" | sed 's/\[//g' | sed 's/\]//g' | cut -d',' -f2)
        local wait_time=$(echo "$stats" | sed 's/\[//g' | sed 's/\]//g' | cut -d',' -f3)

        echo "$pool_size,$fees,$wait_time"
    else
        echo "0,0,0"
    fi
}

# Get real deposit details from contract
# Returns: min_amount_out,max_slippage_bps,expiry_timestamp,timestamp,fee_paid
get_real_deposit_details() {
    local denomination="$1"
    local index="$2"

    local details=$(stellar contract invoke \
        --id "$CONTRACT_ID" \
        --network "$NETWORK" \
        --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
        -- \
        get_deposit_details \
        --denomination_symbol "{\"symbol\":\"$denomination\"}" \
        --index "$index" 2>&1 | grep -o '\[.*\]')

    if [ -n "$details" ]; then
        # Parse ["min_amount_out","max_slippage_bps","expiry_timestamp","timestamp","fee_paid"]
        local clean=$(echo "$details" | sed 's/"//g' | sed 's/\[//g' | sed 's/\]//g')
        local min_amount_out=$(echo "$clean" | cut -d',' -f1)
        local max_slippage_bps=$(echo "$clean" | cut -d',' -f2)
        local expiry_timestamp=$(echo "$clean" | cut -d',' -f3)
        local timestamp=$(echo "$clean" | cut -d',' -f4)
        local fee_paid=$(echo "$clean" | cut -d',' -f5)

        echo "$min_amount_out,$max_slippage_bps,$expiry_timestamp,$timestamp,$fee_paid"
    else
        echo "0,0,0,0,0"
    fi
}

# Get batch contract token balances
get_batch_balances() {
    # Get pXLM balance
    local pxlm_balance=$(stellar contract invoke \
        --id "$PXLM_TOKEN" \
        --network "$NETWORK" \
        --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
        -- \
        balance \
        --id "$CONTRACT_ID" 2>&1 | grep -E "^[0-9]+" || echo "0")

    # Get XLM balance
    local xlm_balance=$(stellar contract invoke \
        --id "$XLM_TOKEN" \
        --network "$NETWORK" \
        --source "SBDOODPRSAAXLVHOHKR2QUY5Z2CFHNIPI7NJWR7CED5KXK7SEQMMH774" \
        -- \
        balance \
        --id "$CONTRACT_ID" 2>&1 | grep -E "^[0-9]+" || echo "0")

    echo "$xlm_balance,$pxlm_balance"
}

# Calculate average payout for all participants
calculate_average_payout() {
    local participant_count=$1
    local reserve0=$2
    local reserve1=$3
    local denomination_value=$4  # in stroops

    if [ "$participant_count" -eq 0 ] || [ "$reserve0" -eq 0 ]; then
        echo "0"
        return
    fi

    # Use bc for all calculations to avoid integer overflow
    # Total input = participant_count * denomination_value
    # amount_out = (amount_in * 997 * reserve_out) / (reserve_in * 1000 + amount_in * 997)
    local payout_xlm=$(echo "scale=4; \
        total_input = $participant_count * $denomination_value; \
        amount_in_with_fee = total_input * 997; \
        numerator = amount_in_with_fee * $reserve1; \
        denominator = $reserve0 * 1000 + amount_in_with_fee; \
        total_output = numerator / denominator; \
        payout_per_participant = total_output / $participant_count; \
        payout_per_participant / 10000000" | bc)

    echo "$payout_xlm"
}

# Display enhanced queue status with participant details
display_enhanced_queue() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}🔍 CoinJoin Monitor v2 - [$timestamp]${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Get pool info (reserves and exchange rate)
    local pool_info=$(get_pool_info "$XLM_PXLM_POOL")
    IFS=',' read -r reserve0 reserve1 exchange_rate <<< "$pool_info"

    # Get queue details for 100M denomination (10 XLM)
    local queue_details=$(get_queue_details "100")
    IFS=',' read -r pool_size fees wait_time <<< "$queue_details"

    # Display pool details
    echo -e "${BLUE}📊 Pool Details (10 XLM Denomination):${NC}"
    echo -e "${GRAY}─────────────────────────────────────────────────────────────${NC}"
    echo -e "  Pool Address: ${XLM_PXLM_POOL:0:8}...${XLM_PXLM_POOL: -8}"

    # Convert reserves to XLM
    local reserve0_xlm=$(echo "scale=2; $reserve0 / 10000000" | bc)
    local reserve1_xlm=$(echo "scale=2; $reserve1 / 10000000" | bc)

    echo -e "  Reserves: ${GREEN}$reserve0_xlm XLM${NC} : ${GREEN}$reserve1_xlm pXLM${NC}"

    # Calculate average payout for minimum participants (3)
    # This is what each would get when batch executes
    local avg_payout=$(calculate_average_payout "$MIN_PARTICIPANTS" "$reserve0" "$reserve1" "100000000")

    # Calculate 10 XLM exchange rate
    local ten_xlm_rate=$(echo "scale=6; 10 * $exchange_rate" | bc)

    echo -e "  Exchange Rate: ${YELLOW}1 XLM = $exchange_rate pXLM${NC}"
    echo -e "  Exchange Rate: ${YELLOW}10 XLM = $ten_xlm_rate pXLM${NC}"
    echo -e "  ${MAGENTA}💰 Expected Payout each (when $MIN_PARTICIPANTS qualify): ${GREEN}~$avg_payout pXLM${NC}"
    echo ""

    # Display batch contract status
    echo -e "${BLUE}💼 Batch Contract Status:${NC}"
    echo -e "${GRAY}─────────────────────────────────────────────────────────────${NC}"
    echo -e "  Contract: ${CONTRACT_ID:0:8}...${CONTRACT_ID: -8}"

    # Get batch balances
    local batch_balances=$(get_batch_balances)
    IFS=',' read -r xlm_bal pxlm_bal <<< "$batch_balances"
    local xlm_bal_display=$(echo "scale=4; $xlm_bal / 10000000" | bc)
    local pxlm_bal_display=$(echo "scale=4; $pxlm_bal / 10000000" | bc)

    echo -e "  Holdings: ${GREEN}$xlm_bal_display XLM${NC} | ${GREEN}$pxlm_bal_display pXLM${NC}"

    # Detect pool changes (swap activity)
    if [ "$previous_reserve0" -ne 0 ]; then
        local reserve_change0=$((reserve0 - previous_reserve0))
        local reserve_change1=$((reserve1 - previous_reserve1))

        if [ "$reserve_change0" -ne 0 ] || [ "$reserve_change1" -ne 0 ]; then
            local change0_xlm=$(echo "scale=2; $reserve_change0 / 10000000" | bc)
            local change1_xlm=$(echo "scale=2; $reserve_change1 / 10000000" | bc)

            if [ "$reserve_change0" -gt 0 ]; then
                echo -e "  ${YELLOW}📈 Recent Activity: +$change0_xlm XLM, $change1_xlm pXLM${NC}"
                last_swap_detected=$(date '+%H:%M:%S')
            fi
        fi
    fi

    if [ -n "$last_swap_detected" ]; then
        echo -e "  Last swap detected: ${CYAN}$last_swap_detected${NC}"
    fi

    # Update previous reserves for next check
    previous_reserve0=$reserve0
    previous_reserve1=$reserve1
    echo ""

    # Display participant queue
    echo -e "${YELLOW}👥 Participant Queue:${NC}"
    echo -e "${GRAY}─────────────────────────────────────────────────────────────${NC}"

    # Initialize qualifying count
    local qualifying_count=0

    if [ "$pool_size" -eq 0 ]; then
        echo -e "  ${GRAY}No participants in queue${NC}"
        echo ""
    else
        # Note: In a real implementation, we would query contract storage for each deposit
        # For now, we'll calculate what we can from the expected payout
        echo -e "${CYAN}  #  | %  | Amt    | xR   | ? | Exp ${NC}"
        echo -e "${GRAY}  ───┼────┼────────┼──────┼───┼─────${NC}"

        # Get expected payout for MINIMUM participants (not all in queue)
        # This is what each would get if minimum participants execute
        local avg_payout=$(calculate_average_payout "$MIN_PARTICIPANTS" "$reserve0" "$reserve1" "100000000")

        # Query real deposit details from contract
        for i in $(seq 1 $pool_size); do
            local index=$((i - 1))  # Contract uses 0-based indexing

            # Get real deposit details from contract
            local deposit_details=$(get_real_deposit_details "100" "$index")
            IFS=',' read -r min_amount_out_stroops max_slippage_bps expiry_timestamp timestamp fee_paid <<< "$deposit_details"

            # Convert min_amount_out to XLM
            local min_amount=$(echo "scale=4; $min_amount_out_stroops / 10000000" | bc)

            # Convert slippage from basis points to percentage
            local slippage=$(echo "scale=2; $max_slippage_bps / 100" | bc)

            # Check if this participant would qualify
            local qualifies
            local color
            if (( $(echo "$avg_payout >= $min_amount" | bc -l) )); then
                qualifies="✓"
                color=$GREEN
                qualifying_count=$((qualifying_count + 1))
            else
                qualifies="✗"
                color=$RED
            fi

            # Calculate time until expiry in minutes
            local current_time=$(date +%s)
            local time_until_expiry=$((expiry_timestamp - current_time))
            local expiry_display
            if [ "$time_until_expiry" -gt 0 ]; then
                local minutes=$((time_until_expiry / 60))
                expiry_display="${minutes}"
            else
                expiry_display="EXP"
            fi

            # Calculate expected output for 10 XLM at deposit time (reverse from min_amount)
            # expected_output = min_amount / (1 - slippage%)
            local slippage_decimal=$(echo "scale=6; $max_slippage_bps / 10000" | bc)
            local expected_output=$(echo "scale=4; $min_amount / (1 - $slippage_decimal)" | bc)

            echo -e "  ${color}$i  | $slippage | $min_amount | $expected_output | $qualifies | $expiry_display${NC}"
        done

        echo -e "\n${GRAY}Legend: % = Max slippage (bps/100) | Amt = Min pXLM required | xR = Expected pXLM for 10 XLM | Exp = Minutes until expiry (48h = 2880 min)${NC}\n"
    fi

    # Calculate qualifying participants based on above loop
    # (qualifier count is set in the loop above)

    # Display queue status
    echo -e "${CYAN}📈 Queue Status:${NC}"
    echo -e "${GRAY}─────────────────────────────────────────────────────────────${NC}"

    # Determine status based on qualifying participants
    if [ "$qualifying_count" -ge "$MIN_PARTICIPANTS" ]; then
        local percentage=$((qualifying_count * 100 / MIN_PARTICIPANTS))
        if [ "$percentage" -gt 100 ]; then
            percentage=100
        fi

        # Create progress bar
        local bar_width=20
        local filled=$((qualifying_count * bar_width / MIN_PARTICIPANTS))
        if [ "$filled" -gt "$bar_width" ]; then
            filled=$bar_width
        fi
        local empty=$((bar_width - filled))
        local filled_bar=$(printf "%*s" $filled | tr ' ' '█')
        local empty_bar=$(printf "%*s" $empty | tr ' ' '░')

        echo -e "  Batch Queue: ${GREEN}$qualifying_count/$MIN_PARTICIPANTS${NC} qualifying participants"
        echo -e "  Status: ${GREEN}READY FOR MIXING${NC}"
        echo -e "  Progress: [${GREEN}${filled_bar}${GRAY}${empty_bar}${NC}] ${GREEN}${percentage}%${NC}"
        echo ""
        echo -e "${MAGENTA}  🎯 Pool is ready! Next deposit will trigger execution.${NC}"
    else
        # Base percentage on qualifying count, not total pool size
        local percentage=$((qualifying_count * 100 / MIN_PARTICIPANTS))
        local bar_width=20
        local filled=$((qualifying_count * bar_width / MIN_PARTICIPANTS))
        local empty=$((bar_width - filled))
        local filled_bar=$(printf "%*s" $filled | tr ' ' '█')
        local empty_bar=$(printf "%*s" $empty | tr ' ' '░')

        echo -e "  Batch Queue: ${YELLOW}$qualifying_count/$MIN_PARTICIPANTS${NC} qualifying participants"
        echo -e "  Total in queue: ${YELLOW}$pool_size${NC}"
        echo -e "  Status: ${YELLOW}WAITING FOR PARTICIPANTS${NC}"
        echo -e "  Progress: [${YELLOW}${filled_bar}${GRAY}${empty_bar}${NC}] ${YELLOW}${percentage}%${NC}"

        local needed=$((MIN_PARTICIPANTS - qualifying_count))
        echo ""
        echo -e "${YELLOW}  ⏳ Need $needed more qualifying participant(s)${NC}"
    fi

    echo ""
    echo -e "${GRAY}CoinJoin enabled: ${GREEN}true${NC}"
    echo -e "${GRAY}Fee: ${GREEN}0.1%${NC} (10 basis points)"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# Test current queue status (one-time check)
test_queue() {
    echo -e "${CYAN}🧪 Testing Current Queue Status:${NC}"
    echo ""
    display_enhanced_queue
}

# Main monitoring loop
monitor_loop() {
    echo -e "${CYAN}🚀 Starting SoroSwap CoinJoin Monitor v2${NC}"
    echo -e "${BLUE}Contract: $CONTRACT_ID${NC}"
    echo -e "${BLUE}Network: $NETWORK${NC}"
    echo -e "${BLUE}Check Interval: ${CHECK_INTERVAL}s${NC}"
    echo ""

    log_message "CoinJoin monitor v2 started"

    # Show initial status
    display_enhanced_queue

    while true; do
        sleep "$CHECK_INTERVAL"
        clear
        display_enhanced_queue
    done
}

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Stopping monitor...${NC}"
    log_message "CoinJoin monitor v2 stopped"
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
    "--help"|"help"|"-h")
        echo "SoroSwap CoinJoin Monitor (v2)"
        echo ""
        echo "Enhanced monitor with detailed participant information"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  monitor        Start monitoring (default)"
        echo "  test           Check current queue status once"
        echo "  --help         Show this help message"
        echo ""
        echo "Features:"
        echo "  • Real-time pool reserves and exchange rates"
        echo "  • Detailed participant queue table"
        echo "  • Slippage and expiry tracking (when available)"
        echo "  • Average payout calculations"
        echo "  • Qualifying participant counts"
        echo ""
        echo "Note: Full participant details require contract storage queries"
        echo "      Current version shows estimated values for demonstration"
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Use '$0 --help' for usage information"
        exit 1
        ;;
esac
