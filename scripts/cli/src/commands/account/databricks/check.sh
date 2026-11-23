GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

for tool in jq curl
do
    if ! command -v $tool > /dev/null 2>&1
    then
        logerror "❌ $tool is not installed"
        exit 1
    fi
done

profile="$(get_active_secret_profile)"
function databricks_check_value () {
    secret_get "$1" "$profile" 2> /dev/null || true
}
host_raw="$(databricks_check_value DATABRICKS_SERVER_HOSTNAME)"
jdbc_host="$(databricks_check_value DATABRICKS_HOST)"
http_path="$(databricks_check_value DATABRICKS_HTTP_PATH)"
databricks_token="$(databricks_check_value DATABRICKS_TOKEN)"
bucket="$(databricks_check_value DATABRICKS_AWS_BUCKET_NAME)"
bucket_region="$(databricks_check_value DATABRICKS_AWS_BUCKET_REGION)"
staging_key_id="$(databricks_check_value DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID)"
staging_secret="$(databricks_check_value DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY)"

if [ -z "$host_raw" ]
then
    host_raw="$jdbc_host"
fi
missing=""
[ -z "$host_raw" ] && missing="$missing DATABRICKS_SERVER_HOSTNAME"
[ -z "$http_path" ] && missing="$missing DATABRICKS_HTTP_PATH"
[ -z "$databricks_token" ] && missing="$missing DATABRICKS_TOKEN"
if [ -n "$missing" ]
then
    logerror "❌ not set:$missing (all the Databricks examples need them)"
    logerror "👉 playground account databricks setup"
    exit 1
fi
databricks_host=$(databricks_normalize_host "$host_raw")
if [ "$databricks_host" != "$host_raw" ]
then
    logwarn "⚠️ DATABRICKS_SERVER_HOSTNAME is \"$host_raw\": the examples need the host only, \"$databricks_host\""
fi
nb_failed=0

# 1. the token
log "🔑 token of workspace $databricks_host"
databricks_api "/api/2.0/preview/scim/v2/Me"
me="$databricks_body"
if [ "$databricks_http_code" != "200" ]
then
    logerror "❌ the workspace refused the token: HTTP $databricks_http_code $(echo "$me" | jq -r '.detail // .message // empty' 2> /dev/null | head -1)"
    cause=$(databricks_explain_http "$databricks_http_code" "$databricks_body")
    [ -n "$cause" ] && logerror "   $cause"
    exit 1
fi
principal=$(echo "$me" | jq -r '.userName // .displayName')
log "✅ token works: $principal (the principal the grants of the examples must target)"

# 2. the SQL warehouse (or cluster) of DATABRICKS_HTTP_PATH
if [[ "$http_path" == */warehouses/* ]]
then
    warehouse_id="${http_path##*/}"
    databricks_api "/api/2.0/sql/warehouses/$warehouse_id"
warehouse="$databricks_body"
    if [ "$databricks_http_code" == "200" ]
    then
        name=$(echo "$warehouse" | jq -r '.name')
        state=$(echo "$warehouse" | jq -r '.state')
        details="$(echo "$warehouse" | jq -r '"\(.cluster_size // "?"), \(if .enable_serverless_compute then "serverless" else (.warehouse_type // "classic") end), auto stop \(.auto_stop_mins // "?") min"')"
        case "$state" in
            RUNNING|STARTING)
                echo -e "✅ ${GREEN}SQL warehouse${NC} $name ($warehouse_id): $state, $details" ;;
            STOPPED|STOPPING)
                echo -e "✅ ${GREEN}SQL warehouse${NC} $name ($warehouse_id): $state (the examples start it), $details" ;;
            *)
                echo -e "❌ ${RED}SQL warehouse${NC} $name ($warehouse_id): $state        👉 playground account databricks setup (pick another warehouse)"
                nb_failed=$((nb_failed + 1)) ;;
        esac
    else
        echo -e "❌ ${RED}SQL warehouse${NC} $warehouse_id of DATABRICKS_HTTP_PATH: HTTP $databricks_http_code $(echo "$warehouse" | jq -r '.message // empty' 2> /dev/null)"
        echo "      wrong DATABRICKS_HTTP_PATH (SQL Warehouses > <warehouse> > Connection details > HTTP path)        👉 playground account databricks setup"
        nb_failed=$((nb_failed + 1))
    fi
else
    cluster_id="${http_path##*/}"
    databricks_api "/api/2.0/clusters/get?cluster_id=$cluster_id"
cluster="$databricks_body"
    if [ "$databricks_http_code" == "200" ]
    then
        echo -e "✅ ${GREEN}Cluster${NC} $(echo "$cluster" | jq -r '.cluster_name') ($cluster_id): $(echo "$cluster" | jq -r '.state')"
    else
        echo -e "❌ ${RED}Cluster${NC} $cluster_id of DATABRICKS_HTTP_PATH: HTTP $databricks_http_code"
        nb_failed=$((nb_failed + 1))
    fi
fi
echo -e "ℹ️  a workspace whose trial or plan ended refuses to start any compute (denyReason INACTIVE): the examples print it when they start the warehouse"

# 3. the JDBC examples read DATABRICKS_HOST
if [ -z "$jdbc_host" ]
then
    echo -e "⚠️ ${YELLOW}DATABRICKS_HOST${NC} not set: needed by connect-jdbc-databricks-sink / -source        👉 playground account databricks setup"
fi

# 4. the S3 staging bucket of the Delta Lake sink, with the staging keys (like the connector)
if [ -z "$bucket" ] || [ -z "$bucket_region" ] || [ -z "$staging_key_id" ] || [ -z "$staging_secret" ]
then
    echo -e "❌ ${RED}Staging bucket${NC}: DATABRICKS_AWS_BUCKET_NAME / _REGION / DATABRICKS_AWS_STAGING_S3_* not all set        👉 playground account databricks setup"
    echo "      needed by: connect-databricks-delta-lake-sink, fm-databricks-delta-lake-sink"
    nb_failed=$((nb_failed + 1))
elif ! type -P aws > /dev/null 2>&1 && ! docker info > /dev/null 2>&1
then
    echo -e "⚠️ ${YELLOW}Staging bucket${NC} $bucket: not checked (neither the aws CLI nor docker)"
else
    if out=$(aws_key_id="$staging_key_id" aws_secret="$staging_secret" aws_token="" aws_region="$bucket_region" aws_account_cli s3api head-bucket --bucket "$bucket" 2>&1)
    then
        echo -e "✅ ${GREEN}Staging bucket${NC} $bucket ($bucket_region) reachable with the staging keys"
    else
        code=$(aws_account_error_code "$out")
        if echo "$out" | grep -q "(301)"
        then
            echo -e "❌ ${RED}Staging bucket${NC} $bucket is not in $bucket_region: fix DATABRICKS_AWS_BUCKET_REGION"
        elif echo "$out" | grep -q "(404)"
        then
            echo -e "❌ ${RED}Staging bucket${NC} $bucket does not exist"
        elif echo "$out" | grep -q "(403)"
        then
            echo -e "❌ ${RED}Staging bucket${NC} $bucket: access denied for the staging keys (wrong keys, or no s3 permission on the bucket)"
        else
            echo -e "❌ ${RED}Staging bucket${NC} $bucket: ${code:-$(echo "$out" | head -1)}"
        fi
        echo "      needed by: connect-databricks-delta-lake-sink, fm-databricks-delta-lake-sink"
        nb_failed=$((nb_failed + 1))
    fi
fi
echo -e "ℹ️  the Delta Lake sink also needs, for $principal: USE CATALOG / USE SCHEMA / CREATE TABLE on workspace.default, and READ FILES on the external location of s3://${bucket:-<bucket>} (a lag of 0 does not prove success: failed COPY INTO only show in Query History)"

echo ""
if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed check(s) failed: the examples listed above would fail"
else
    log "🎉 the Databricks workspace is ready for the Databricks examples"
fi
