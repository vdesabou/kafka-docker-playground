suffix="$(echo "${args[--suffix]}" | tr '[:lower:]' '[:upper:]')"
account2="${args[--account2]}"
keystore="${args[--keystore]}"

if [[ ! -n "$keystore" ]]
then
    # what the examples use: the keystore of 'playground salesforce setup', else the one in the examples
    keystore="$(salesforce_user_keystore_path)"
    if [ ! -f "$keystore" ]
    then
        keystore="$root_folder/connect/connect-salesforce-cdc-source/salesforce-confluent.keystore.jks"
    fi
fi
if [ ! -f "$keystore" ]
then
    logerror "❌ keystore $keystore is missing"
    logerror "👉 playground salesforce setup generates one"
    exit 1
fi
for tool in openssl curl jq
do
    if ! command -v $tool > /dev/null 2>&1
    then
        logerror "❌ $tool is not installed"
        exit 1
    fi
done

sf_tmp_dir=$(mktemp -d -t playground-salesforce-check.XXXXXX)
trap 'rm -rf "$sf_tmp_dir"' EXIT

# same resolution as an example: exported variable, then the active secrets profile, then default
profile="$(get_active_secret_profile)"
function salesforce_check_value () {
    name=$(salesforce_setup_var_name "$1" "$suffix" "$account2")
    secret_get "$name" "$profile" 2> /dev/null || true
}
username_var=$(salesforce_setup_var_name SALESFORCE_USERNAME "$suffix" "$account2")
consumer_key_var=$(salesforce_setup_var_name SALESFORCE_CONSUMER_KEY_WITH_JWT "$suffix" "$account2")
instance_var=$(salesforce_setup_var_name SALESFORCE_INSTANCE "$suffix" "$account2")
username=$(salesforce_check_value SALESFORCE_USERNAME)
consumer_key=$(salesforce_check_value SALESFORCE_CONSUMER_KEY_WITH_JWT)
instance_url=$(salesforce_check_value SALESFORCE_INSTANCE)
instance_url="${instance_url:-https://login.salesforce.com}"

missing=0
for var in "$username_var:$username" "$consumer_key_var:$consumer_key"
do
    if [ -z "${var#*:}" ]
    then
        logerror "❌ ${var%%:*} is not set"
        missing=1
    fi
done
if [ $missing -eq 1 ]
then
    logerror "👉 playground salesforce setup$( [[ -n "$suffix" ]] && echo " --suffix $suffix" )$( [[ -n "$account2" ]] && echo " --account2" )"
    exit 1
fi

salesforce_setup_load_keystore "$keystore"

log "🔑 JWT bearer login of $username on $instance_url ($consumer_key_var ${consumer_key:0:12}…, certificate of $keystore)"
if salesforce_setup_jwt_token "$instance_url" "$consumer_key" "$username" "$sf_jwt_key_file" > "$sf_tmp_dir/token.out"
then
    log "✅ JWT bearer login works ($sf_token_instance_url)"
else
    answer=$(cat "$sf_tmp_dir/token.out")
    logerror "❌ JWT bearer login rejected: $answer"
    case "$answer" in
        *"client identifier invalid"*)
            logerror "   $consumer_key_var is not the consumer key of an External Client App of this org, or the app was created less than 10 minutes ago" ;;
        *"hasn't approved this consumer"*|*"not approved"*)
            logerror "   the app is not pre-authorized for this user: its OAuth policy must be 'Admin approved users are pre-authorized' and list the user's profile (playground salesforce setup does it)" ;;
        *"invalid assertion"*|*"invalid signature"*|*"invalid_grant"*"certificate"*)
            logerror "   the certificate of the External Client App does not match the private key of $keystore" ;;
        *"audience is invalid"*)
            logerror "   wrong $instance_var: https://login.salesforce.com, or https://test.salesforce.com for a sandbox" ;;
        *"user hasn't been"*|*"inactive"*|*"locked"*|*"expired"*)
            logerror "   the user $username can't log in: check it in Setup > Users" ;;
    esac
    logerror "   Salesforce shows the reason of every login in Setup > Login History"
    exit 1
fi

missing_objects=0
function salesforce_check_query () {
    curl -sS -m 30 -G -H "Authorization: Bearer $sf_access_token" "$sf_token_instance_url/services/data/v66.0/$1" --data-urlencode "q=$2"
}

nb=$(salesforce_check_query query "SELECT QualifiedApiName FROM EntityDefinition WHERE QualifiedApiName = 'MyPlatformEvent__e'" | jq -r '.totalSize // 0' 2> /dev/null)
if [ "${nb:-0}" -ge 1 ]
then
    log "✅ Platform Event MyPlatformEvent__e exists"
else
    logwarn "⚠️ Platform Event MyPlatformEvent__e is missing: only the Platform Events examples need it"
    missing_objects=1
fi

cdc_entities=$(salesforce_check_query tooling/query "SELECT SelectedEntity FROM PlatformEventChannelMember WHERE EventChannel = 'ChangeEvents'" | jq -r '.records[]?.SelectedEntity' 2> /dev/null | sort | tr '\n' ' ')
if [[ " $cdc_entities" == *" ContactChangeEvent "* ]]
then
    log "✅ Change Data Capture is enabled on Contact (entities: $cdc_entities)"
else
    logwarn "⚠️ Change Data Capture is not enabled on Contact (entities: ${cdc_entities:-none}): only the CDC examples need it"
    missing_objects=1
fi

if [ $missing_objects -eq 1 ]
then
    log "👉 playground salesforce setup$( [[ -n "$suffix" ]] && echo " --suffix $suffix" )$( [[ -n "$account2" ]] && echo " --account2" ) deploys what is missing"
    exit 0
fi
log "🎉 the org is ready for all the Salesforce examples"
