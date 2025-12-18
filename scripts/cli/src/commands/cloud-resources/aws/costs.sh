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
    handle_aws_credentials
else
    handle_aws_credentials > /dev/null 2>&1
fi  

# temp dir for intermediate files (histogram input)
tmp_dir=$(mktemp -d -t pg-aws-costs-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

display_histogram() {
    local file=$1

    total_cost_local=$(awk -F '\t' '{sum += $2} END {print sum+0}' "$file")
    echo ""
    echo "---------------------------------"
    printf "TOTAL COST: 💰 $%.2f\n" "$total_cost_local"
    echo "---------------------------------"

    while IFS=$'\t' read -r resource_name cost resource; do
        # default values if missing
        resource_name=${resource_name:-unknown}
        cost=${cost:-0}
        resource=${resource:-$resource_name}
        
        # Skip zero-cost entries
        if (( $(echo "$cost <= 0" | bc -l) )); then
            continue
        fi

        if (( $(echo "$total_cost_local == 0" | bc -l) )); then
            percentage=0
        else
            percentage=$(echo "scale=2; 100 * $cost / $total_cost_local" | bc -l)
        fi
        
        # Clamp percentage to [0, 100] to avoid display issues
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

if [[ ! -n "$display_only_total_cost" ]]
then
    log "📊 Fetching AWS costs for resources tagged with cflt_managed_id=$user from $start_date to $end_date"
    log ""
fi

# Get costs grouped by service for resources with cflt_managed_id tag matching user

if [[ ! -n "$display_only_total_cost" ]]
then
    log "💰 Overall costs by service:"
fi
cost_data=$(aws ce get-cost-and-usage \
    --time-period Start=$start_date,End=$end_date \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{
        "Tags": {
            "Key": "cflt_managed_id",
            "Values": ["'"$user"'"]
        }
    }' \
    --region us-east-1 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$cost_data" ]; then
    # Build histogram input file: "Service total Service"
    HIST_FILE="$tmp_dir/aws_service_costs.txt"
    echo "$cost_data" | jq -r '[.ResultsByTime[].Groups[]] | group_by(.Keys[0]) | map({service: .[0].Keys[0], total: (map(.Metrics.UnblendedCost.Amount | tonumber) | add)}) | sort_by(-.total) | .[] | select(.total != 0) | "\(.service)\t\(.total)\t\(.service)"' > "$HIST_FILE"

    if [[ ! -n "$display_only_total_cost" ]]
    then
        log "👛 service costs"

        display_histogram "$HIST_FILE"
    fi

    # Calculate total
    total_cost=$(awk -F '\t' '{sum += $2} END {print sum+0}' "$HIST_FILE")

    if [[ -n "$display_only_total_cost" ]]
    then
        printf "%.2f" $total_cost
        exit 0
    else
        log "  Total: \$$(printf "%.2f" $total_cost) USD"
    fi

else
    logerror "Failed to retrieve cost data. Make sure you have:"
    logerror "  1. AWS Cost Explorer access enabled"
    logerror "  2. Resources tagged with Key=cflt_managed_id, Value=$user"
fi

if [[ ! -n "$display_only_total_cost" ]]
then
    log ""
    log "💡 Note: AWS Cost Explorer may have a 24-48 hour delay in reporting costs."
fi