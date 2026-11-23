project="${args[--project]}"
account="${args[--account]}"
service_account="${args[--service-account]}"
new_key="${args[--new-key]}"
dry_run="${args[--dry-run]}"
no_store="${args[--no-store]}"
keyfile_arg="${args[--keyfile]}"

function gcp_setup_store () {
    store_project="$1"
    store_keyfile="$2"
    if [[ -n "$no_store" ]]
    then
        log "📋 --no-store, the values to export:"
        echo "export GCP_PROJECT=\"$store_project\""
        echo "export GCP_KEYFILE_CONTENT=\$(jq -aRs . \"$store_keyfile\" | sed 's/^\"//' | sed 's/\"\$//')"
    else
        playground secrets set GCP_PROJECT --value "$store_project" --plain
        playground secrets set GCP_KEYFILE_CONTENT --value "$(gcp_keyfile_to_content "$store_keyfile")" --secret
        log "💾 stored GCP_PROJECT and GCP_KEYFILE_CONTENT"
    fi
}

# a keyfile.json left in an example folder wins over GCP_KEYFILE_CONTENT
function gcp_setup_warn_stale_keyfiles () {
    private_key_id=$(jq -r '.private_key_id' "$1")
    stale=""
    for f in "$root_folder"/connect/*/keyfile.json "$root_folder"/ccloud/*/keyfile.json
    do
        [ -f "$f" ] || continue
        if [ "$(jq -r '.private_key_id // empty' "$f" 2> /dev/null)" != "$private_key_id" ]
        then
            stale="$stale ${f#$root_folder/}"
        fi
    done
    if [[ -n "$stale" ]]
    then
        logwarn "⚠️ these example folders have their own keyfile.json, another key, used instead of GCP_KEYFILE_CONTENT:"
        for f in $stale
        do
            logwarn "   $f"
        done
        remove=""
        if [ -t 0 ] && [[ ! -n "$no_store" ]]
        then
            read -r -p "🗑️ remove them, so that the examples use the stored key? [y/N] " remove
        fi
        if [[ "$remove" == "y" ]] || [[ "$remove" == "Y" ]]
        then
            (cd "$root_folder" && rm -f $stale)
            log "🗑️ removed$stale"
        else
            logwarn "   to use the stored key everywhere: (cd $root_folder && rm$stale)"
        fi
    fi
}

# an existing key (shared project): check it, save it, store it, change nothing in the project
if [[ -n "$keyfile_arg" ]]
then
    for tool in jq openssl curl
    do
        if ! command -v $tool > /dev/null 2>&1
        then
            logerror "❌ $tool is not installed"
            exit 1
        fi
    done
    if [ "$(jq -r '.type // empty' "$keyfile_arg" 2> /dev/null)" != "service_account" ]
    then
        logerror "❌ $keyfile_arg is not a service account key file (JSON with \"type\": \"service_account\")"
        exit 1
    fi
    client_email=$(jq -r '.client_email' "$keyfile_arg")
    if [[ ! -n "$project" ]]
    then
        project=$(jq -r '.project_id // empty' "$keyfile_arg")
    fi
    if [[ -n "$dry_run" ]]
    then
        log "🧪 --dry-run: nothing changed. setup would check the key of $client_email, save it in $(gcp_user_keyfile_path) and store GCP_PROJECT=$project and GCP_KEYFILE_CONTENT"
        exit 0
    fi
    token_out=$(gcp_jwt_token "$keyfile_arg") || {
        logerror "❌ the key of $client_email can't log in: $token_out"
        logerror "   playground account gcp check --keyfile $keyfile_arg explains why"
        exit 1
    }
    log "✅ the key of $client_email can log in"

    keyfile="$(gcp_user_keyfile_path)"
    mkdir -p "$(dirname "$keyfile")"
    if [ -f "$keyfile" ] && ! cmp -s "$keyfile" "$keyfile_arg"
    then
        cp -p "$keyfile" "$keyfile.bak"
        logwarn "💾 previous key file kept as $keyfile.bak"
    fi
    if ! cmp -s "$keyfile" "$keyfile_arg" 2> /dev/null
    then
        (umask 077 && cat "$keyfile_arg" > "$keyfile")
    fi
    chmod 600 "$keyfile"
    log "🔑 key $(jq -r '.private_key_id' "$keyfile" | cut -c1-12)… saved in $keyfile"

    gcp_setup_store "$project" "$keyfile"
    gcp_setup_warn_stale_keyfiles "$keyfile"
    log "🩺 what this key can do in $project:"
    playground account gcp check --keyfile "$keyfile" --project "$project"
    exit $?
fi

if [[ ! "$service_account" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
then
    logerror "❌ --service-account $service_account is not a valid name (6 to 30 lowercase letters, digits and dashes, starting with a letter)"
    exit 1
fi

if [[ ! -n "$project" ]]
then
    project="$(secret_get GCP_PROJECT "$(get_active_secret_profile)" 2> /dev/null || true)"
fi

apis=$(gcp_setup_apis | cut -d'|' -f1 | tr '\n' ' ')
if [[ -n "$dry_run" ]]
then
    sa_email="$service_account@${project:-<project>}.iam.gserviceaccount.com"
    log "🧪 --dry-run: nothing changed. On project ${project:-<project>}, setup would:"
    log "🔌 enable the APIs:"
    gcp_setup_apis | while IFS='|' read -r api what examples
    do
        printf '   %-38s %-18s %s\n' "$api" "$what" "$examples"
    done
    log "🤖 create the service account $sa_email (or reuse it) and grant it:"
    gcp_setup_roles | while IFS='|' read -r role why
    do
        printf '   %-38s %s\n' "$role" "$why"
    done
    log "🔑 create a key in $(gcp_user_keyfile_path) (or reuse it while it still exists)"
    log "💾 store GCP_PROJECT and GCP_KEYFILE_CONTENT with playground secrets set"
    exit 0
fi

gcp_setup_require_tools

# under $HOME: shared with docker desktop (not /private/tmp), and the new key never lands in a shared folder
mkdir -p "${PLAYGROUND_SECRETS_DIR:-$HOME/.config/kafka-docker-playground}"
gcp_tmp_dir=$(mktemp -d "${PLAYGROUND_SECRETS_DIR:-$HOME/.config/kafka-docker-playground}/tmp-gcp-setup.XXXXXX")
chmod 700 "$gcp_tmp_dir"
trap 'rm -rf "$gcp_tmp_dir"' EXIT

# 1. the account
if [[ -n "$account" ]]
then
    # your own gcloud, already logged in
    if [ "$gcp_gcloud_mode" == "local" ]
    then
        gcp_gcloud_config=""
    else
        gcp_gcloud_config="$HOME/.config/gcloud"
    fi
    if ! gcp_gcloud auth list --format="value(account)" 2> /dev/null | grep -qx "$account"
    then
        logerror "❌ gcloud is not logged into $account (gcloud auth list)"
        logerror "   log in with: gcloud auth login $account, or run without --account"
        exit 1
    fi
    gcp_gcloud_account="$account"
else
    gcp_gcloud_config="${PLAYGROUND_SECRETS_DIR:-$HOME/.config/kafka-docker-playground}/gcloud"
    mkdir -p "$gcp_gcloud_config"
    account=$(gcp_gcloud config get-value account 2> /dev/null | tail -1) || true
    if [[ ! -n "$account" ]] || ! gcp_gcloud auth print-access-token > /dev/null 2>&1
    then
        # local gcloud logs in through the browser; the docker image prints a link and reads a code from the terminal
        if [ "$gcp_gcloud_mode" != "local" ] && [ ! -t 0 ]
        then
            logerror "❌ logging in without a local gcloud needs a terminal to paste the code: run it in a terminal, or pass --account with an account your gcloud is logged into"
            exit 1
        fi
        log "🌐 log into Google Cloud in the browser, with the account that owns the project"
        if [ "$gcp_gcloud_mode" == "local" ]
        then
            gcp_gcloud_interactive=1 gcp_gcloud auth login --quiet || { logerror "❌ gcloud auth login failed"; exit 1; }
        else
            log "   open the link below, then paste the verification code"
            gcp_gcloud_interactive=1 gcp_gcloud auth login --no-launch-browser --quiet || { logerror "❌ gcloud auth login failed"; exit 1; }
        fi
        account=$(gcp_gcloud config get-value account 2> /dev/null | tail -1) || true
    fi
fi
log "👤 account $account"

# 2. the project
if [[ ! -n "$project" ]]
then
    projects=$(gcp_gcloud projects list --format="value(projectId)" 2> /dev/null) || true
    if [ "$(echo "$projects" | awk 'NF' | wc -l | tr -d ' ')" == "1" ]
    then
        project="$projects"
    else
        logerror "❌ pass the project with --project, $account can see:"
        echo "$projects" | awk 'NF { print "   " $0 }' | head -20 >&2
        logerror "   no project yet? create one with billing enabled: https://console.cloud.google.com/projectcreate"
        exit 1
    fi
fi
if ! gcp_gcloud projects describe "$project" --format="value(projectNumber)" > "$gcp_tmp_dir/project.out" 2>&1
then
    logerror "❌ project $project not found, or $account can't see it:"
    sed 's/^/   /' "$gcp_tmp_dir/project.out" | head -5 >&2
    exit 1
fi
log "🗂️ project $project"

# 3. the APIs
log "🔌 enabling the APIs of the examples (a minute the first time)"
if ! gcp_gcloud services enable $apis --project "$project" --quiet > "$gcp_tmp_dir/enable.out" 2>&1
then
    # one by one, to tell which one fails (often: billing not enabled)
    failed_apis=""
    for api in $apis
    do
        if ! gcp_gcloud services enable "$api" --project "$project" --quiet > "$gcp_tmp_dir/enable-one.out" 2>&1
        then
            failed_apis="$failed_apis $api"
            logwarn "   ⚠️ $api: $(grep -m1 -iE 'error|denied|billing' "$gcp_tmp_dir/enable-one.out" | cut -c1-200)"
        fi
    done
    if [[ " $failed_apis " == *" iam.googleapis.com "* ]] || [[ " $failed_apis " == *" cloudresourcemanager.googleapis.com "* ]]
    then
        logerror "❌ IAM and Resource Manager APIs are required to create the service account"
        exit 1
    fi
    if [[ -n "$failed_apis" ]]
    then
        logwarn "⚠️ not enabled:$failed_apis (the examples using them will fail). Billing enabled on $project? https://console.cloud.google.com/billing/linkedaccount?project=$project"
    fi
fi
billing=$(gcp_gcloud billing projects describe "$project" --format="value(billingEnabled)" 2> /dev/null | tail -1) || true
if [ "$billing" == "False" ]
then
    logwarn "⚠️ billing is not enabled on $project: Spanner, Bigtable, Dataproc and Cloud Functions need it"
    logwarn "   https://console.cloud.google.com/billing/linkedaccount?project=$project"
fi

# 4. the service account and its roles
sa_email="$service_account@$project.iam.gserviceaccount.com"
if gcp_gcloud iam service-accounts describe "$sa_email" --project "$project" > /dev/null 2>&1
then
    log "🤖 service account $sa_email already exists"
else
    log "🤖 creating service account $sa_email"
    if ! gcp_gcloud iam service-accounts create "$service_account" --project "$project" \
        --display-name "kafka-docker-playground" \
        --description "created by playground account gcp setup, used by the GCP examples" > "$gcp_tmp_dir/sa.out" 2>&1
    then
        logerror "❌ failed to create the service account:"
        sed 's/^/   /' "$gcp_tmp_dir/sa.out" | head -5 >&2
        exit 1
    fi
fi

existing_roles=$(gcp_gcloud projects get-iam-policy "$project" --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:$sa_email" --format="value(bindings.role)" 2> /dev/null) || true
nb_granted=0
while IFS='|' read -r role why
do
    if echo "$existing_roles" | grep -qx "$role"
    then
        continue
    fi
    # a new service account takes a few seconds to be visible to IAM
    attempt=1
    until gcp_gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:$sa_email" \
        --role "$role" --condition=None --quiet --format=none > "$gcp_tmp_dir/role.out" 2>&1 < /dev/null
    do
        if [ $attempt -ge 6 ]
        then
            logerror "❌ failed to grant $role to $sa_email:"
            sed 's/^/   /' "$gcp_tmp_dir/role.out" | head -5 >&2
            logerror "   your account needs the Owner or Project IAM Admin role on $project"
            exit 1
        fi
        attempt=$((attempt + 1))
        sleep 5
    done
    nb_granted=$((nb_granted + 1))
done < <(gcp_setup_roles)
log "🎭 $sa_email has the $(gcp_setup_roles | wc -l | tr -d ' ') roles of the examples ($nb_granted granted now)"

# 5. the key
keyfile="$(gcp_user_keyfile_path)"
mkdir -p "$(dirname "$keyfile")"
key_ids=$(gcp_gcloud iam service-accounts keys list --iam-account "$sa_email" --project "$project" \
    --managed-by user --format="value(name.basename())" 2> /dev/null) || true
reuse=""
if [[ ! -n "$new_key" ]] && [ -f "$keyfile" ] && [ "$(jq -r '.client_email // empty' "$keyfile" 2> /dev/null)" == "$sa_email" ]
then
    if echo "$key_ids" | grep -qx "$(jq -r '.private_key_id // empty' "$keyfile")"
    then
        reuse=1
    fi
fi
if [[ -n "$reuse" ]]
then
    log "🔑 reusing the key in $keyfile ($(jq -r '.private_key_id' "$keyfile" | cut -c1-12)…)"
else
    nb_keys=$(echo "$key_ids" | awk 'NF' | wc -l | tr -d ' ')
    if [ "$nb_keys" -ge 10 ]
    then
        logerror "❌ $sa_email already has 10 keys, the maximum: delete old ones first"
        logerror "   gcloud iam service-accounts keys list --iam-account $sa_email"
        logerror "   gcloud iam service-accounts keys delete <key id> --iam-account $sa_email"
        exit 1
    fi
    log "🔑 creating a key for $sa_email"
    if ! gcp_gcloud iam service-accounts keys create "$gcp_tmp_dir/key.json" --iam-account "$sa_email" --project "$project" > "$gcp_tmp_dir/key.out" 2>&1
    then
        logerror "❌ failed to create a key:"
        sed 's/^/   /' "$gcp_tmp_dir/key.out" | head -5 >&2
        if grep -q "disableServiceAccountKeyCreation" "$gcp_tmp_dir/key.out"
        then
            logerror "   the organization policy iam.disableServiceAccountKeyCreation forbids keys in this project:"
            logerror "   use a project outside that organization (a personal one), or ask an admin for an exception"
        fi
        exit 1
    fi
    if [ -f "$keyfile" ]
    then
        cp -p "$keyfile" "$keyfile.bak"
        logwarn "💾 previous key file kept as $keyfile.bak"
    fi
    (umask 077 && cat "$gcp_tmp_dir/key.json" > "$keyfile")
    chmod 600 "$keyfile"
    log "🔑 key $(jq -r '.private_key_id' "$keyfile" | cut -c1-12)… saved in $keyfile"
    if [ "$nb_keys" -ge 7 ]
    then
        logwarn "⚠️ $sa_email now has $((nb_keys + 1)) keys (max 10): delete the ones you no longer use (gcloud iam service-accounts keys list --iam-account $sa_email)"
    fi
fi

# 6. wait until the key can log in (a new key takes a few seconds)
deadline=$((SECONDS + 120))
until gcp_jwt_token "$keyfile" > "$gcp_tmp_dir/token.out"
do
    if [ $SECONDS -ge $deadline ]
    then
        logerror "❌ the key still can't log in after 120 seconds: $(cat "$gcp_tmp_dir/token.out")"
        exit 1
    fi
    sleep 10
done
log "✅ the key of $sa_email can log in"

# 7. store
gcp_setup_store "$project" "$keyfile"
gcp_setup_warn_stale_keyfiles "$keyfile"

# 8. check, waiting for the roles granted now to apply (IAM takes up to 2 minutes)
check_out="$gcp_tmp_dir/check.out"
if [ $nb_granted -gt 0 ]
then
    log "⏳ waiting for the $nb_granted new roles to apply (up to 2 minutes, max 180 seconds)"
    deadline=$((SECONDS + 180))
    until playground account gcp check --keyfile "$keyfile" --project "$project" > "$check_out" 2>&1 && grep -q "ready for the GCP examples" "$check_out"
    do
        if [ $SECONDS -ge $deadline ]
        then
            break
        fi
        sleep 20
    done
else
    playground account gcp check --keyfile "$keyfile" --project "$project" > "$check_out" 2>&1 || true
fi
log "🩺 what the key can do in $project:"
grep -v "functions found" "$check_out"
log "🩺 check it any time with: playground account gcp check"
log "✋ two examples need something setup can't create, see https://kafka-docker-playground.io/#/gcp:"
log "   cloud functions sink: a function (function-1 / function-11 in europe-west2)"
log "   firebase sink and source: the default Realtime Database of the project"
