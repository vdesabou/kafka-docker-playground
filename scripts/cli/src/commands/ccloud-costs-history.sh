detailed="${args[--detailed]}"
output_dir="${args[--output-dir]}"
no_open="${args[--no-open]}"
sample="${args[--sample]}"

if [[ -n "$sample" ]]
then
    # dummy billing data, in the same format as the monthly files saved below
    log "🧪 writing the HTML report from the dummy billing data of tools/cloud-costs/samples/$sample"
    write_cloud_costs_report "ccloud" "$root_folder/tools/cloud-costs/samples/$sample" "$output_dir" "$no_open" "${USER}"
    exit $?
fi

# raw cost API response of each month, for the HTML report
data_dir=$(mktemp -d -t pg-ccloud-costs-history-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $data_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $data_dir"
fi

if [[ "$OSTYPE" == "darwin"* ]]
then
    start_date=$(date -v-1y +%Y-%m-%d) # macOS: 1 year ago
else
    start_date=$(date -d "1 year ago" +%Y-%m-%d) # Linux: 1 year ago
fi

# Add one day
if [[ "$OSTYPE" == "darwin"* ]]
then
    start_date=$(date -v+1d -j -f "%Y-%m-%d" "$start_date" +%Y-%m-%d) # macOS: Add 1 day
else
    start_date=$(date -d "$start_date +1 day" +%Y-%m-%d) # Linux: Add 1 day
fi

current_date="$start_date"

# Function to display histograms
display_histogram() {
    local label=$1
    local value=$2
    local bar=$(printf '💰%.0s' $(seq 1 $(echo "$value / 10" | bc))) # Each 💰 represents $10
    printf "%-20s | %s $%.2f\n" "$label" "$bar" "$value"
}

readable_date () {
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        date -j -f "%Y-%m-%d" "$1" +"%b %d, %Y"
    else
        date -d "$1" +"%b %d, %Y"
    fi
}
# Collect costs and display histograms
while true; do
    # the previous period ended today (same day of the month as the start date): nothing left, an empty period fails
    if [[ ! "$current_date" < "$(date +%Y-%m-%d)" ]]; then
        break
    fi
    if [[ "$OSTYPE" == "darwin"* ]]; then
        end_date=$(date -j -v+1m -f "%Y-%m-%d" "$current_date" +%Y-%m-%d) # macOS: Add 1 month
    else
        end_date=$(date -d "$current_date +1 month" +%Y-%m-%d) # Linux: Add 1 month
    fi

    # Break the loop if end_date is in the future
    if [[ "$end_date" > "$(date +%Y-%m-%d)" ]]; then
        end_date=$(date +%Y-%m-%d) # Set end_date to today
        cost=$(playground  --output-level ERROR ccloud-costs --start-date "$current_date" --end-date "$end_date" --display-only-total-cost --raw-output-file "$data_dir/${current_date}_${end_date}.json")
        display_histogram "$(readable_date $current_date) to $(readable_date $end_date)" "$cost"
        if [[ -n "$detailed" ]]
        then
            playground  --output-level ERROR ccloud-costs --start-date "$current_date" --end-date "$end_date" 
        fi
        break
    fi

    # Call playground  --output-level ERROR ccloud-costs for the current range
    cost=$(playground  --output-level ERROR ccloud-costs --start-date "$current_date" --end-date "$end_date" --display-only-total-cost --raw-output-file "$data_dir/${current_date}_${end_date}.json")
    display_histogram "$(readable_date $current_date) to $(readable_date $end_date)" "$cost"

    if [[ -n "$detailed" ]]
    then
        playground  --output-level ERROR ccloud-costs --start-date "$current_date" --end-date "$end_date" 
    fi

    # Move to the next range
    current_date="$end_date"
done

write_cloud_costs_report "ccloud" "$data_dir" "$output_dir" "$no_open" "${USER}"
