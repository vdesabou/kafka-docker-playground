url="${args[--url]}"
password="${args[--password]}"
developer_username="${args[--developer-username]}"
developer_password="${args[--developer-password]}"
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
function servicenow_setup_value () {
    name="$1"
    prompt="$2"
    silent="$3"
    optional="$4"
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
    if [ -z "$value" ] && [[ ! -n "$optional" ]]
    then
        logerror "❌ $name is not set: pass it as a flag (see --help)"
        exit 1
    fi
    printf '%s' "$value"
}
if [[ ! -n "$url" ]]
then
    url=$(servicenow_setup_value SERVICENOW_URL "🌐 instance (dev12345, or its URL)")
fi
if [[ ! -n "$password" ]]
then
    password=$(servicenow_setup_value SERVICENOW_PASSWORD "🔐 password of admin" silent)
fi
if [[ ! -n "$developer_username" ]]
then
    developer_username=$(servicenow_setup_value SERVICENOW_DEVELOPER_USERNAME "👤 your ServiceNow ID, to wake the instance up (empty to skip)" "" optional)
fi
if [ -n "$developer_username" ] && [[ ! -n "$developer_password" ]]
then
    developer_password=$(servicenow_setup_value SERVICENOW_DEVELOPER_PASSWORD "🔐 password of $developer_username" silent optional)
fi

export SERVICENOW_URL
SERVICENOW_URL=$(servicenow_normalize_url "$url")
export SERVICENOW_PASSWORD="$password"
export SERVICENOW_DEVELOPER_USERNAME="$developer_username"
export SERVICENOW_DEVELOPER_PASSWORD="$developer_password"
log "🌐 instance $SERVICENOW_URL"

# 1. wake it up if it hibernates (servicenow_wake_up_instance: Playwright in docker, like the examples)
state=$(servicenow_account_state)
case "$state" in
    hibernating|waking)
        if [ "$state" == "hibernating" ] && { [ -z "$developer_username" ] || [ -z "$developer_password" ]; }
        then
            logerror "❌ the instance is hibernating: wake it up at https://developer.servicenow.com (Manage my instance), or pass --developer-username (your ServiceNow ID) so that setup and the examples do it"
            exit 1
        fi
        if ! docker info > /dev/null 2>&1
        then
            logerror "❌ the instance is $state and waking it up needs docker (Playwright image): start docker, or wake it up at https://developer.servicenow.com"
            exit 1
        fi
        servicenow_wake_up_instance || exit 1
        state=$(servicenow_account_state) ;;
    missing)
        logerror "❌ nothing answers at $SERVICENOW_URL: wrong URL, or the instance was released (unused for about 10 days): request a new one at https://developer.servicenow.com"
        exit 1 ;;
esac

# 2. basic authentication for admin (Identity Type = Machine, like the examples)
if [ "$state" == "unauthorized" ]
then
    servicenow_ensure_machine_identity || exit 1
    state=$(servicenow_account_state)
fi
if [ "$state" != "awake" ]
then
    logerror "❌ the instance answers \"$state\" for admin: nothing stored"
    exit 1
fi
log "✅ admin can use the REST API of $SERVICENOW_URL"

# 3. store
if [[ -n "$no_store" ]]
then
    log "📋 --no-store, the values to export:"
    echo "export SERVICENOW_URL=\"$SERVICENOW_URL\""
    echo "export SERVICENOW_PASSWORD=\"$SERVICENOW_PASSWORD\""
    if [ -n "$developer_username" ]
    then
        echo "export SERVICENOW_DEVELOPER_USERNAME=\"$developer_username\""
        echo "export SERVICENOW_DEVELOPER_PASSWORD=\"$developer_password\""
    fi
else
    playground secrets set SERVICENOW_URL --value "$SERVICENOW_URL" --plain
    playground secrets set SERVICENOW_PASSWORD --value "$SERVICENOW_PASSWORD" --secret
    stored="SERVICENOW_URL and SERVICENOW_PASSWORD"
    if [ -n "$developer_username" ] && [ -n "$developer_password" ]
    then
        playground secrets set SERVICENOW_DEVELOPER_USERNAME --value "$developer_username" --plain
        playground secrets set SERVICENOW_DEVELOPER_PASSWORD --value "$developer_password" --secret
        stored="$stored, SERVICENOW_DEVELOPER_USERNAME and SERVICENOW_DEVELOPER_PASSWORD"
    fi
    log "💾 stored $stored"
fi

log "🩺 the instance now:"
playground account servicenow check || true
log "🩺 check it any time with: playground account servicenow check"
