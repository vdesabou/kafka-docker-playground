user="${args[--user]}"
display_only_total_cost="${args[--display-only-total-cost]}"
start_date="${args[--start-date]}"
end_date="${args[--end-date]}"

if [[ ! -n "$start_date" ]]
then
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        start_date=$(date -v-1m +%Y-%m-%d)
    else
        start_date=$(date -d "1 month ago" +%Y-%m-%d)
    fi

    if [[ ! -n "$end_date" ]]
    then
        if [[ "$OSTYPE" == "darwin"* ]]
        then
            end_date=$(date -v-3d +%Y-%m-%d)
        else
            end_date=$(date -d "3 days ago" +%Y-%m-%d)
        fi
    fi
else
    # start_date is set
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        # macOS: Check if the date is more than one year ago
        if [[ $(date -j -f "%Y-%m-%d" "$start_date" +%s) -lt $(date -v-1y +%s) ]]
        then
            logerror "start_date must be less than one year old"
            return 1
        fi
    else
        # Linux: Check if the date is more than one year ago
        if [[ $(date -d "$start_date" +%s) -lt $(date -d "1 year ago" +%s) ]]
        then
            logerror "start_date must be less than one year old"
            return 1
        fi
    fi

    if [[ ! -n "$end_date" ]]
    then
        if [[ "$OSTYPE" == "darwin"* ]]
        then
            #end_date set with start_date +30 days
            end_date=$(date -v+30d -j -f "%Y-%m-%d" "$start_date" +%Y-%m-%d)
        else
            #end_date set with start_date +30 days
            end_date=$(date -d "$start_date +30 days" +%Y-%m-%d)
        fi
    fi
fi

if [[ ! -n "$user" ]]
then
    user="${USER}"
fi

if [[ ! -n "$display_only_total_cost" ]]
then
    login_and_maybe_set_azure_subscription
else
    login_and_maybe_set_azure_subscription > /dev/null 2>&1
fi  

# Use /tmp so Dockerized az CLI can access files on macOS
tmp_dir=$(mktemp -d /tmp/pg-azure-costs-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

display_histogram() {
    local file=$1

    local total_cost_local=$(awk -F $'\t' '{sum += $2} END {print sum+0}' "$file")

    if [[ -n "$display_only_total_cost" ]]
    then
        printf "%.2f" $total_cost_local
        return
    fi
    echo ""
    echo "---------------------------------"
    printf "TOTAL COST: 💰 \$%.2f\n" "$total_cost_local"
    echo "---------------------------------"

    while IFS=$'\t' read -r resource_name cost resource; do
            resource_name=${resource_name:-unknown}
            cost=${cost:-0}
            resource=${resource:-$resource_name}

            if (( $(echo "$cost <= 0" | bc -l) )); then
                    continue
            fi

            if (( $(echo "$total_cost_local == 0" | bc -l) )); then
                    percentage=0
            else
                    percentage=$(echo "scale=2; 100 * $cost / $total_cost_local" | bc -l)
            fi

            if (( $(echo "$percentage < 0" | bc -l) )); then
                    percentage=0
            fi
            if (( $(echo "$percentage > 100" | bc -l) )); then
                    percentage=100
            fi

            inverse_percentage=$(echo "scale=2; 100 - $percentage" | bc -l)

            bar_length=50
            filled_length=$(echo "scale=0; $inverse_percentage * $bar_length / 100" | bc -l)
            empty_length=$((bar_length - filled_length))
            bar=$(printf "%${empty_length}s" | tr ' ' '💰')
            bar+=$(printf "%${filled_length}s" | tr ' ' '⬛')

            resource_no_comma=$(echo "${resource//,/}")
            printf "%-50s (%s) | %s $%.2f (%.2f%%)\n" "$resource_name" "$resource_no_comma" "$bar" "$cost" "$percentage"

    done < "$file"
    echo ""
}

sub_id=$(az account show --query id -o tsv 2>/dev/null)
if [[ -z "$sub_id" ]]; then
    logerror "Unable to determine Azure subscription ID. Please login with 'az login'."
    exit 1
fi

if [[ ! -n "$display_only_total_cost" ]]
then
    log "📊 Fetching Azure costs for resources tagged cflt_managed_id=$user from $start_date to $end_date"
    log ""
fi 

# Build Cost Management query definition
DEF_FILE="$tmp_dir/definition.json"
cat > "$DEF_FILE" << JSON
{
    "type": "Usage",
    "timeframe": "Custom",
    "timePeriod": {
        "from": "${start_date}T00:00:00Z",
        "to": "${end_date}T00:00:00Z"
    },
    "dataset": {
        "granularity": "Monthly",
        "aggregation": {
            "totalCost": { "name": "Cost", "function": "Sum" }
        },
        "grouping": [ { "type": "Dimension", "name": "ServiceName" } ],
        "filter": {
            "and": [
                { "tags": { "name": "cflt_managed_id", "operator": "In", "values": ["${user}"] } },
                { "tags": { "name": "cflt_managed_by", "operator": "In", "values": ["user"] } }
            ]
        }
    }
}
JSON

OUT_JSON="$tmp_dir/out.json"
run_cost_query() {
    local scope="$1"; local def="$2"; local out="$3"
    local url="https://management.azure.com${scope}/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
    az rest --method post --url "$url" --headers "Content-Type=application/json" --headers "Accept=application/json" --body @"$def" --output json > "$out" 2>/dev/null || true
    # Success if JSON contains properties.rows or properties.columns (both indicate valid Cost Management response)
    if jq -e '.properties.rows' "$out" >/dev/null 2>&1 || jq -e '.properties.columns' "$out" >/dev/null 2>&1; then
        return 0
    fi
    if [ ! -z "$PG_VERBOSE_MODE" ]; then
        log "❌ Azure cost query output did not contain expected fields; showing response:"
        cat "$out"
    fi
    return 1
}

OUT_JSON="$tmp_dir/out.json"
if ! run_cost_query "/subscriptions/$sub_id" "$DEF_FILE" "$OUT_JSON"; then
    logerror "Failed to run Azure cost query even via REST."
    exit 1
fi

if [[ ! -n "$display_only_total_cost" ]]
then
    log "💰 Overall costs by service:"
fi 

HIST_FILE="$tmp_dir/azure_service_costs.txt"

# Azure Cost Management returns columns and rows; find the column for ServiceName and Cost
svc_idx=$(jq -r '.properties.columns | to_entries | map(select(.value.name=="ServiceName")) | .[0].key' "$OUT_JSON")
cost_idx=$(jq -r '.properties.columns | to_entries | map(select(.value.name=="Cost")) | .[0].key' "$OUT_JSON")

if [[ -z "$svc_idx" || -z "$cost_idx" || "$svc_idx" == "null" || "$cost_idx" == "null" ]]; then
    logerror "Unexpected Azure cost query format."
    cat "$OUT_JSON"
    exit 1
fi

# Aggregate by service across months
jq -r --argjson si "$svc_idx" --argjson ci "$cost_idx" '.properties.rows | map({svc: .[$si], cost: (.[$ci] // 0)}) | group_by(.svc) | map({service: .[0].svc, total: (map(.cost | tonumber) | add)}) | sort_by(-.total) | .[] | select(.total != 0) | "\(.service)\t\(.total)\t\(.service)"' "$OUT_JSON" > "$HIST_FILE"


display_histogram "$HIST_FILE"