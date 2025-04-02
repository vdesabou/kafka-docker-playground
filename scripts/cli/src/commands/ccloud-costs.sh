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

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

INPUT_FILE="$tmp_dir/out.log"

log "💰 Retrieve ccloud costs for a range from $start_date to $end_date "
confluent billing cost list --start-date "$start_date" --end-date "$end_date" --output json > $INPUT_FILE
if [[ $? -ne 0 ]]
then
    logerror "❌ Failed to retrieve ccloud costs with command: confluent billing cost list --start-date $start_date --end-date $end_date --output json"
    cat "$INPUT_FILE"
    exit 1
fi

log "💰 costs retrieved successfully. Processing costs from JSON..."

display_histogram() {
    local file=$1
    local title=$2

    total_cost_local=$(awk '{sum += $2} END {print sum}' $file)
    echo ""
    echo "$title"
    echo "---------------------------------"
    echo "TOTAL COST $file: 💰 $total_cost_local"
    echo "---------------------------------"

    # Find the maximum value in the dataset
    max_value=$(awk '{if ($2 > max) max = $2} END {print max}' "$file")

    while read -r line; do
    label=$(echo "$line" | awk '{print $1}')
    value=$(echo "$line" | awk '{print $2}')
    # Calculate the proportion of the value relative to the maximum value
    proportion=$(echo "scale=2; $value / $max_value * 50" | bc) # Scale to a maximum of 20 emojis with precision
    bar=$(printf '💰%.0s' $(seq 1 ${proportion%.*})) # Generate the bar based on the integer part of the proportion
    printf "%-20s | %s (%.2f)\n" "$label" "$bar" "$value"
    done < "$file"
    echo ""
}

jq -r '.[] | "\(.product) \(.amount | sub("\\$"; ""; "g") | tonumber)"' "$INPUT_FILE" | \
awk '{sum[$1] += $2} END {for (product in sum) print product, sum[product]}' | sort -k2 -n > $tmp_dir/product_costs.txt

jq -r '.[] | "\(.resource_name) \(.amount | sub("\\$"; ""; "g") | tonumber)"' "$INPUT_FILE" | \
awk '{sum[$1] += $2} END {for (resource in sum) print resource, sum[resource]}' | sort -k2 -n > $tmp_dir/resource_costs.txt

jq -r '.[] | "\(.environment) \(.amount | sub("\\$"; ""; "g") | tonumber)"' "$INPUT_FILE" | \
awk '{sum[$1] += $2} END {for (env in sum) print env, sum[env]}' | sort -k2 -n > $tmp_dir/environment_costs.txt

# Calculate and display the total cost across all products
total_cost=$(awk '{sum += $2} END {print sum}' $tmp_dir/product_costs.txt)
echo "---------------------------------"
echo "TOTAL COST ACROSS ALL PRODUCTS: 💰 $total_cost"
echo "---------------------------------"

# Display histograms
display_histogram "$tmp_dir/product_costs.txt" "Histogram: Total Cost per Product"

display_histogram "$tmp_dir/resource_costs.txt" "Histogram: Total Cost per Resource"

display_histogram "$tmp_dir/environment_costs.txt" "Histogram: Total Cost per Environment"
