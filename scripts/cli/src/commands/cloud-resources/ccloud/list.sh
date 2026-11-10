user="${args[--user]}"
json="${args[--json]}"

if [[ ! -n "$user" ]]
then
    user="${USER}"
fi
tmp_dir=$(mktemp -d -t pg-ccloud-list-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

quiet=0
if [[ -n "$json" ]]
then
    quiet=1
fi
if ! ccloud_scan_org "$tmp_dir" "$user" "$quiet"
then
    exit 1
fi
nb_environments=$(cat "$tmp_dir/nb-environments.txt")
nb_clusters=$(cat "$tmp_dir/nb-clusters.txt")


if [[ -n "$json" ]]
then
    jq -n --arg user "$user" --argjson nb_environments "$nb_environments" --argjson nb_clusters "$nb_clusters" \
        --slurpfile connectors "$tmp_dir/connectors.json" \
        --slurpfile environments "$tmp_dir/environments-user.json" \
        --slurpfile clusters "$tmp_dir/clusters-user.json" \
        --slurpfile service_accounts "$tmp_dir/service-accounts-user.json" \
        --slurpfile api_keys "$tmp_dir/api-keys-user.json" \
        --slurpfile recorded_topics "$tmp_dir/recorded-topics.json" \
        '{user: $user, scanned: {environments: $nb_environments, clusters: $nb_clusters},
          connectors: $connectors[0], environments: $environments[0], clusters: $clusters[0],
          service_accounts: $service_accounts[0], api_keys: $api_keys[0], recorded_topics: $recorded_topics[0]}'
    exit 0
fi

now=$(date +%s)
# age of an epoch: 3d, 5h, 12m
function epoch_age () {
    local epoch="$1"
    if [[ ! "$epoch" =~ ^[0-9]+$ ]]
    then
        echo "?"
        return
    fi
    local seconds=$(( now - epoch ))
    if [ $seconds -ge 86400 ]
    then
        echo "$(( seconds / 86400 ))d"
    elif [ $seconds -ge 3600 ]
    then
        echo "$(( seconds / 3600 ))h"
    else
        echo "$(( seconds / 60 ))m"
    fi
}

echo ""
nb=$(jq length "$tmp_dir/connectors.json")
if [ "$nb" -gt 0 ]
then
    log "🤖 Connectors *_$user ($nb), 🧹 deleted by cleanup with their dlq/success/error topics"
    printf "%-38s %-10s %-26s %-12s %-24s %-5s\n" "Name" "Status" "Type" "Id" "Cluster (environment)" "Age"
    jq -r '.[] | [.name, .status, .type, .id, "\(.cluster_name) (\(.environment))", (.created // "")] | map(tostring) | join("\u001f")' "$tmp_dir/connectors.json" \
        | while IFS=$'\x1f' read -r name status type id cluster created
        do
            printf "%-38s %-10s %-26s %-12s %-24s %-5s\n" "$name" "$status" "$type" "$id" "$cluster" "$(epoch_age "$created")"
        done
else
    log "🤖 Connectors *_$user: none ✅"
fi

echo ""
nb=$(jq length "$tmp_dir/environments-user.json")
if [ "$nb" -gt 0 ]
then
    log "🌐 Environments pg-$user-* ($nb)"
    printf "%-14s %-60s %-6s\n" "Id" "Name" "🧹"
    jq -r '.[] | [.id, .name, (if .cleanup then "yes" else "no" end)] | map(tostring) | join("\u001f")' "$tmp_dir/environments-user.json" \
        | while IFS=$'\x1f' read -r id name cleanup
        do
            printf "%-14s %-60s %-6s\n" "$id" "$name" "$cleanup"
        done
else
    log "🌐 Environments pg-$user-*: none ✅"
fi

echo ""
nb=$(jq length "$tmp_dir/clusters-user.json")
if [ "$nb" -gt 0 ]
then
    log "🎰 Clusters created for $user ($nb)"
    printf "%-12s %-40s %-10s %-6s %-14s %-8s %-28s\n" "Id" "Name" "Type" "Cloud" "Region" "Status" "🧹"
    jq -r '.[] | [.id, .name, .type, .cloud, .region, .status, .cleanup] | map(tostring) | join("\u001f")' "$tmp_dir/clusters-user.json" \
        | while IFS=$'\x1f' read -r id name type cloud region status cleanup
        do
            printf "%-12s %-40s %-10s %-6s %-14s %-8s %-28s\n" "$id" "$name" "$type" "$cloud" "$region" "$status" "$cleanup"
        done
else
    log "🎰 Clusters created for $user: none ✅"
fi

echo ""
nb=$(jq length "$tmp_dir/service-accounts-user.json")
if [ "$nb" -gt 0 ]
then
    log "🤖 Service accounts pg-$user-* ($nb)"
    printf "%-12s %-40s %-9s %-16s\n" "Id" "Name" "API keys" "🧹"
    jq -r --slurpfile keys "$tmp_dir/api-keys-user.json" '.[] | .id as $id | [.id, .name, ([$keys[0][] | select(.owner == $id)] | length), .cleanup] | map(tostring) | join("\u001f")' "$tmp_dir/service-accounts-user.json" \
        | while IFS=$'\x1f' read -r id name keys cleanup
        do
            printf "%-12s %-40s %-9s %-16s\n" "$id" "$name" "$keys" "$cleanup"
        done
else
    log "🤖 Service accounts pg-$user-*: none ✅"
fi

nb=$(jq length "$tmp_dir/api-keys-user.json")
if [ "$nb" -gt 0 ]
then
    echo ""
    log "🔑 API keys owned by these service accounts, or created for you by the playground ($nb)"
    printf "%-18s %-16s %-14s %-40s %-5s %-12s\n" "Key" "Resource type" "Resource" "Owner" "Age" "🧹"
    jq -r '.[] | [.key, .resource_type, .resource, .owner_name, (.created | fromdateiso8601? // ""), (if .in_use then "no (in use)" else "yes" end)] | map(tostring) | join("\u001f")' "$tmp_dir/api-keys-user.json" \
        | while IFS=$'\x1f' read -r key type resource owner created cleanup
        do
            printf "%-18s %-16s %-14s %-40s %-5s %-12s\n" "$key" "$type" "$resource" "$owner" "$(epoch_age "$created")" "$cleanup"
        done
fi

echo ""
nb=$(jq length "$tmp_dir/recorded-topics.json")
if [ "$nb" -gt 0 ]
then
    log "📝 Topics recorded by your runs on this machine (playground-ccloud-created-topics)"
    jq -r '.[] | [.cluster, (.cluster_name // ""), (.cluster_exists | tostring), (.checked | tostring), (.recorded | tostring), (.existing | length | tostring), (.existing[:5] | join(", "))] | map(tostring) | join("\u001f")' "$tmp_dir/recorded-topics.json" \
        | while IFS=$'\x1f' read -r cluster cluster_name exists checked recorded existing names
        do
            if [ "$exists" != "true" ]
            then
                log "  🪦 $cluster: cluster gone, $recorded stale record(s)"
            elif [ "$checked" != "true" ]
            then
                log "  ❓ $cluster_name ($cluster): $recorded recorded, could not list its topics (no API key or permission)"
            elif [ "$existing" == "0" ]
            then
                log "  ✅ $cluster_name ($cluster): $recorded recorded, none left"
            else
                more=""
                if [ "$existing" -gt 5 ]
                then
                    more=", …"
                fi
                log "  📝 $cluster_name ($cluster): $recorded recorded (topics or prefixes), $existing topic(s) still exist: $names$more"
            fi
        done
else
    log "📝 Topics recorded by your runs on this machine: none ✅"
fi

echo ""
running=$(jq '[.[] | select(.status == "RUNNING")] | length' "$tmp_dir/connectors.json")
connectors=$(jq length "$tmp_dir/connectors.json")
clusters=$(jq length "$tmp_dir/clusters-user.json")
if [ "$connectors" -gt 0 ] || [ "$clusters" -gt 0 ]
then
    log "💸 Still billing: $connectors connector(s) ($running RUNNING), $clusters cluster(s) created for you"
    log "🧹 To delete them: playground cloud-resources cleanup --resource ccloud --dry-run, then without --dry-run"
else
    log "✨ Nothing billing for $user in this organization (scanned $nb_environments environment(s), $nb_clusters cluster(s))"
fi
