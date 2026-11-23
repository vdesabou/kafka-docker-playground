project="${args[--project]}"
keyfile_arg="${args[--keyfile]}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

for tool in jq openssl curl
do
    if ! command -v $tool > /dev/null 2>&1
    then
        logerror "❌ $tool is not installed"
        exit 1
    fi
done

gcp_tmp_dir=$(mktemp -d -t playground-gcp-check.XXXXXX)
chmod 700 "$gcp_tmp_dir"
trap 'rm -rf "$gcp_tmp_dir"' EXIT
keyfile="$gcp_tmp_dir/keyfile.json"

# same resolution as an example (without a keyfile.json in its folder): GCP_KEYFILE_CONTENT, exported or
# in the active secrets profile, then the key file of 'playground account gcp setup'
profile="$(get_active_secret_profile)"
if [[ -n "$keyfile_arg" ]]
then
    cp "$keyfile_arg" "$keyfile"
    key_source="$keyfile_arg"
else
    content="$(secret_get GCP_KEYFILE_CONTENT "$profile" 2> /dev/null || true)"
    if [ -n "$content" ]
    then
        gcp_content_to_keyfile "$content" > "$keyfile"
        key_source="GCP_KEYFILE_CONTENT"
    elif [ -f "$(gcp_user_keyfile_path)" ]
    then
        cp "$(gcp_user_keyfile_path)" "$keyfile"
        key_source="$(gcp_user_keyfile_path)"
        logwarn "⚠️ GCP_KEYFILE_CONTENT is not set, the examples won't find this key: run playground account gcp setup"
    else
        logerror "❌ no key: GCP_KEYFILE_CONTENT is not set and $(gcp_user_keyfile_path) is missing"
        logerror "👉 playground account gcp setup creates a service account and its key"
        exit 1
    fi
fi
if [ "$(jq -r '.type // empty' "$keyfile" 2> /dev/null)" != "service_account" ]
then
    logerror "❌ $key_source is not a service account key file (JSON with \"type\": \"service_account\")"
    exit 1
fi
client_email=$(jq -r '.client_email' "$keyfile")
key_project=$(jq -r '.project_id // empty' "$keyfile")
private_key_id=$(jq -r '.private_key_id // empty' "$keyfile")

if [[ ! -n "$project" ]]
then
    project="$(secret_get GCP_PROJECT "$profile" 2> /dev/null || true)"
fi
if [[ ! -n "$project" ]]
then
    project="$key_project"
    logwarn "⚠️ GCP_PROJECT is not set (the examples require it), using the project of the key: $project"
elif [ "$project" != "$key_project" ]
then
    logwarn "⚠️ GCP_PROJECT is $project but the key belongs to project $key_project: some examples use one, some the other"
fi

# 1. login
log "🔑 OAuth login of $client_email (key ${private_key_id:0:12}…, from $key_source)"
if ! gcp_jwt_token "$keyfile" > "$gcp_tmp_dir/token.out"
then
    error=$(jq -r '.error // empty' "$gcp_tmp_dir/token.out" 2> /dev/null)
    description=$(jq -r '.error_description // empty' "$gcp_tmp_dir/token.out" 2> /dev/null)
    if [[ "$error" == "invalid_key" ]]
    then
        logerror "❌ $description"
    else
        logerror "❌ Google rejected the login: ${error:-$(cat "$gcp_tmp_dir/token.out")} ${description}"
    fi
    case "$description" in
        *"Invalid JWT Signature"*)
            logerror "   the key was deleted or disabled: run playground account gcp setup (it creates a new one)" ;;
        *"account not found"*)
            logerror "   the service account $client_email does not exist (deleted?): run playground account gcp setup" ;;
        *"Invalid JWT"*|*"iat"*|*"exp"*)
            logerror "   the clock of this machine is off: check the date" ;;
        *)
            if [[ "$error" == "invalid_key" ]]
            then
                logerror "   the private_key of the key file is damaged: GCP_KEYFILE_CONTENT must be the output of jq -aRs . keyfile.json without the surrounding quotes"
            elif ! grep -q '{' "$gcp_tmp_dir/token.out"
            then
                logerror "   oauth2.googleapis.com is not reachable from this machine (proxy, firewall?)"
            fi ;;
    esac
    exit 1
fi
log "✅ login works"

# 2. one read-only call per API: name|url|examples|role
function gcp_check_probe () {
    name="$1"
    url="$2"
    examples="$3"
    role="$4"
    api="$5"
    code=$(curl -sS -m 30 -o "$gcp_tmp_dir/probe.json" -w '%{http_code}' -H "Authorization: Bearer $gcp_access_token" "$url" 2> /dev/null) || code="000"
    if [ "$code" == "200" ]
    then
        echo -e "✅ ${GREEN}$name${NC}"
        return 0
    fi
    message=$(jq -r '.error.message // empty' "$gcp_tmp_dir/probe.json" 2> /dev/null | head -1 | cut -c1-160)
    reasons=$(jq -r '[.error.details[]?.reason // empty, .error.status // empty] | join(" ")' "$gcp_tmp_dir/probe.json" 2> /dev/null)
    if [[ "$reasons" == *SERVICE_DISABLED* ]] || [[ "$message" == *"has not been used in project"* ]] || [[ "$message" == *"is disabled"* ]]
    then
        echo -e "❌ ${RED}$name${NC}: the API is not enabled        👉 gcloud services enable $api --project $project"
    elif [[ "$reasons" == *BILLING_DISABLED* ]] || [[ "$message" == *"billing"* ]] || [[ "$message" == *"Billing"* ]]
    then
        echo -e "❌ ${RED}$name${NC}: billing is not enabled on $project        👉 https://console.cloud.google.com/billing/linkedaccount?project=$project"
    elif [ "$code" == "403" ]
    then
        echo -e "❌ ${RED}$name${NC}: permission denied, missing role $role        👉 playground account gcp setup"
    else
        echo -e "❌ ${RED}$name${NC}: HTTP $code ${message}"
    fi
    echo "      needed by: $examples"
    [ -n "$message" ] && [ "$code" == "403" ] && echo "      Google says: $message"
    nb_failed=$((nb_failed + 1))
    return 1
}

nb_failed=0
gcp_check_probe "Cloud Storage" "https://storage.googleapis.com/storage/v1/b?project=$project&maxResults=1" \
    "gcs sink and source, dataproc sink" "roles/storage.admin" storage.googleapis.com || true
gcp_check_probe "Pub/Sub" "https://pubsub.googleapis.com/v1/projects/$project/topics?pageSize=1" \
    "pubsub source and sink" "roles/pubsub.admin" pubsub.googleapis.com || true
gcp_check_probe "BigQuery" "https://bigquery.googleapis.com/bigquery/v2/projects/$project/datasets?maxResults=1" \
    "bigquery sink and source" "roles/bigquery.admin" bigquery.googleapis.com || true
gcp_check_probe "Spanner" "https://spanner.googleapis.com/v1/projects/$project/instances?pageSize=1" \
    "spanner sink, debezium spanner source" "roles/spanner.admin" spanner.googleapis.com || true
gcp_check_probe "Bigtable" "https://bigtableadmin.googleapis.com/v2/projects/$project/instances" \
    "bigtable sink" "roles/bigtable.admin" bigtableadmin.googleapis.com || true
gcp_check_probe "Firestore" "https://firestore.googleapis.com/v1/projects/$project/databases" \
    "firestore sink" "roles/datastore.owner" firestore.googleapis.com || true
gcp_check_probe "Dataproc" "https://dataproc.googleapis.com/v1/projects/$project/regions/us-east1/clusters?pageSize=1" \
    "dataproc sink" "roles/dataproc.editor" dataproc.googleapis.com || true

# the function the cloud functions examples call must exist
if gcp_check_probe "Cloud Functions" "https://cloudfunctions.googleapis.com/v2/projects/$project/locations/-/functions?pageSize=100" \
    "cloud functions sink (only to check that its function exists)" "roles/cloudfunctions.viewer" cloudfunctions.googleapis.com
then
    functions=$(jq -r '.functions[]?.name' "$gcp_tmp_dir/probe.json" | sed -E 's|.*/locations/([^/]+)/functions/(.*)|\2 (\1)|')
    for wanted in "function-1|connect-gcp-cloud-functions-sink" "function-11|fm-gcp-cloud-functions-gen2-sink"
    do
        fn="${wanted%%|*}"
        example="${wanted##*|}"
        if echo "$functions" | grep -q "^$fn (europe-west2)$"
        then
            echo "   ✅ function $fn in europe-west2 ($example)"
        else
            echo "   ⚠️ no function $fn in europe-west2, needed by $example unless GCP_FUNCTION_FUNCTION / GCP_FUNCTION_REGION point to another one"
        fi
    done
    if [ -n "$functions" ]
    then
        echo "      functions found: $(echo "$functions" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    fi
fi

# the firebase examples write to the default Realtime Database of the project
if gcp_check_probe "Realtime Database" "https://firebasedatabase.googleapis.com/v1beta/projects/$project/locations/-/instances" \
    "firebase sink and source" "roles/firebasedatabase.admin" firebasedatabase.googleapis.com
then
    rtdb=$(jq -r '.instances[]? | select(.type == "DEFAULT_DATABASE") | .databaseUrl' "$gcp_tmp_dir/probe.json")
    if [ -n "$rtdb" ]
    then
        echo "   ✅ default database $rtdb"
    else
        echo "   ⚠️ no default Realtime Database: create it in the Firebase console (Build > Realtime Database), needed by the firebase examples"
    fi
fi

# 3. project permissions of the examples that create IAM bindings or Dataproc clusters
permissions='["resourcemanager.projects.setIamPolicy","iam.serviceAccounts.actAs"]'
code=$(curl -sS -m 30 -o "$gcp_tmp_dir/perms.json" -w '%{http_code}' -X POST -H "Authorization: Bearer $gcp_access_token" \
    -H "Content-Type: application/json" -d "{\"permissions\": $permissions}" \
    "https://cloudresourcemanager.googleapis.com/v1/projects/$project:testIamPermissions" 2> /dev/null) || code="000"
if [ "$code" == "200" ]
then
    granted=$(jq -r '.permissions[]?' "$gcp_tmp_dir/perms.json")
    if echo "$granted" | grep -qx "resourcemanager.projects.setIamPolicy"
    then
        echo -e "✅ ${GREEN}Project IAM${NC}: can grant roles (firestore sink)"
    else
        echo -e "❌ ${RED}Project IAM${NC}: can't grant roles, missing role roles/resourcemanager.projectIamAdmin        👉 playground account gcp setup"
        echo "      needed by: firestore sink"
        nb_failed=$((nb_failed + 1))
    fi
    if echo "$granted" | grep -qx "iam.serviceAccounts.actAs"
    then
        echo -e "✅ ${GREEN}Service Account User${NC}: can start Dataproc clusters"
    else
        # only a project level grant is visible here, not one on the compute service account itself
        echo -e "⚠️ ${YELLOW}Service Account User${NC}: no roles/iam.serviceAccountUser on the project (fine if it is granted on the default compute service account)        👉 playground account gcp setup"
        echo "      needed by: dataproc sink"
    fi
else
    message=$(jq -r '.error.message // empty' "$gcp_tmp_dir/perms.json" 2> /dev/null | head -1 | cut -c1-160)
    echo -e "⚠️ ${YELLOW}Project IAM${NC}: can't test the project permissions (HTTP $code ${message})"
fi

echo ""
if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed check(s) failed: the examples listed above would fail (new roles can take 2 minutes to apply)"
else
    log "🎉 project $project is ready for the GCP examples"
fi
