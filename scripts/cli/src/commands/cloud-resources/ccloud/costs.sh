start_date="${args[--start-date]}"
end_date="${args[--end-date]}"
display_only_total_cost="${args[--display-only-total-cost]}"
raw_output_file="${args[--raw-output-file]}"
output_dir="${args[--output-dir]}"
no_open="${args[--no-open]}"
no_report="${args[--no-report]}"
sample="${args[--sample]}"

if [[ -n "$sample" ]]
then
    # last month of the dummy billing data, in the same format as the file saved below
    sample_file=$(ls "$root_folder/tools/cloud-costs/samples/$sample/"*_*.json | sort | tail -1)
    log "🧪 writing the HTML report from the dummy billing data of tools/cloud-costs/samples/$sample/$(basename "$sample_file")"
    write_ccloud_costs_range_report "$sample_file" "$output_dir" "$no_open" "${USER}"
    exit $?
fi

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

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# named <start date>_<end date>.json for the HTML report
INPUT_FILE="$tmp_dir/${start_date}_${end_date}.json"

if [[ ! -n "$display_only_total_cost" ]]
then
    log "💰 Retrieve ccloud costs for a range from $start_date to $end_date "
fi
confluent billing cost list --start-date "$start_date" --end-date "$end_date" --output json > $INPUT_FILE
if [[ $? -ne 0 ]]
then
    logerror "❌ failed to retrieve ccloud costs with command: confluent billing cost list --start-date $start_date --end-date $end_date"
    cat "$INPUT_FILE"
    exit 1
fi
if [[ -n "$raw_output_file" ]]
then
    cp "$INPUT_FILE" "$raw_output_file"
fi
if [[ ! -n "$display_only_total_cost" ]]
then
    log "⏳ costs retrieved successfully. processing results..."
fi

display_histogram() {
    local file=$1

    total_cost_local=$(awk '{sum += $2} END {print sum}' $file)
    echo ""
    echo "---------------------------------"
    echo "TOTAL COST: 💰 \$$total_cost_local"
    echo "---------------------------------"

    while read -r line; do
        resource_name=$(echo "$line" | awk '{print $1}')
        cost=$(echo "$line" | awk '{print $2}')
        resource=$(echo "$line" | awk '{print $3}')
        # proportion=$(echo "scale=1; $cost / $total_cost_local * 100" | bc) # Calculate percentage
        # bar=$(printf '💰%.0s' $(seq 1 ${proportion%.*})) # Generate the bar based on the integer part of the proportion
        
        # calculate the percentage of cost
        if [[ "$total_cost_local" == "0" ]]; then
            percentage=0
        else
            percentage=$(echo "scale=2; 100 * $cost / $total_cost_local" | bc)
        fi
        inverse_percentage=$(echo "100 - $percentage" | bc)

        # create the cost bar
        bar_length=50
        filled_length=$(echo "$inverse_percentage * $bar_length / 100" | bc)
        empty_length=$((bar_length - filled_length))
        bar=$(printf "%${empty_length}s" | tr ' ' '💰')
        bar+=$(printf "%${filled_length}s" | tr ' ' '⬛')

        resource_no_comma=$(echo "${resource//,/}")
        printf "%-50s (%s) | %s $%.2f (%.2f%%)\n" "$resource_name" "$resource_no_comma" "$bar" "$cost" "$percentage"

    done < "$file"
    echo ""
}

jq -r '.[] | "\(.product) \(.amount | sub("\\$"; ""; "g") | tonumber)"' "$INPUT_FILE" | \
awk '{sum[$1] += $2} END {for (product in sum) print product, sum[product]}' | sort -k2 -nr > $tmp_dir/product_costs.txt

# Calculate and display the total cost across all products
total_cost=$(awk '{sum += $2} END {print sum}' $tmp_dir/product_costs.txt)

if [[ -n "$display_only_total_cost" ]]
then
    echo "$total_cost"
    exit 0
fi
echo "---------------------------------"
echo "TOTAL COST ACROSS ALL PRODUCTS: 💰 $total_cost"
echo "---------------------------------"

while read -r line
do
    product=$(echo "$line" | awk '{print $1}')
    log "👛 $(echo "$product" | tr '[:upper:]' '[:lower:]') product costs"
    TMP_FILE="$tmp_dir/product_costs_$product.txt"
    jq -r '.[] | select(.product == "'"$product"'") | "\(.resource_name) \(.amount | sub("\\$"; ""; "g") | tonumber) \(.resource)"' "$INPUT_FILE" | \
    awk '{sum[$1] += $2; resources[$1] = (resources[$1] ? resources[$1] ", " : "") $3} END {for (resource in sum) print resource, sum[resource], resources[resource]}' | sort -k2 -nr > "$TMP_FILE"
    display_histogram "$TMP_FILE"
done < $tmp_dir/product_costs.txt

jq -r '.[] | "\(.environment) \(.amount | sub("\\$"; ""; "g") | tonumber)"' "$INPUT_FILE" | \
awk '{sum[$1] += $2} END {for (env in sum) print env, sum[env]}' | sort -k2 -nr > $tmp_dir/environment_costs.txt

log "👛 environment costs"
display_histogram "$tmp_dir/environment_costs.txt"

if [[ ! -n "$no_report" ]]
then
    write_ccloud_costs_range_report "$INPUT_FILE" "$output_dir" "$no_open" "${USER}"
fi
