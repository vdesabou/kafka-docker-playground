target_org="${args[--target-org]}"
alias="${args[--alias]}"
instance_url="${args[--instance-url]%/}"
app_name="${args[--app-name]}"
suffix="${args[--suffix]}"
account2="${args[--account2]}"
keystore="${args[--keystore]}"
generate_keystore="${args[--generate-keystore]}"
max_wait="${args[--max-wait]}"
dry_run="${args[--dry-run]}"
no_store="${args[--no-store]}"

if [[ ! "$app_name" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || [[ "$app_name" == *__* ]] || [[ "$app_name" == *_ ]]
then
    logerror "❌ --app-name $app_name is not a valid API name (letters, digits and single underscores, starting with a letter)"
    exit 1
fi
suffix="$(echo "$suffix" | tr '[:lower:]' '[:upper:]')"
if [[ -n "$suffix" ]] && [[ ! "$suffix" =~ ^[A-Z0-9_]+$ ]]
then
    logerror "❌ --suffix $suffix must only contain letters, digits and underscores"
    exit 1
fi
salesforce_setup_require_tools

sf_tmp_dir=$(mktemp -d -t playground-salesforce-setup.XXXXXX)
trap 'rm -rf "$sf_tmp_dir"' EXIT

salesforce_setup_resolve_keystore "$keystore" "$generate_keystore"

# 1. the org
if [[ ! -n "$target_org" ]]
then
    if [ ! -t 0 ]
    then
        logerror "❌ logging in needs a browser: run it in a terminal, or log in first (sf org login web --alias $alias) and pass --target-org $alias"
        exit 1
    fi
    log "🌐 log into your Salesforce org in the browser that opens ($instance_url), then click Allow"
    if ! sf org login web --alias "$alias" --instance-url "$instance_url"
    then
        logerror "❌ sf org login web failed"
        exit 1
    fi
    target_org="$alias"
fi
salesforce_setup_resolve_org "$target_org"
log "☁️ org $sf_org_id ($sf_instance_url), user $sf_username"

user_json=$(sf data query --query "SELECT Email, Profile.Name FROM User WHERE Username = '$sf_username'" --target-org "$target_org" --json 2> /dev/null) || true
profile=$(echo "$user_json" | jq -r '.result.records[0].Profile.Name // empty')
email=$(echo "$user_json" | jq -r '.result.records[0].Email // empty')
if [ -z "$profile" ]
then
    logerror "❌ could not read the profile of $sf_username"
    echo "$user_json" | jq -r '.message // empty' >&2
    exit 1
fi
log "👤 the External Client App is pre-authorized for profile \"$profile\""

# 2. the metadata, rendered from scripts/salesforce-org-setup/metadata
function xml_escape () {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}
profile_xml=$(xml_escape "$profile")
email_xml=$(xml_escape "${email:-$sf_username}")

output_dir="/tmp/playground-salesforce-setup/$app_name"
rm -rf "$output_dir"
template_dir="$root_folder/scripts/salesforce-org-setup/metadata"
for template in $(cd "$template_dir" && find . -type f)
do
    out="$output_dir/${template//@@APP_NAME@@/$app_name}"
    mkdir -p "$(dirname "$out")"
    content=$(cat "$template_dir/$template")
    # quoted replacements: bash 5.2 would otherwise expand & in them
    content="${content//@@APP_NAME@@/"$app_name"}"
    content="${content//@@CERTIFICATE@@/"$sf_certificate"}"
    content="${content//@@PROFILE@@/"$profile_xml"}"
    content="${content//@@CONTACT_EMAIL@@/"$email_xml"}"
    printf '%s\n' "$content" > "$out"
done
log "📝 metadata rendered in $output_dir"

if [[ -n "$dry_run" ]]
then
    log "🧪 --dry-run: nothing deployed. To deploy it yourself:"
    log "   sf project deploy start --metadata-dir $output_dir/app --target-org $target_org --wait 15"
    log "   sf project deploy start --metadata-dir $output_dir/policies --target-org $target_org --wait 15"
    exit 0
fi

# 3. deploy: the app first, then its policies, which only exist once the app does
function salesforce_deploy () {
    dir="$1"
    what="$2"
    log "🚀 deploying $what"
    sf project deploy start --metadata-dir "$dir" --target-org "$target_org" --wait 15 --json > "$sf_tmp_dir/deploy.json" 2> /dev/null || true
    if [ "$(jq -r '(.result // .data // {}) | .success // false' "$sf_tmp_dir/deploy.json" 2> /dev/null)" != "true" ]
    then
        logerror "❌ failed to deploy $what"
        jq -r '(.result // .data // {}) | .details.componentFailures // [] | if type == "array" then . else [.] end | .[] | "   \(.componentType) \(.fullName): \(.problem)"' "$sf_tmp_dir/deploy.json" 2> /dev/null >&2
        jq -r '.message // empty' "$sf_tmp_dir/deploy.json" 2> /dev/null >&2
        if grep -q "ChangeEvents_ContactChangeEvent" "$sf_tmp_dir/deploy.json" 2> /dev/null
        then
            logerror "   a Developer Edition org allows 5 Change Data Capture entities: unselect one in Setup > Change Data Capture"
        fi
        logerror "   rendered metadata: $output_dir"
        exit 1
    fi
}
salesforce_deploy "$output_dir/app" "External Client App $app_name, MyPlatformEvent__e and Change Data Capture on Contact"
salesforce_deploy "$output_dir/policies" "the policies of $app_name (pre-authorized for \"$profile\", IP restrictions relaxed)"

# 4. consumer key, and wait until a JWT bearer login works
consumer_key=$(salesforce_setup_get_consumer_key "$target_org" "$app_name")
if [ -z "$consumer_key" ]
then
    logerror "❌ could not read the consumer key of $app_name back"
    logerror "   find it in Setup > External Client App Manager > $app_name > Settings > OAuth Settings > Consumer Key and Secret"
    exit 1
fi
log "🔑 consumer key of $app_name: ${consumer_key:0:12}…"

log "⏳ waiting for the JWT bearer login of $sf_username to work (a new External Client App takes 2 to 10 minutes to be active, max $max_wait seconds)"
deadline=$((SECONDS + max_wait))
while true
do
    if salesforce_setup_jwt_token "$instance_url" "$consumer_key" "$sf_username" "$sf_jwt_key_file" > "$sf_tmp_dir/token.out"
    then
        break
    fi
    if [ $SECONDS -ge $deadline ]
    then
        logerror "❌ the JWT bearer login still fails after $max_wait seconds: $(cat "$sf_tmp_dir/token.out")"
        logerror "   check Setup > Login History in Salesforce, then run 'playground salesforce check' later"
        exit 1
    fi
    log "   not yet: $(jq -r '.error_description // .error // .' "$sf_tmp_dir/token.out" 2> /dev/null | head -1), retrying in 20 seconds"
    sleep 20
done
log "✅ JWT bearer login works for $sf_username"

# 5. store
username_var=$(salesforce_setup_var_name SALESFORCE_USERNAME "$suffix" "$account2")
instance_var=$(salesforce_setup_var_name SALESFORCE_INSTANCE "$suffix" "$account2")
consumer_key_var=$(salesforce_setup_var_name SALESFORCE_CONSUMER_KEY_WITH_JWT "$suffix" "$account2")
password_var=$(salesforce_setup_var_name SALESFORCE_PASSWORD "$suffix" "$account2")
token_var=$(salesforce_setup_var_name SALESFORCE_SECURITY_TOKEN "$suffix" "$account2")

if [[ -n "$no_store" ]]
then
    log "📋 --no-store, the values to export:"
    echo "export $username_var=\"$sf_username\""
    echo "export $instance_var=\"$instance_url\""
    echo "export $consumer_key_var=\"$consumer_key\""
else
    playground secrets set "$username_var" --value "$sf_username" --plain
    playground secrets set "$instance_var" --value "$instance_url" --plain
    playground secrets set "$consumer_key_var" --value "$consumer_key" --secret
    log "💾 stored $username_var, $instance_var and $consumer_key_var"
fi

log "✋ Salesforce can't give these two back, store them yourself if not done yet:"
log "   playground secrets set $password_var"
log "   playground secrets set $token_var      (emailed by Salesforce: Settings > My Personal Information > Reset My Security Token)"
check_flags=""
if [[ -n "$suffix" ]]
then
    check_flags="$check_flags --suffix $suffix"
fi
if [[ -n "$account2" ]]
then
    check_flags="$check_flags --account2"
fi
log "🩺 check it any time with: playground salesforce check$check_flags"
