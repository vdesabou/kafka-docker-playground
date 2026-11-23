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
SERVICENOW_URL="$(secret_get SERVICENOW_URL "$profile" 2> /dev/null || true)"
SERVICENOW_PASSWORD="$(secret_get SERVICENOW_PASSWORD "$profile" 2> /dev/null || true)"
developer_username="$(secret_get SERVICENOW_DEVELOPER_USERNAME "$profile" 2> /dev/null || true)"
developer_password="$(secret_get SERVICENOW_DEVELOPER_PASSWORD "$profile" 2> /dev/null || true)"
missing=""
[ -z "$SERVICENOW_URL" ] && missing="$missing SERVICENOW_URL"
[ -z "$SERVICENOW_PASSWORD" ] && missing="$missing SERVICENOW_PASSWORD"
if [ -n "$missing" ]
then
    logerror "❌ not set:$missing (all the ServiceNow examples need them)"
    logerror "👉 playground account servicenow setup"
    exit 1
fi
normalized=$(servicenow_normalize_url "$SERVICENOW_URL")
if [ "$SERVICENOW_URL" != "$normalized" ]
then
    logwarn "⚠️ SERVICENOW_URL is \"$SERVICENOW_URL\": the examples need \"$normalized\" (https, host only, trailing /)        👉 playground account servicenow setup"
    SERVICENOW_URL="$normalized"
fi

# 1. the instance
log "🔑 REST API of $SERVICENOW_URL as admin (basic authentication, like the examples)"
state=$(servicenow_account_state)
nb_failed=0
case "$state" in
    awake)
        echo -e "✅ ${GREEN}Instance${NC} awake, admin logged in" ;;
    unauthorized)
        echo -e "❌ ${RED}Login${NC}: HTTP 401 for admin: wrong SERVICENOW_PASSWORD, or the Identity Type of admin is not Machine (recent releases refuse basic authentication otherwise)"
        echo "      👉 playground account servicenow setup (it sets Identity Type = Machine, like the examples)"
        exit 1 ;;
    hibernating)
        # not a failure when the examples can wake it up themselves (playground run calls this check)
        if [ -n "$developer_username" ] && [ -n "$developer_password" ]
        then
            echo -e "⚠️ ${YELLOW}Instance${NC} hibernating: the examples wake it up by themselves (SERVICENOW_DEVELOPER_* are set, a few minutes), or now: playground account servicenow setup"
            exit 0
        fi
        echo -e "❌ ${RED}Instance${NC} hibernating"
        echo "      👉 wake it up at https://developer.servicenow.com (Manage my instance), or store your ServiceNow ID so the examples do it: playground account servicenow setup --developer-username <you>"
        exit 1 ;;
    waking)
        echo -e "⏳ ${YELLOW}Instance${NC} waking up (gateway error): the examples wait for it, a minute or two"
        exit 0 ;;
    missing)
        echo -e "❌ ${RED}Instance${NC}: nothing answers at $SERVICENOW_URL: wrong URL, or the instance was released (unused for about 10 days)"
        echo "      👉 request a new one at https://developer.servicenow.com, then playground account servicenow setup"
        exit 1 ;;
    *)
        echo -e "❌ ${RED}Instance${NC}: unexpected answer from $SERVICENOW_URL: $state"
        exit 1 ;;
esac

# 2. the tables the examples use
code=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -u admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' "${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1" 2> /dev/null) || code="000"
if [ "$code" == "200" ]
then
    echo -e "✅ ${GREEN}Table incident${NC} (servicenow sources)"
else
    echo -e "❌ ${RED}Table incident${NC}: HTTP $code"
    echo "      needed by: the servicenow sources"
    nb_failed=$((nb_failed + 1))
fi
count=$(curl -s -m 30 -u admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' "${SERVICENOW_URL}api/now/table/sys_db_object?sysparm_query=name=u_test_table&sysparm_fields=name&sysparm_limit=1" 2> /dev/null | jq -r '.result | length' 2> /dev/null) || count=""
if [ "$count" == "1" ]
then
    echo -e "✅ ${GREEN}Table u_test_table${NC} (servicenow sinks)"
else
    echo -e "ℹ️  table u_test_table does not exist yet: the servicenow sinks create it"
fi

# 3. waking up by themselves
if [ -n "$developer_username" ] && [ -n "$developer_password" ]
then
    echo -e "✅ ${GREEN}SERVICENOW_DEVELOPER_*${NC} set: the examples wake the instance up when it hibernates (Docker, Playwright image)"
else
    echo -e "⚠️ ${YELLOW}SERVICENOW_DEVELOPER_*${NC} not set: when the instance hibernates, wake it up by hand at https://developer.servicenow.com        👉 playground account servicenow setup --developer-username <you>"
fi

echo ""
if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed check(s) failed: the examples listed above would fail"
else
    log "🎉 the ServiceNow instance is ready for the ServiceNow examples"
fi
