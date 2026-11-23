host_arg="${args[--host]}"
token_arg="${args[--token]}"
warehouse_arg="${args[--warehouse]}"
bucket="${args[--bucket]}"
bucket_region="${args[--bucket-region]}"
staging_key_id="${args[--staging-access-key-id]}"
staging_secret="${args[--staging-secret-access-key]}"
no_store="${args[--no-store]}"

for tool in jq curl
do
    if ! command -v $tool > /dev/null 2>&1
    then
        logerror "❌ $tool is not installed"
        exit 1
    fi
done

# missing values: the stored ones, else asked for
profile="$(get_active_secret_profile)"
function databricks_setup_value () {
    name="$1"
    prompt="$2"
    silent="$3"
    value="$(secret_get "$name" "$profile" 2> /dev/null || true)"
    if [ -z "$value" ] && [ -t 0 ]
    then
        if [[ -n "$silent" ]]
        then
            read -r -s -p "$prompt: " value < /dev/tty
            echo "" >&2
        else
            read -r -p "$prompt: " value < /dev/tty
        fi
    fi
    if [ -z "$value" ]
    then
        logerror "❌ $name is not set: pass it as a flag (see --help)"
        exit 1
    fi
    printf '%s' "$value"
}
[[ -n "$host_arg" ]] || host_arg=$(databricks_setup_value DATABRICKS_SERVER_HOSTNAME "🏠 workspace URL or host (https://dbc-xxxx.cloud.databricks.com)")
[[ -n "$token_arg" ]] || token_arg=$(databricks_setup_value DATABRICKS_TOKEN "🔐 personal access token (Settings > Developer > Access tokens)" silent)
databricks_host=$(databricks_normalize_host "$host_arg")
databricks_token="$token_arg"

# 1. the token
databricks_api "/api/2.0/preview/scim/v2/Me"
me="$databricks_body"
if [ "$databricks_http_code" != "200" ]
then
    logerror "❌ the workspace refused the token: HTTP $databricks_http_code"
    cause=$(databricks_explain_http "$databricks_http_code" "$databricks_body")
    [ -n "$cause" ] && logerror "   $cause"
    exit 1
fi
principal=$(echo "$me" | jq -r '.userName // .displayName')
log "✅ token of $principal works on $databricks_host"

# 2. the SQL warehouse: DATABRICKS_HTTP_PATH and the hostname come from its connection details
databricks_api "/api/2.0/sql/warehouses"
warehouses="$databricks_body"
if [ "$databricks_http_code" != "200" ]
then
    logerror "❌ can't list the SQL warehouses: HTTP $databricks_http_code"
    exit 1
fi
if [[ -n "$warehouse_arg" ]]
then
    warehouse=$(echo "$warehouses" | jq -c --arg w "$warehouse_arg" '[.warehouses[]? | select(.id == $w or .name == $w)][0] // empty')
elif [ "$(echo "$warehouses" | jq '.warehouses | length')" == "1" ]
then
    warehouse=$(echo "$warehouses" | jq -c '.warehouses[0]')
else
    stored_path="$(secret_get DATABRICKS_HTTP_PATH "$profile" 2> /dev/null || true)"
    warehouse=$(echo "$warehouses" | jq -c --arg w "${stored_path##*/}" '[.warehouses[]? | select(.id == $w)][0] // empty')
fi
if [ -z "$warehouse" ]
then
    logerror "❌ pass the SQL warehouse with --warehouse <name or id>, the workspace has:"
    echo "$warehouses" | jq -r '.warehouses[]? | "   \(.name) (\(.id)): \(.state), \(.cluster_size)"' >&2
    [ "$(echo "$warehouses" | jq '.warehouses | length')" == "0" ] && logerror "   none: create one in SQL Warehouses (2X-Small, auto stop 10 minutes)"
    exit 1
fi
warehouse_id=$(echo "$warehouse" | jq -r '.id')
http_path=$(echo "$warehouse" | jq -r '.odbc_params.path // empty')
[ -n "$http_path" ] || http_path="/sql/1.0/warehouses/$warehouse_id"
server_hostname=$(echo "$warehouse" | jq -r '.odbc_params.hostname // empty')
[ -n "$server_hostname" ] || server_hostname="$databricks_host"
log "🏭 SQL warehouse $(echo "$warehouse" | jq -r '.name') ($warehouse_id, $(echo "$warehouse" | jq -r '.state')): http path $http_path"

# 3. the S3 staging bucket of the Delta Lake sink
[[ -n "$bucket" ]] || bucket=$(databricks_setup_value DATABRICKS_AWS_BUCKET_NAME "🪣 S3 staging bucket of the Delta Lake sink")
[[ -n "$bucket_region" ]] || bucket_region=$(databricks_setup_value DATABRICKS_AWS_BUCKET_REGION "🌍 its region")
[[ -n "$staging_key_id" ]] || staging_key_id=$(databricks_setup_value DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID "🔑 access key id allowed on the bucket")
[[ -n "$staging_secret" ]] || staging_secret=$(databricks_setup_value DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY "🔐 its secret access key" silent)
if type -P aws > /dev/null 2>&1 || docker info > /dev/null 2>&1
then
    if out=$(aws_key_id="$staging_key_id" aws_secret="$staging_secret" aws_token="" aws_region="$bucket_region" aws_account_cli s3api head-bucket --bucket "$bucket" 2>&1)
    then
        log "✅ staging bucket $bucket ($bucket_region) reachable with the staging keys"
    else
        logerror "❌ staging bucket $bucket: $(echo "$out" | grep -v '^$' | head -1) (wrong region, missing bucket, or keys not allowed): nothing stored"
        exit 1
    fi
else
    logwarn "⚠️ staging bucket $bucket not checked (neither the aws CLI nor docker)"
fi

# 4. store
if [[ -n "$no_store" ]]
then
    log "📋 --no-store, the values to export:"
    echo "export DATABRICKS_SERVER_HOSTNAME=\"$server_hostname\""
    echo "export DATABRICKS_HOST=\"$server_hostname\""
    echo "export DATABRICKS_HTTP_PATH=\"$http_path\""
    echo "export DATABRICKS_TOKEN=\"$databricks_token\""
    echo "export DATABRICKS_AWS_BUCKET_NAME=\"$bucket\""
    echo "export DATABRICKS_AWS_BUCKET_REGION=\"$bucket_region\""
    echo "export DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID=\"$staging_key_id\""
    echo "export DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY=\"$staging_secret\""
else
    playground secrets set DATABRICKS_SERVER_HOSTNAME --value "$server_hostname" --plain
    playground secrets set DATABRICKS_HOST --value "$server_hostname" --plain
    playground secrets set DATABRICKS_HTTP_PATH --value "$http_path" --plain
    playground secrets set DATABRICKS_TOKEN --value "$databricks_token" --secret
    playground secrets set DATABRICKS_AWS_BUCKET_NAME --value "$bucket" --plain
    playground secrets set DATABRICKS_AWS_BUCKET_REGION --value "$bucket_region" --plain
    playground secrets set DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID --value "$staging_key_id" --secret
    playground secrets set DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY --value "$staging_secret" --secret
    log "💾 stored DATABRICKS_SERVER_HOSTNAME, DATABRICKS_HOST, DATABRICKS_HTTP_PATH, DATABRICKS_TOKEN, DATABRICKS_AWS_BUCKET_NAME, DATABRICKS_AWS_BUCKET_REGION and DATABRICKS_AWS_STAGING_S3_*"
fi

log "🔏 the Delta Lake sink also needs these grants for $principal (run them in a SQL editor of the workspace):"
echo "   GRANT USE CATALOG ON CATALOG workspace TO \`$principal\`;"
echo "   GRANT USE SCHEMA, CREATE TABLE ON SCHEMA workspace.default TO \`$principal\`;"
echo "   GRANT READ FILES ON EXTERNAL LOCATION <the external location of s3://$bucket> TO \`$principal\`;"

log "🩺 the workspace now:"
DATABRICKS_SERVER_HOSTNAME="$server_hostname" DATABRICKS_HOST="$server_hostname" DATABRICKS_HTTP_PATH="$http_path" DATABRICKS_TOKEN="$databricks_token" \
DATABRICKS_AWS_BUCKET_NAME="$bucket" DATABRICKS_AWS_BUCKET_REGION="$bucket_region" \
DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID="$staging_key_id" DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY="$staging_secret" \
    playground account databricks check || true
log "🩺 check it any time with: playground account databricks check"
