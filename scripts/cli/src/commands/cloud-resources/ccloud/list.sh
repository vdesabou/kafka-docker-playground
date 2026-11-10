user="${args[--user]}"
json="${args[--json]}"

if [[ ! -n "$user" ]]
then
    user="${USER}"
fi
# examples strip - . _ from the user in some names (${USER//[-._]/})
user_normalized=$(tr '[:upper:]' '[:lower:]' <<< "${user//[-._]/}")

tmp_dir=$(mktemp -d -t pg-ccloud-list-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# log goes to stderr, but keep --json output free of anything else
function list_log () {
    if [[ ! -n "$json" ]]
    then
        log "$@"
    fi
}

if ! confluent environment list -o json > "$tmp_dir/environments.json" 2> "$tmp_dir/error.txt"
then
    if grep -q -e "You must login" -e "Your session has expired" "$tmp_dir/error.txt"
    then
        logerror "❌ the confluent CLI is not logged in: run 'confluent login --save' and try again"
    else
        logerror "❌ could not list the Confluent Cloud environments: $(cat "$tmp_dir/error.txt")"
    fi
    exit 1
fi

nb_environments=$(jq length "$tmp_dir/environments.json")
list_log "🔎 Looking for what $user left in Confluent Cloud, in the $nb_environments environment(s) of the organization"

# every call below only reads: run them 8 at a time, an org shared by a whole team has many environments and clusters
export PG_CCLOUD_LIST_TMP="$tmp_dir"
jq -r '.[].id' "$tmp_dir/environments.json" | xargs -P 8 -I {} sh -c \
    'confluent kafka cluster list --environment "$1" -o json > "$PG_CCLOUD_LIST_TMP/clusters-$1.json" 2> /dev/null || echo "[]" > "$PG_CCLOUD_LIST_TMP/clusters-$1.json"' _ {}

# service accounts and API keys are org-wide: fetched while the connectors are listed
confluent iam service-account list -o json > "$tmp_dir/service-accounts.json" 2> /dev/null &
sa_pid=$!
confluent api-key list -o json > "$tmp_dir/api-keys.json" 2> /dev/null &
keys_pid=$!

# all clusters, with their environment
for env_id in $(jq -r '.[].id' "$tmp_dir/environments.json")
do
    env_name=$(jq -r --arg id "$env_id" '.[] | select(.id == $id) | .name' "$tmp_dir/environments.json")
    jq -c --arg env "$env_id" --arg env_name "$env_name" \
        '(if type == "array" then . else [] end)[] | {environment: $env, environment_name: $env_name, id, name, type, cloud, region, status}' \
        "$tmp_dir/clusters-$env_id.json" 2> /dev/null
done | jq -s '.' > "$tmp_dir/all-clusters.json"
nb_clusters=$(jq length "$tmp_dir/all-clusters.json")
list_log "🔎 Listing the connectors of the $nb_clusters Kafka cluster(s)"

jq -r '.[] | "\(.environment) \(.id)"' "$tmp_dir/all-clusters.json" | xargs -P 8 -L 1 sh -c \
    'confluent connect cluster list --environment "$0" --cluster "$1" -o json > "$PG_CCLOUD_LIST_TMP/connectors-$1.json" 2> /dev/null || echo "[]" > "$PG_CCLOUD_LIST_TMP/connectors-$1.json"'

wait $sa_pid || echo "[]" > "$tmp_dir/service-accounts.json"
wait $keys_pid || echo "[]" > "$tmp_dir/api-keys.json"

# local run records: "<cluster id> <topic|prefix:<prefix>|connector:<name>> <run id = epoch of the run>"
get_ccloud_created_topics_file
if [ -f "$ccloud_created_topics_file" ]
then
    jq -Rn '[inputs | split(" ") | select(length >= 2) | {cluster: .[0], entry: .[1], run_id: (.[2] // "")}]' "$ccloud_created_topics_file" > "$tmp_dir/records.json"
else
    echo "[]" > "$tmp_dir/records.json"
fi

# connectors *_<user> (as matched by 'cloud-resources cleanup'), with the epoch of the run that created them when recorded
for cluster_id in $(jq -r '.[].id' "$tmp_dir/all-clusters.json")
do
    jq -c --arg cluster "$cluster_id" --arg user "$user" --slurpfile clusters "$tmp_dir/all-clusters.json" --slurpfile records "$tmp_dir/records.json" '
        ($clusters[0][] | select(.id == $cluster)) as $c
        | (if type == "array" then . else [] end)[]
        | select(.name | contains("_" + $user))
        | . as $conn
        | {environment: $c.environment, environment_name: $c.environment_name, cluster: $cluster, cluster_name: $c.name,
           id, name, status, type,
           created: ([$records[0][] | select(.cluster == $cluster and .entry == ("connector:" + $conn.name)) | .run_id | tonumber? ] | max)}' \
        "$tmp_dir/connectors-$cluster_id.json" 2> /dev/null
done | jq -s '.' > "$tmp_dir/connectors.json"

# environments and clusters named pg-<user>-*: what the playground created for this user
jq --arg u "$user" --arg n "$user_normalized" '
    [.[] | select((.name == "pg-" + $u) or (.name | startswith("pg-" + $u + "-")) or (.name | ascii_downcase | . == "pg-" + $n or startswith("pg-" + $n + "-")))
     | {id, name, cleanup: (.name | startswith("pg-" + $u + "-sa-"))}]' "$tmp_dir/environments.json" > "$tmp_dir/environments-user.json"
jq --arg u "$user" --arg n "$user_normalized" --slurpfile envs "$tmp_dir/environments-user.json" '
    ([$envs[0][] | .id]) as $env_ids
    | ([$envs[0][] | select(.cleanup) | .id]) as $cleanup_env_ids
    | [.[] | select((.environment as $e | $env_ids | index($e)) or (.name | startswith("pg-" + $u + "-")) or (.name | ascii_downcase | startswith("pg-" + $n + "-")))
       | . + {cleanup: (if (.environment as $e | $cleanup_env_ids | index($e)) then "deleted with its environment" elif (.name | startswith("pg-" + $u + "-")) then "all its topics" else "no" end)}]' \
    "$tmp_dir/all-clusters.json" > "$tmp_dir/clusters-user.json"

# service accounts pg-<user>-* and the API keys they own
jq --arg u "$user" '
    [(if type == "array" then . else [] end)[] | select(.name | startswith("pg-" + $u + "-"))
     | {id, name, description, cleanup: (if (.name | startswith("pg-" + $u + "-conn-")) then "yes" else "CI only" end)}]' \
    "$tmp_dir/service-accounts.json" > "$tmp_dir/service-accounts-user.json"
jq --slurpfile sas "$tmp_dir/service-accounts-user.json" '
    ([$sas[0][] | {key: .id, value: .name}] | from_entries) as $owners
    | [(if type == "array" then . else [] end)[] | select($owners[.owner] != null)
       | {key, owner, owner_name: $owners[.owner], resource_type, resource, created, description}]' \
    "$tmp_dir/api-keys.json" > "$tmp_dir/api-keys-user.json"

# topics recorded by this machine's runs: still there? (one topic list per cluster that still exists)
for cluster_id in $(jq -r '[.[] | select(.entry | startswith("connector:") | not) | .cluster] | unique | .[]' "$tmp_dir/records.json")
do
    env_id=$(jq -r --arg id "$cluster_id" '.[] | select(.id == $id) | .environment' "$tmp_dir/all-clusters.json")
    if [ -n "$env_id" ]
    then
        if confluent kafka topic list --environment "$env_id" --cluster "$cluster_id" -o json > "$tmp_dir/topics-$cluster_id.json" 2> /dev/null < /dev/null
        then
            checked=true
        else
            echo "[]" > "$tmp_dir/topics-$cluster_id.json"
            checked=false
        fi
    else
        echo "[]" > "$tmp_dir/topics-$cluster_id.json"
        checked=false
    fi
    jq -c --arg cluster "$cluster_id" --arg env "$env_id" --argjson checked "$checked" --slurpfile records "$tmp_dir/records.json" --slurpfile clusters "$tmp_dir/all-clusters.json" '
        ([.[].name]) as $existing
        | ([$records[0][] | select(.cluster == $cluster and (.entry | startswith("connector:") | not)) | .entry] | unique) as $entries
        | {cluster: $cluster,
           cluster_name: ([$clusters[0][] | select(.id == $cluster) | .name] | first),
           cluster_exists: ($env != ""),
           checked: $checked,
           recorded: ($entries | length),
           existing: [$existing[] as $t | select($entries | any(. as $e | $e == $t or (($e | startswith("prefix:")) and ($t | startswith($e[7:]))))) | $t]}' \
        "$tmp_dir/topics-$cluster_id.json"
done | jq -s '.' > "$tmp_dir/recorded-topics.json"

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
    printf "%-12s %-40s %-9s %-8s\n" "Id" "Name" "API keys" "🧹"
    jq -r --slurpfile keys "$tmp_dir/api-keys-user.json" '.[] | .id as $id | [.id, .name, ([$keys[0][] | select(.owner == $id)] | length), .cleanup] | map(tostring) | join("\u001f")' "$tmp_dir/service-accounts-user.json" \
        | while IFS=$'\x1f' read -r id name keys cleanup
        do
            printf "%-12s %-40s %-9s %-8s\n" "$id" "$name" "$keys" "$cleanup"
        done
else
    log "🤖 Service accounts pg-$user-*: none ✅"
fi

nb=$(jq length "$tmp_dir/api-keys-user.json")
if [ "$nb" -gt 0 ]
then
    echo ""
    log "🔑 API keys owned by these service accounts ($nb)"
    printf "%-18s %-16s %-14s %-40s %-5s\n" "Key" "Resource type" "Resource" "Owner" "Age"
    jq -r '.[] | [.key, .resource_type, .resource, .owner_name, (.created | fromdateiso8601? // "")] | map(tostring) | join("\u001f")' "$tmp_dir/api-keys-user.json" \
        | while IFS=$'\x1f' read -r key type resource owner created
        do
            printf "%-18s %-16s %-14s %-40s %-5s\n" "$key" "$type" "$resource" "$owner" "$(epoch_age "$created")"
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
    log "🎓 cleanup only reaches connectors on the cluster(s) of your CLUSTER_NAME / AWS_ / GCP_ / AZURE_ / AWS_DATABRICKS_CLUSTER_NAME (and the last one used): delete any other with playground connector delete, or in the UI"
else
    log "✨ Nothing billing for $user in this organization (scanned $nb_environments environment(s), $nb_clusters cluster(s))"
fi
