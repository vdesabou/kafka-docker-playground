profile="${args[--profile]:-$(get_active_secret_profile)}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

tmp_dir=$(mktemp -d -t pg-ccloud-check-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# 1. the confluent CLI
if ! confluent environment list -o json > "$tmp_dir/environments.json" 2> "$tmp_dir/error.txt"
then
    if grep -q -e "You must login" -e "Your session has expired" "$tmp_dir/error.txt"
    then
        logerror "❌ the confluent CLI is not logged in: run 'confluent login --organization <id> --save' and try again"
    else
        logerror "❌ could not list the Confluent Cloud environments: $(cat "$tmp_dir/error.txt")"
    fi
    exit 1
fi
org=$(confluent organization describe -o json 2> /dev/null | jq -r '"\(.name) (\(.id))"' 2> /dev/null || true)
log "🔐 confluent CLI logged in to organization ${org:-<unknown>}, checking secrets profile $profile"

# a variable like 'playground run' sees it: exported in the shell first, else the secrets profile
declare -a exported_names
function ccloud_check_value () {
    if [ -n "${!1:-}" ]
    then
        printf '%s' "${!1}"
    else
        secret_get_from_store "$1" "$profile" 2> /dev/null || true
    fi
}
for name in ENVIRONMENT SCHEMA_REGISTRY_CREDS CLUSTER_NAME CLUSTER_CLOUD CLUSTER_REGION CLUSTER_CREDS AWS_CLUSTER_NAME AWS_CLUSTER_CLOUD AWS_CLUSTER_REGION AWS_CLUSTER_CREDS GCP_CLUSTER_NAME GCP_CLUSTER_CLOUD GCP_CLUSTER_REGION GCP_CLUSTER_CREDS AZURE_CLUSTER_NAME AZURE_CLUSTER_CLOUD AZURE_CLUSTER_REGION AZURE_CLUSTER_CREDS AWS_DATABRICKS_CLUSTER_NAME AWS_DATABRICKS_CLUSTER_CLOUD AWS_DATABRICKS_CLUSTER_REGION AWS_DATABRICKS_CLUSTER_CREDS
do
    if [ -n "${!name:-}" ]
    then
        exported_names+=("$name")
    fi
done

nb_failed=0
function ccloud_check_fail () {
    echo -e "❌ ${RED}$1${NC} $2"
    nb_failed=$((nb_failed + 1))
}

# 2. the environment
environment_id=$(ccloud_check_value ENVIRONMENT)
if [ -z "$environment_id" ]
then
    logerror "❌ ENVIRONMENT is not set in secrets profile $profile (nor exported): every fully managed example then creates its own cluster on each run"
    logerror "👉 playground account ccloud setup --dry-run"
    exit 1
fi
environment_name=$(jq -r --arg id "$environment_id" '.[] | select(.id == $id) | .name' "$tmp_dir/environments.json")
if [ -z "$environment_name" ]
then
    ccloud_check_fail "Environment" "$environment_id does not exist in organization ${org:-<unknown>} (deleted, or the confluent CLI is logged in to another organization)        👉 playground account ccloud setup"
    environment_ok=0
else
    echo -e "✅ ${GREEN}Environment${NC} $environment_name ($environment_id)"
    environment_ok=1
fi

# keys of the org, to tell a deleted key or a key of another cluster apart from a key not yet usable
api_keys_ok=1
confluent api-key list -o json > "$tmp_dir/api-keys.json" 2> /dev/null || { echo "[]" > "$tmp_dir/api-keys.json"; api_keys_ok=0; }

# $1 = key:secret, $2 = resource id: empty when the key belongs to it, else why not
function ccloud_check_key_owner () {
    local key="${1%%:*}" resource
    [ $api_keys_ok -eq 1 ] || return 0
    resource=$(jq -r --arg k "$key" '[.[] | select(.key == $k)][0].resource // empty' "$tmp_dir/api-keys.json")
    if [ -z "$resource" ]
    then
        echo "API key $key does not exist (deleted)"
    elif [ "$resource" != "$2" ]
    then
        echo "API key $key is a key of $resource, not of $2"
    fi
}

# $1 = key:secret, $2 = url: HTTP code of a GET with the key
function ccloud_check_http () {
    curl -s -o /dev/null -w '%{http_code}' --max-time 20 -u "$1" "$2" 2> /dev/null || true
}

# 3. the clusters: prefix|expected cloud|who uses it
if [ $environment_ok -eq 1 ]
then
    confluent kafka cluster list --environment "$environment_id" -o json > "$tmp_dir/clusters.json" 2> /dev/null || echo "[]" > "$tmp_dir/clusters.json"
else
    echo "[]" > "$tmp_dir/clusters.json"
fi
declare -A checked_cluster_ids
while IFS='|' read -r prefix expected_cloud users setup_flag
do
    # no environment: its clusters can't be found, the failure above says it all
    [ $environment_ok -eq 1 ] || break
    label="${prefix}CLUSTER"
    name=$(ccloud_check_value "${prefix}CLUSTER_NAME")
    if [ -z "$name" ]
    then
        if [ -z "$prefix" ]
        then
            ccloud_check_fail "$label" "CLUSTER_NAME is not set: $users create their own cluster on each run        👉 playground account ccloud setup"
        elif [ "$prefix" == "AWS_DATABRICKS_" ]
        then
            echo -e "ℹ️  ${label}_NAME is not set: only $users needs it        👉 playground account ccloud setup${setup_flag:+ $setup_flag}"
        else
            echo -e "ℹ️  ${label}_NAME is not set: $users use CLUSTER_NAME, and stop when it is not on $expected_cloud        👉 playground account ccloud setup${setup_flag:+ $setup_flag}"
        fi
        continue
    fi
    stored_cloud=$(ccloud_check_value "${prefix}CLUSTER_CLOUD")
    stored_region=$(ccloud_check_value "${prefix}CLUSTER_REGION")
    creds=$(ccloud_check_value "${prefix}CLUSTER_CREDS")
    cluster=$(jq -c --arg n "$name" '[.[] | select(.name == $n and ((.status // "") | ascii_upcase | test("DELET") | not))][0] // empty' "$tmp_dir/clusters.json")
    if [ -z "$cluster" ]
    then
        ccloud_check_fail "$label" "$name does not exist in environment $environment_id (needed by $users)        👉 playground account ccloud setup${setup_flag:+ $setup_flag}"
        continue
    fi
    id=$(echo "$cluster" | jq -r '.id')
    cloud=$(echo "$cluster" | jq -r '.cloud | ascii_downcase')
    region=$(echo "$cluster" | jq -r '.region')
    status=$(echo "$cluster" | jq -r '.status')
    problems=()
    [ "$status" != "UP" ] && problems+=("status is $status, not UP")
    [ -n "$expected_cloud" ] && [ "$cloud" != "$expected_cloud" ] && problems+=("it is on $cloud, $users need $expected_cloud")
    [ -n "$stored_cloud" ] && [ "$stored_cloud" != "$cloud" ] && problems+=("${prefix}CLUSTER_CLOUD is $stored_cloud, the cluster is on $cloud")
    [ -n "$stored_region" ] && [ "$stored_region" != "$region" ] && problems+=("${prefix}CLUSTER_REGION is $stored_region, the cluster is in $region")
    [ -z "$stored_cloud" ] && problems+=("${prefix}CLUSTER_CLOUD is not set")
    [ -z "$stored_region" ] && problems+=("${prefix}CLUSTER_REGION is not set")
    # the key, when the cluster is the same as one already checked: the same answer
    key_result=""
    if [ -z "$creds" ]
    then
        problems+=("${prefix}CLUSTER_CREDS is not set")
    elif [ -n "${checked_cluster_ids[$id:${creds%%:*}]:-}" ]
    then
        key_result="${checked_cluster_ids[$id:${creds%%:*}]}"
    else
        owner_problem=$(ccloud_check_key_owner "$creds" "$id")
        if [ -n "$owner_problem" ]
        then
            key_result="$owner_problem"
        else
            rest_endpoint=$(confluent kafka cluster describe "$id" --environment "$environment_id" -o json 2> /dev/null | jq -r '.rest_endpoint // empty')
            if [ -n "$rest_endpoint" ]
            then
                code=$(ccloud_check_http "$creds" "$rest_endpoint/kafka/v3/clusters/$id/topics")
                case "$code" in
                    200) key_result="" ;;
                    401) key_result="API key ${creds%%:*} is refused (401): wrong secret, or a new key not usable yet (a minute or two)" ;;
                    403) key_result="API key ${creds%%:*} can't list the topics (403): a service account key without ACLs?" ;;
                    *) key_result="~API key ${creds%%:*} not verified (HTTP ${code:-no answer} from $rest_endpoint)" ;;
                esac
            fi
        fi
        checked_cluster_ids[$id:${creds%%:*}]="${key_result:-ok}"
    fi
    [ "$key_result" == "ok" ] && key_result=""
    warning=""
    if [[ "$key_result" == "~"* ]]
    then
        warning="${key_result#\~}"
    elif [ -n "$key_result" ]
    then
        problems+=("$key_result")
    fi
    if [ ${#problems[@]} -eq 0 ]
    then
        echo -e "✅ ${GREEN}$label${NC} $name ($id, $cloud $region, key ${creds%%:*} works)${warning:+ ⚠️ $warning}"
    else
        ccloud_check_fail "$label" "$name ($id, $cloud $region)"
        for problem in "${problems[@]}"
        do
            echo "      $problem"
        done
        echo "      needed by: $users        👉 playground account ccloud setup${setup_flag:+ $setup_flag}"
    fi
done << EOF
||the fully managed examples that need no specific cloud|
AWS_|aws|ccloud/fm-aws-*|--cloud aws
GCP_|gcp|ccloud/fm-gcp-*|--cloud gcp
AZURE_|azure|ccloud/fm-azure-*|--cloud azure
AWS_DATABRICKS_|aws|ccloud/fm-databricks-delta-lake-sink|--cloud databricks
EOF

# 4. the Schema Registry key
sr_creds=$(ccloud_check_value SCHEMA_REGISTRY_CREDS)
if [ $environment_ok -eq 1 ]
then
    confluent schema-registry cluster describe --environment "$environment_id" -o json > "$tmp_dir/sr.json" 2> /dev/null || echo "{}" > "$tmp_dir/sr.json"
    sr_cluster=$(jq -r '.cluster // empty' "$tmp_dir/sr.json")
    sr_endpoint=$(jq -r '.endpoint_url // empty' "$tmp_dir/sr.json")
    if [ -z "$sr_cluster" ]
    then
        ccloud_check_fail "Schema Registry" "environment $environment_id has no Schema Registry (Stream Governance not enabled)        👉 playground account ccloud setup"
    elif [ -z "$sr_creds" ]
    then
        ccloud_check_fail "Schema Registry" "SCHEMA_REGISTRY_CREDS is not set: the examples with Avro, Protobuf or JSON Schema fail        👉 playground account ccloud setup"
    else
        owner_problem=$(ccloud_check_key_owner "$sr_creds" "$sr_cluster")
        if [ -n "$owner_problem" ]
        then
            ccloud_check_fail "Schema Registry" "$sr_cluster: $owner_problem        👉 playground account ccloud setup"
        else
            code=$(ccloud_check_http "$sr_creds" "$sr_endpoint/subjects")
            case "$code" in
                200) echo -e "✅ ${GREEN}Schema Registry${NC} $sr_cluster ($sr_endpoint, key ${sr_creds%%:*} works)" ;;
                401) ccloud_check_fail "Schema Registry" "$sr_cluster: API key ${sr_creds%%:*} is refused (401): wrong secret, or a new key not usable yet (a minute or two)" ;;
                403) ccloud_check_fail "Schema Registry" "$sr_cluster: API key ${sr_creds%%:*} can't list the subjects (403): a service account key without a role binding?" ;;
                *) echo -e "⚠️ ${YELLOW}Schema Registry${NC} $sr_cluster: API key ${sr_creds%%:*} not verified (HTTP ${code:-no answer} from $sr_endpoint)" ;;
            esac
        fi
        used=$(jq -r '.used_schemas // empty' "$tmp_dir/sr.json")
        limit=$(jq -r '.free_schemas_limit // empty' "$tmp_dir/sr.json")
        if [[ "$used" =~ ^[0-9]+$ ]] && [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -gt 0 ] && [ $((used * 100 / limit)) -ge 90 ]
        then
            echo -e "⚠️ ${YELLOW}Schema Registry${NC} $used of the $limit free schemas are used: delete old subjects        👉 playground cloud-resources cleanup --resource ccloud --dry-run"
        fi
    fi
fi

# 5. the regions of the cloud resources of the examples
for pair in AWS_REGION:AWS_CLUSTER_REGION AZURE_REGION:AZURE_CLUSTER_REGION
do
    var="${pair%%:*}"
    cluster_var="${pair#*:}"
    value=$(ccloud_check_value "$var")
    cluster_value=$(ccloud_check_value "$cluster_var")
    if [ -n "$value" ] && [ -n "$cluster_value" ] && [ "$value" != "$cluster_value" ]
    then
        echo -e "⚠️ ${YELLOW}$var${NC} is $value but $cluster_var is $cluster_value: the examples that need their cloud resources and the cluster in the same region stop"
    fi
done

# 6. exported variables win over the profile
if [ ${#exported_names[@]} -gt 0 ]
then
    echo -e "⚠️ ${YELLOW}Exported${NC} in your shell, these win over secrets profile $profile: ${exported_names[*]}        👉 remove them from your shell startup file (~/.zshrc…)"
fi
if [ $api_keys_ok -eq 0 ]
then
    echo -e "⚠️ ${YELLOW}API keys${NC} could not be listed ('confluent api-key list'): a deleted key or a key of another cluster is reported as refused"
fi

echo ""
if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed check(s) failed: the examples listed above would fail or create their own cluster"
    exit 1
else
    log "🎉 environment ${environment_name:-$environment_id} and its clusters are ready for the fully managed examples"
    log "👉 playground cloud-resources ccloud list        # what still runs (connectors) in the organization"
fi
