detailed="${args[--detailed]}"

if [[ "$OSTYPE" == "darwin"* ]]
then
    start_date=$(date -v-1y +%Y-%m-%d) # macOS: 1 year ago
else
    start_date=$(date -d "1 year ago" +%Y-%m-%d) # Linux: 1 year ago
fi

# add one day
if [[ "$OSTYPE" == "darwin"* ]]
then
    start_date=$(date -v+1d -j -f "%Y-%m-%d" "$start_date" +%Y-%m-%d) # macOS: Add 1 day
else
    start_date=$(date -d "$start_date +1 day" +%Y-%m-%d) # Linux: Add 1 day
fi

current_date="$start_date"

maybe_display_only_total_cost="--display-only-total-cost"
if [[ -n "$detailed" ]]
then
    maybe_display_only_total_cost=""
fi

while true; do
    if [[ "$OSTYPE" == "darwin"* ]]; then
        end_date=$(date -j -v+1m -f "%Y-%m-%d" "$current_date" +%Y-%m-%d) # macOS: Add 1 month
    else
        end_date=$(date -d "$current_date +1 month" +%Y-%m-%d) # Linux: Add 1 month
    fi

    # Break the loop if end_date is in the future
    if [[ "$end_date" > "$(date +%Y-%m-%d)" ]]; then
        end_date=$(date +%Y-%m-%d) # Set end_date to today
        log "📅 costs from $current_date to $end_date"
        playground ccloud-costs --start-date "$current_date" --end-date "$end_date" $maybe_display_only_total_cost
        break
    fi

    # Call playground ccloud-costs for the current range
    log "📅 costs from $current_date to $end_date"
    playground ccloud-costs --start-date "$current_date" --end-date "$end_date" $maybe_display_only_total_cost

    # Move to the next range
    current_date="$end_date"
done