# Convert the space delimited string to an array
eval "resources=(${args[--resource]})"
threshold="${args[--threshold]}"
days="${args[--days]}"
scheduled="${args[--scheduled]}"
user="${USER}"

if [ "$days" -lt 1 ] || [ "$days" -gt 31 ]
then
    # the Confluent Cloud billing API takes one month at most
    logerror "❌ --days $days must be between 1 and 31"
    exit 1
fi
if [ "$threshold" -lt 0 ]
then
    logerror "❌ --threshold $threshold must be 0 or more"
    exit 1
fi

if [[ "$OSTYPE" == "darwin"* ]]
then
    start_date=$(date -v-"${days}"d +%Y-%m-%d)
else
    start_date=$(date -d "$days days ago" +%Y-%m-%d)
fi
end_date=$(date +%Y-%m-%d)

tmp_dir=$(mktemp -d -t pg-cost-reminder-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

if [[ -n "$scheduled" ]]
then
    log "💸 cost reminder of $(date '+%Y-%m-%d %H:%M') for $user: ${resources[*]}, $start_date → $end_date, threshold \$$threshold"
else
    log "💸 cost of your resources from $start_date to $end_date (billing lags: the last days can be incomplete), and what still runs for you: ${resources[*]}"
fi

total="0"
parts=()        # one short text per cloud, for the notification
running=()      # what still runs and bills by the hour, for the notification
skipped=()

add_cost () {
    total=$(awk -v a="$total" -v b="$1" 'BEGIN { printf "%.2f", a + b }')
}

for resource in "${resources[@]}"
do
    case "$resource" in
        ccloud)
            if ! command -v confluent > /dev/null 2>&1
            then
                logwarn "⏭️ skipping ccloud: the confluent CLI is not installed"
                skipped+=("ccloud")
                continue
            fi
            bill="$tmp_dir/ccloud-billing.json"
            if ! confluent billing cost list --start-date "$start_date" --end-date "$end_date" --output json > "$bill" 2> "$tmp_dir/ccloud-billing.err" || ! jq -e 'type == "array"' "$bill" > /dev/null 2>&1
            then
                logwarn "⏭️ ccloud cost not available: $(head -c 300 "$tmp_dir/ccloud-billing.err" | tr '\n' ' ')(logged out? run: confluent login --save; reading the billing needs a role on the organization)"
                skipped+=("ccloud cost")
            else
                # your resources, by name: connectors <TYPE>_<user>, clusters and environments pg-<user>-*
                yours=$(jq -r --arg u "$user" '[.[] | select((.resource_name // "") | (endswith("_" + $u) or startswith("pg-" + $u))) | .amount | sub("[$,]"; ""; "g") | tonumber] | add // 0 | . * 100 | round / 100' "$bill")
                org=$(jq -r '[.[] | .amount | sub("[$,]"; ""; "g") | tonumber] | add // 0 | . * 100 | round / 100' "$bill")
                log "💰 ccloud: \$$yours for your resources (organization: \$$org)"
                jq -r --arg u "$user" '[.[] | select((.resource_name // "") | (endswith("_" + $u) or startswith("pg-" + $u))) | {n: .resource_name, p: .product, a: (.amount | sub("[$,]"; ""; "g") | tonumber)}]
                    | group_by(.n) | map({n: .[0].n, p: .[0].p, a: (map(.a) | add)}) | sort_by(-.a) | .[] | select(.a >= 0.01)
                    | "     \(.p | ascii_downcase)\t\(.n)\t$\(.a * 100 | round / 100)"' "$bill" | column -t -s $'\t'
                add_cost "$yours"
                parts+=("ccloud \$$yours")
            fi
            list="$tmp_dir/ccloud-list.json"
            if playground --output-level ERROR cloud-resources ccloud list --json > "$list" 2> /dev/null && jq -e . "$list" > /dev/null 2>&1
            then
                nb_connectors=$(jq '.connectors | length' "$list")
                nb_running=$(jq '[.connectors[] | select(.status == "RUNNING")] | length' "$list")
                clusters=$(jq -r '[.clusters[].name] | join(", ")' "$list")
                log "🤖 ccloud: $nb_connectors connector(s) named *_$user ($nb_running RUNNING), $(jq '.clusters | length' "$list") cluster(s) pg-$user-*${clusters:+ ($clusters)}, $(jq '.environments | length' "$list") environment(s) pg-$user*"
                jq -r '.connectors[] | "     \(.status)\t\(.name)\t\(.cluster_name // .cluster // "")"' "$list" | column -t -s $'\t'
                if [ "$nb_running" -gt 0 ]
                then
                    running+=("$nb_running ccloud connector(s) RUNNING")
                fi
            else
                logwarn "⏭️ ccloud: could not list what still runs (playground cloud-resources ccloud list)"
                skipped+=("ccloud list")
            fi
        ;;
        aws|azure)
            if ! unattended_cloud_check "$resource"
            then
                logwarn "⏭️ skipping $resource: $unattended_cloud_reason"
                skipped+=("$resource")
                continue
            fi
            cost=$(playground --output-level ERROR cloud-resources "$resource" costs --start-date "$start_date" --end-date "$end_date" --display-only-total-cost 2> /dev/null | tail -1)
            if [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?$ ]]
            then
                cost=$(printf '%.2f' "$cost")
                log "💰 $resource: \$$cost for the resources tagged cflt_managed_id=$user"
                add_cost "$cost"
                parts+=("$resource \$$cost")
            else
                logwarn "⏭️ $resource cost not available (playground cloud-resources $resource costs)"
                skipped+=("$resource cost")
            fi
            playground cloud-resources "$resource" list --user "$user" > "$tmp_dir/$resource-list.txt" 2>&1
            nb_left=$(grep -c "🔥" "$tmp_dir/$resource-list.txt" | tr -d ' ')
            log "📋 $resource: $nb_left resource(s) still up for $user"
            grep "🔥" "$tmp_dir/$resource-list.txt" | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/^.*🔥/     🔥/'
        ;;
    esac
done

notify=""
if [ ${#parts[@]} -gt 0 ] && awk -v t="$total" -v th="$threshold" 'BEGIN { exit !(t >= th) }'
then
    notify="cost"
fi
if [ ${#running[@]} -gt 0 ]
then
    notify="${notify:+$notify, }running"
fi
if [ ${#skipped[@]} -gt 0 ]
then
    # a logged out CLI would otherwise keep the reminder silent every week
    notify="${notify:+$notify, }skipped"
fi

summary="last $days days: \$$total"
if [ ${#parts[@]} -gt 0 ]
then
    summary+=" ($(IFS=,; echo "${parts[*]}" | sed 's/,/, /g'))"
fi
if [ ${#running[@]} -gt 0 ]
then
    summary+="; $(IFS=,; echo "${running[*]}" | sed 's/,/, /g')"
fi
if [ ${#skipped[@]} -gt 0 ]
then
    summary+="; not checked: $(IFS=,; echo "${skipped[*]}" | sed 's/,/, /g')"
fi

if [[ -n "$notify" ]]
then
    logwarn "💸 $summary"
    log "👉 playground cloud-resources ccloud list, playground cloud-resources <cloud> costs, playground cloud-resources cleanup --resource <cloud> --dry-run"
    if [[ -n "$scheduled" ]]
    then
        scheduled_job_notify "💸 kafka-docker-playground cloud costs" "$summary"
    fi
else
    log "🟢 $summary: under \$$threshold, no connector running, every cloud checked: no notification"
fi
