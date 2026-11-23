subscription="${args[--subscription]}"

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

azure_tmp_dir=$(mktemp -d -t playground-azure-check.XXXXXX)
trap 'rm -rf "$azure_tmp_dir"' EXIT

# same resolution as an example: exported variable, then the active secrets profile
profile="$(get_active_secret_profile)"
function azure_check_value () {
    secret_get "$1" "$profile" 2> /dev/null || true
}
client_id="$(azure_check_value AZ_CLIENT_ID)"
client_secret="$(azure_check_value AZ_CLIENT_SECRET)"
tenant="$(azure_check_value AZ_TENANT_ID)"
if [[ ! -n "$subscription" ]]
then
    subscription="$(azure_check_value AZURE_SUBSCRIPTION_NAME)"
fi

if [ -z "$client_id" ] || [ -z "$client_secret" ] || [ -z "$tenant" ]
then
    logwarn "⚠️ no service principal: AZ_CLIENT_ID, AZ_CLIENT_SECRET and AZ_TENANT_ID are not all set"
    logwarn "   the Azure examples open the browser for 'az login' on every run (and can't run unattended)"
    logerror "👉 playground account azure setup creates a service principal and stores them"
    exit 1
fi

# 1. login
log "🔑 login of service principal $client_id in tenant $tenant (client credentials, like the examples)"
# not in a $( ): azure_access_token must reach this shell
if ! azure_sp_token "$tenant" "$client_id" "$client_secret" > "$azure_tmp_dir/token.out"
then
    out=$(cat "$azure_tmp_dir/token.out")
    logerror "❌ Entra ID rejected the login: $(echo "$out" | jq -r '"\(.error) \(.error_description)"' 2> /dev/null || echo "$out")"
    cause=$(azure_explain_login_error "$out")
    if [ -n "$cause" ]
    then
        logerror "   $cause"
    elif ! echo "$out" | grep -q '{'
    then
        logerror "   login.microsoftonline.com is not reachable from this machine (proxy, firewall?)"
    fi
    exit 1
fi
oid=$(azure_jwt_claim "$azure_access_token" oid)
log "✅ login works (object id $oid)"

function azure_get () {
    curl -sS -m 30 -o "$azure_tmp_dir/out.json" -w '%{http_code}' -H "Authorization: Bearer $azure_access_token" "https://management.azure.com$1" 2> /dev/null || echo "000"
}
nb_failed=0

# 2. the subscription
code=$(azure_get "/subscriptions?api-version=2022-12-01")
if [ "$code" != "200" ]
then
    logerror "❌ can't list the subscriptions (HTTP $code): $(jq -r '.error.message // empty' "$azure_tmp_dir/out.json" 2> /dev/null)"
    exit 1
fi
subscriptions=$(jq -r '.value[] | "\(.subscriptionId)|\(.displayName)|\(.state)"' "$azure_tmp_dir/out.json")
if [ -z "$subscriptions" ]
then
    echo -e "❌ ${RED}Subscription${NC}: the service principal has no role on any subscription        👉 playground account azure setup"
    exit 1
fi
if [[ ! -n "$subscription" ]]
then
    if [ "$(echo "$subscriptions" | wc -l | tr -d ' ')" == "1" ]
    then
        subscription=$(echo "$subscriptions" | cut -d'|' -f2)
        logwarn "⚠️ AZURE_SUBSCRIPTION_NAME is not set, using the only subscription of the service principal: $subscription"
    else
        logerror "❌ AZURE_SUBSCRIPTION_NAME is not set and the service principal sees several subscriptions:"
        echo "$subscriptions" | cut -d'|' -f2 | sed 's/^/   /' >&2
        exit 1
    fi
fi
subscription_id=$(echo "$subscriptions" | awk -F'|' -v n="$subscription" '$2 == n { print $1; exit }')
if [ -z "$subscription_id" ]
then
    echo -e "❌ ${RED}Subscription${NC} $subscription: the service principal has no role on it (it sees: $(echo "$subscriptions" | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//; s/,/, /g'))"
    exit 1
fi
echo -e "✅ ${GREEN}Subscription${NC} $subscription ($subscription_id, $(echo "$subscriptions" | awk -F'|' -v n="$subscription" '$2 == n { print $3; exit }'))"

# 3. roles of the service principal on the subscription (inherited ones included)
code=$(azure_get "/subscriptions/$subscription_id/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=assignedTo('$oid')")
if [ "$code" == "200" ]
then
    role_ids=$(jq -r '.value[] | select(.properties.scope as $s | ("/subscriptions/'"$subscription_id"'" | startswith($s)) or ($s == "/") or ($s | startswith("/providers/Microsoft.Management/"))) | .properties.roleDefinitionId | split("/") | last' "$azure_tmp_dir/out.json")
    owner="8e3af657-a8ff-443b-a75c-2fe8c4bcb635"
    uaa="18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"
    while IFS='|' read -r role role_id why
    do
        if echo "$role_ids" | grep -qx -e "$role_id" -e "$owner" || { [ "$role_id" != "b24988ac-6180-42a0-ab88-20f7382dd24c" ] && echo "$role_ids" | grep -qx "$uaa"; }
        then
            echo -e "✅ ${GREEN}Role $role${NC} (or broader) on the subscription"
        else
            echo -e "❌ ${RED}Role $role${NC}: missing on the subscription        👉 playground account azure setup"
            echo "      needed for: $why"
            nb_failed=$((nb_failed + 1))
        fi
    done < <(azure_setup_roles)
else
    echo -e "⚠️ ${YELLOW}Roles${NC}: can't list the role assignments (HTTP $code $(jq -r '.error.code // empty' "$azure_tmp_dir/out.json" 2> /dev/null))"
fi

# 4. resource providers
code=$(azure_get "/subscriptions/$subscription_id/providers?api-version=2021-04-01&\$select=namespace,registrationState")
if [ "$code" == "200" ]
then
    while IFS='|' read -r provider examples
    do
        state=$(jq -r --arg p "$provider" '.value[] | select(.namespace | ascii_downcase == ($p | ascii_downcase)) | .registrationState' "$azure_tmp_dir/out.json")
        if [ "$state" == "Registered" ]
        then
            echo -e "✅ ${GREEN}$provider${NC}"
        elif [ "$state" == "Registering" ]
        then
            echo -e "⏳ ${YELLOW}$provider${NC}: registering (takes a few minutes)"
        else
            echo -e "❌ ${RED}$provider${NC}: ${state:-unknown}        👉 az provider register --namespace $provider --subscription $subscription_id"
            echo "      needed by: $examples"
            nb_failed=$((nb_failed + 1))
        fi
    done < <(azure_setup_providers)
else
    echo -e "⚠️ ${YELLOW}Resource providers${NC}: can't list them (HTTP $code)"
fi

# 5. the extra service principals CI uses instead of creating Entra apps (only read when GITHUB_RUN_NUMBER is set)
for pair in "AZURE_LOGS_CLIENT_ID|AZURE_LOGS_CLIENT_SECRET|log analytics v2 and kusto sinks" \
            "AZURE_DATALAKE_CLIENT_ID|AZURE_DATALAKE_CLIENT_PASSWORD|data lake gen2 sink" \
            "AZURE_COGNITIVE_APP_ID|AZURE_COGNITIVE_APP_PASSWORD|cognitive search sink"
do
    id_var="${pair%%|*}"
    rest="${pair#*|}"
    secret_var="${rest%%|*}"
    examples="${rest#*|}"
    id_value="$(azure_check_value "$id_var")"
    secret_value="$(azure_check_value "$secret_var")"
    if [ -z "$id_value" ] || [ -z "$secret_value" ]
    then
        continue
    fi
    if out=$(azure_sp_token "$tenant" "$id_value" "$secret_value")
    then
        echo -e "✅ ${GREEN}$id_var${NC} / $secret_var log in (CI, $examples)"
    else
        echo -e "❌ ${RED}$id_var${NC} / $secret_var: $(echo "$out" | jq -r '.error_description' 2> /dev/null | cut -c1-120)"
        cause=$(azure_explain_login_error "$out")
        [ -n "$cause" ] && echo "      ${cause//AZ_CLIENT_SECRET/$secret_var}"
        echo "      needed by: $examples, in CI only (locally the examples create their own Entra app)"
        nb_failed=$((nb_failed + 1))
    fi
done

# 6. resource groups your examples left behind (they are named pg<user>...)
user_prefix="pg$(echo "${USER}" | tr -d '._-' | tr '[:upper:]' '[:lower:]')"
code=$(azure_get "/subscriptions/$subscription_id/resourcegroups?api-version=2021-04-01")
if [ "$code" == "200" ]
then
    leftovers=$(jq -r --arg p "$user_prefix" '.value[].name | select(ascii_downcase | startswith($p))' "$azure_tmp_dir/out.json")
    if [ -n "$leftovers" ]
    then
        echo -e "⚠️ ${YELLOW}$(echo "$leftovers" | wc -l | tr -d ' ') resource group(s)${NC} left by your examples: $(echo "$leftovers" | tr '\n' ' ')"
        echo "      👉 playground cloud-resources cleanup --resource azure --dry-run"
    fi
fi

echo ""
if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed check(s) failed: the examples listed above would fail (new roles can take a few minutes to apply)"
else
    log "🎉 subscription $subscription is ready for the Azure examples"
fi
