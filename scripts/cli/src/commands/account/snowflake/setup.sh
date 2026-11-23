account="${args[--account]}"
user="${args[--user]}"
password="${args[--password]}"
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
function snowflake_setup_value () {
    name="$1"
    prompt="$2"
    silent="$3"
    value="$(secret_get "$name" "$profile" 2> /dev/null || true)"
    if [ -z "$value" ]
    then
        if [ ! -t 0 ]
        then
            logerror "❌ $name is not set: pass it as a flag (see --help)"
            exit 1
        fi
        if [[ -n "$silent" ]]
        then
            read -r -s -p "$prompt: " value < /dev/tty
            echo "" >&2
        else
            read -r -p "$prompt: " value < /dev/tty
        fi
    fi
    printf '%s' "$value"
}
if [[ ! -n "$account" ]]
then
    account=$(snowflake_setup_value SNOWFLAKE_ACCOUNT_NAME "🏔️ account identifier or URL (Snowsight > your name > Account > copy the account URL)")
fi
if [[ ! -n "$user" ]]
then
    user=$(snowflake_setup_value SNOWFLAKE_USERNAME "👤 admin user")
fi
if [[ ! -n "$password" ]]
then
    password=$(snowflake_setup_value SNOWFLAKE_PASSWORD "🔐 password of $user" silent)
fi

account_input="$account"
account=$(snowflake_normalize_account "$account")
if [ "$account" != "$(echo "$account_input" | tr '[:upper:]' '[:lower:]')" ]
then
    log "🏔️ account identifier: $account (from $account_input)"
fi

# validate the login, then show what check reports (roles, default role, edition)
if ! snowflake_login "$account" "$user" "$password" > /tmp/playground-snowflake-login.$$ 2>&1
then
    out=$(cat /tmp/playground-snowflake-login.$$)
    rm -f /tmp/playground-snowflake-login.$$
    reason=$(echo "$out" | jq -r '"\(.code // "") \(.message // "")"' 2> /dev/null | head -1) || reason=""
    if [ -z "${reason// /}" ]
    then
        reason="no Snowflake account answers at $account.snowflakecomputing.com"
    fi
    logerror "❌ Snowflake rejected the login: $reason"
    cause=$(snowflake_explain_login_error "$out")
    if [ -n "$cause" ]
    then
        logerror "   $cause"
    fi
    logerror "   nothing stored"
    exit 1
fi
rm -f /tmp/playground-snowflake-login.$$
snowflake_logout
log "✅ $user can log into $account"

if [[ -n "$no_store" ]]
then
    log "📋 --no-store, the values to export:"
    echo "export SNOWFLAKE_ACCOUNT_NAME=\"$account\""
    echo "export SNOWFLAKE_USERNAME=\"$user\""
    echo "export SNOWFLAKE_PASSWORD=\"$password\""
else
    playground secrets set SNOWFLAKE_ACCOUNT_NAME --value "$account" --plain
    playground secrets set SNOWFLAKE_USERNAME --value "$user" --plain
    playground secrets set SNOWFLAKE_PASSWORD --value "$password" --secret
    log "💾 stored SNOWFLAKE_ACCOUNT_NAME, SNOWFLAKE_USERNAME and SNOWFLAKE_PASSWORD"
fi

log "🩺 what this login can do:"
SNOWFLAKE_ACCOUNT_NAME="$account" SNOWFLAKE_USERNAME="$user" SNOWFLAKE_PASSWORD="$password" playground account snowflake check || true
log "🩺 check it any time with: playground account snowflake check"
