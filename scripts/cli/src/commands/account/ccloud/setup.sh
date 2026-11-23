eval "clouds=(${args[--cloud]})"
environment_name="${args[--environment-name]:-pg-${USER}}"
profile="${args[--profile]:-$(get_active_secret_profile)}"
dry_run="${args[--dry-run]}"

# CLUSTER_* (examples that need no specific cloud): --default-cloud, else the first --cloud that is not databricks
default_cloud="${args[--default-cloud]}"
if [ -z "$default_cloud" ]
then
    for cloud in "${clouds[@]}"
    do
        if [ "$cloud" != "databricks" ]
        then
            default_cloud="$cloud"
            break
        fi
    done
elif [[ " ${clouds[*]} " != *" $default_cloud "* ]]
then
    logerror "❌ --default-cloud $default_cloud is not one of the --cloud: ${clouds[*]}"
    exit 1
fi

# a region variable from the shell, else from the secrets profile (where 'playground run' gets it from too)
function region_variable () {
    if [ -n "${!1:-}" ]
    then
        echo "${!1}"
    else
        # not stored: empty (the CLI runs with set -e)
        secret_get_from_store "$1" "$profile" 2> /dev/null || true
    fi
}

declare -A regions
aws_region=$(region_variable AWS_REGION)
azure_region=$(region_variable AZURE_REGION)
regions[aws]="${args[--aws-region]:-${aws_region:-eu-west-2}}"
regions[gcp]="${args[--gcp-region]:-europe-west2}"
regions[azure]="${args[--azure-region]:-${azure_region:-westeurope}}"
regions[databricks]="${args[--databricks-region]:-us-east-2}"
declare -A prefixes
prefixes[aws]="AWS_"
prefixes[gcp]="GCP_"
prefixes[azure]="AZURE_"
prefixes[databricks]="AWS_DATABRICKS_"
# cloud provider of each cluster: the databricks one is an AWS cluster (fm-databricks-delta-lake-sink)
declare -A providers
providers[aws]="aws"
providers[gcp]="gcp"
providers[azure]="azure"
providers[databricks]="aws"

tmp_dir=$(mktemp -d -t pg-ccloud-setup-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

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

if [[ -n "$dry_run" ]]
then
    log "🔎 dry-run: showing what would be created and stored, nothing is"
fi
log "🏗️ Setting up environment $environment_name with cluster(s) ${clouds[*]} (default: ${default_cloud:-none}), stored in secrets profile $profile"

# keys of the org, to know whether the keys already stored in the profile still belong to the resources
confluent api-key list -o json > "$tmp_dir/api-keys.json" 2> /dev/null || echo "[]" > "$tmp_dir/api-keys.json"

# $1 = variable stored in the profile, $2 = resource id: true when it holds a key of that resource
function stored_key_belongs_to () {
    local creds key
    creds=$(secret_get_from_store "$1" "$profile" 2> /dev/null) || return 1
    key="${creds%%:*}"
    [ -n "$key" ] && [ -n "${creds#*:}" ] && jq -e --arg k "$key" --arg r "$2" 'any(.[]; .key == $k and .resource == $r)' "$tmp_dir/api-keys.json" > /dev/null
}

# $1 = resource id, $2 = description: a new API key owned by the logged-in user, as key:secret
function create_user_api_key () {
    confluent api-key create --resource "$1" --environment "$environment_id" --description "$2" -o json 2> "$tmp_dir/error.txt" | jq -r 'select(.api_key != null) | "\(.api_key):\(.api_secret)"'
}

# what gets stored at the end: name, value, and plain/secret
declare -a store_names store_values store_kinds
function to_store () {
    store_names+=("$1")
    store_values+=("$2")
    store_kinds+=("$3")
}

# 🌐 environment
environment_id=$(jq -r --arg n "$environment_name" '[.[] | select(.name == $n)][0].id // empty' "$tmp_dir/environments.json")
if [ -n "$environment_id" ]
then
    log "🌐 environment $environment_name ($environment_id) already exists, reusing it"
elif [[ -n "$dry_run" ]]
then
    log "🔎 dry-run, would create environment $environment_name (Stream Governance essentials)"
    environment_id="<new environment>"
else
    log "🌐 creating environment $environment_name"
    environment_id=$(confluent environment create "$environment_name" --governance-package essentials -o json | jq -r '.id // empty')
    if [ -z "$environment_id" ]
    then
        logerror "❌ could not create environment $environment_name"
        exit 1
    fi
    log "🌐 environment $environment_name is $environment_id"
fi
to_store ENVIRONMENT "$environment_id" plain

# 🎰 clusters
if [[ "$environment_id" == env-* ]]
then
    confluent kafka cluster list --environment "$environment_id" -o json > "$tmp_dir/clusters.json" 2> /dev/null || echo "[]" > "$tmp_dir/clusters.json"
else
    echo "[]" > "$tmp_dir/clusters.json"
fi
declare -A cluster_ids
for cloud in "${clouds[@]}"
do
    name="pg-${USER}-$cloud"
    region="${regions[$cloud]}"
    id=$(jq -r --arg n "$name" '[.[] | select(.name == $n and ((.status // "") | ascii_upcase | test("DELET") | not))][0].id // empty' "$tmp_dir/clusters.json")
    if [ -n "$id" ]
    then
        existing_region=$(jq -r --arg id "$id" '.[] | select(.id == $id) | .region' "$tmp_dir/clusters.json")
        log "🎰 cluster $name ($id, ${providers[$cloud]} $existing_region) already exists, reusing it"
        if [ "$existing_region" != "$region" ]
        then
            logwarn "⚠️ it is in $existing_region, not $region: examples expecting $region will stop, delete it in the UI to move it"
            region="$existing_region"
        fi
    elif [[ -n "$dry_run" ]]
    then
        log "🔎 dry-run, would create Basic cluster $name (${providers[$cloud]} $region)"
        id="<new $cloud cluster>"
    else
        log "🎰 creating Basic cluster $name (${providers[$cloud]} $region)"
        id=$(confluent kafka cluster create "$name" --cloud "${providers[$cloud]}" --region "$region" --type basic --environment "$environment_id" -o json | jq -r '.id // empty')
        if [ -z "$id" ]
        then
            logerror "❌ could not create cluster $name (${providers[$cloud]} $region)"
            exit 1
        fi
        log "🎰 cluster $name is $id"
    fi
    cluster_ids[$cloud]="$id"
    regions[$cloud]="$region"
done

# 🔑 Schema Registry key (one per environment)
sr_creds=""
if [[ "$environment_id" == env-* ]]
then
    sr_cluster=""
    for i in $(seq 1 60)
    do
        sr_cluster=$(confluent schema-registry cluster describe --environment "$environment_id" -o json 2> /dev/null | jq -r '.cluster // empty')
        [ -n "$sr_cluster" ] && break
        if [ "$i" -eq 1 ]
        then
            log "⏳ waiting for the Schema Registry of environment $environment_id"
        fi
        sleep 5
    done
    if [ -z "$sr_cluster" ]
    then
        logerror "❌ the Schema Registry of environment $environment_id is not available after 5 minutes"
        exit 1
    fi
    if stored_key_belongs_to SCHEMA_REGISTRY_CREDS "$sr_cluster"
    then
        log "🔑 SCHEMA_REGISTRY_CREDS of profile $profile is a key of $sr_cluster, keeping it"
        to_store SCHEMA_REGISTRY_CREDS "$(secret_get_from_store SCHEMA_REGISTRY_CREDS "$profile")" secret
    elif [[ -n "$dry_run" ]]
    then
        log "🔎 dry-run, would create a Schema Registry API key for $sr_cluster, owned by you"
        to_store SCHEMA_REGISTRY_CREDS "<new key>" secret
    else
        sr_creds=$(create_user_api_key "$sr_cluster" "kafka-docker-playground SCHEMA_REGISTRY_CREDS (${USER})")
        if [ -z "$sr_creds" ]
        then
            logerror "❌ could not create a Schema Registry API key: $(cat "$tmp_dir/error.txt")"
            exit 1
        fi
        log "🔑 created Schema Registry API key ${sr_creds%%:*} ($sr_cluster), owned by you"
        to_store SCHEMA_REGISTRY_CREDS "$sr_creds" secret
    fi
elif [[ -n "$dry_run" ]]
then
    log "🔎 dry-run, would create a Schema Registry API key, owned by you"
    to_store SCHEMA_REGISTRY_CREDS "<new key>" secret
fi

# 🔑 Kafka keys, and the variables of each cluster
for cloud in "${clouds[@]}"
do
    id="${cluster_ids[$cloud]}"
    prefix="${prefixes[$cloud]}"
    name="pg-${USER}-$cloud"
    creds=""
    if [[ "$id" == lkc-* ]] && stored_key_belongs_to "${prefix}CLUSTER_CREDS" "$id"
    then
        log "🔑 ${prefix}CLUSTER_CREDS of profile $profile is a key of $id, keeping it"
        creds=$(secret_get_from_store "${prefix}CLUSTER_CREDS" "$profile")
        to_store "${prefix}CLUSTER_CREDS" "$creds" secret
    elif [[ -n "$dry_run" ]]
    then
        log "🔎 dry-run, would create a Kafka API key for $name, owned by you"
        creds="<new key>"
        to_store "${prefix}CLUSTER_CREDS" "$creds" secret
    else
        creds=$(create_user_api_key "$id" "kafka-docker-playground CLUSTER_CREDS (${USER})")
        if [ -z "$creds" ]
        then
            logerror "❌ could not create a Kafka API key for $name: $(cat "$tmp_dir/error.txt")"
            exit 1
        fi
        log "🔑 created Kafka API key ${creds%%:*} ($id), owned by you"
        to_store "${prefix}CLUSTER_CREDS" "$creds" secret
    fi
    to_store "${prefix}CLUSTER_NAME" "$name" plain
    to_store "${prefix}CLUSTER_CLOUD" "${providers[$cloud]}" plain
    to_store "${prefix}CLUSTER_REGION" "${regions[$cloud]}" plain
    if [ "$cloud" == "$default_cloud" ]
    then
        to_store CLUSTER_NAME "$name" plain
        to_store CLUSTER_CLOUD "${providers[$cloud]}" plain
        to_store CLUSTER_REGION "${regions[$cloud]}" plain
        if [ -n "$creds" ]
        then
            to_store CLUSTER_CREDS "$creds" secret
        fi
    fi
done

# ⏳ new clusters: wait for them to be UP (a few minutes for a Basic cluster)
if [[ -z "$dry_run" ]]
then
    for cloud in "${clouds[@]}"
    do
        id="${cluster_ids[$cloud]}"
        for i in $(seq 1 120)
        do
            status=$(confluent kafka cluster describe "$id" --environment "$environment_id" -o json 2> /dev/null | jq -r '.status // empty')
            [ "$status" == "UP" ] && break
            if [ "$i" -eq 1 ]
            then
                log "⏳ waiting for cluster pg-${USER}-$cloud ($id) to be UP ($status)"
            fi
            sleep 5
        done
        if [ "$status" != "UP" ]
        then
            logwarn "⚠️ cluster pg-${USER}-$cloud ($id) is $status after 10 minutes: it is stored anyway, check it in the UI"
        fi
    done
fi

# 💾 the secrets profile, with 'playground secrets set' (the keys kept from the profile too)
echo ""
for i in "${!store_names[@]}"
do
    name="${store_names[$i]}"
    value="${store_values[$i]}"
    if [[ -n "$dry_run" ]]
    then
        if [ "${store_kinds[$i]}" == "secret" ]
        then
            log "🔎 dry-run, would store $name=${value%%:*}:<secret> in profile $profile"
        else
            log "🔎 dry-run, would store $name=$value in profile $profile"
        fi
    else
        if ! out=$(playground secrets set "$name" --value "$value" --profile "$profile" "--${store_kinds[$i]}" 2>&1)
        then
            echo "$out"
            logerror "❌ could not store $name in profile $profile"
            exit 1
        fi
        echo "$out" | grep "⚠️" || true
        if [ "${store_kinds[$i]}" == "secret" ]
        then
            log "💾 $name=${value%%:*}:<secret> stored in profile $profile"
        else
            log "💾 $name=$value stored in profile $profile"
        fi
    fi
done

# ⚠️ exported variables win over the profile: they would hide what was just stored
exported=""
for name in ENVIRONMENT SCHEMA_REGISTRY_CREDS CLUSTER_NAME CLUSTER_CLOUD CLUSTER_REGION CLUSTER_CREDS AWS_CLUSTER_NAME GCP_CLUSTER_NAME AZURE_CLUSTER_NAME AWS_CLUSTER_CREDS GCP_CLUSTER_CREDS AZURE_CLUSTER_CREDS AWS_DATABRICKS_CLUSTER_NAME AWS_DATABRICKS_CLUSTER_CREDS
do
    if [ -n "${!name:-}" ]
    then
        exported="$exported $name"
    fi
done
echo ""
if [ -n "$exported" ]
then
    logwarn "⚠️ exported in your shell, these win over the profile:$exported"
    logwarn "👉 remove them from your shell startup file (~/.zshrc…) and open a new terminal"
fi
for cloud in aws azure
do
    if [[ " ${clouds[*]} " == *" $cloud "* ]]
    then
        var="AWS_REGION"
        [ "$cloud" == "azure" ] && var="AZURE_REGION"
        value=$(region_variable "$var")
        if [ -n "$value" ] && [ "$value" != "${regions[$cloud]}" ]
        then
            logwarn "⚠️ $var is $value but the $cloud cluster is in ${regions[$cloud]}: the examples that need their cloud resources and the cluster in the same region will stop"
        fi
    fi
done

if [[ -n "$dry_run" ]]
then
    log "🔎 dry-run done: run it again without --dry-run"
    exit 0
fi
log "✅ environment $environment_name ($environment_id) and cluster(s) ${clouds[*]} are ready, in secrets profile $profile"
if [ "$profile" != "$(get_active_secret_profile)" ]
then
    log "👉 playground secrets profile $profile        # to use them"
fi
log "👉 playground cleanup-cloud-details      # forget the cluster of the previous runs"
log "👉 playground run -f ccloud/fm-datagen-source/fully-managed-datagen-source.sh"
log "🎓 new API keys can take a minute or two to be usable"
