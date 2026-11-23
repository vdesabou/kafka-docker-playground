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

# same resolution as an example: exported variable, then the active secrets profile
profile="$(get_active_secret_profile)"
account_raw="$(secret_get SNOWFLAKE_ACCOUNT_NAME "$profile" 2> /dev/null || true)"
user="$(secret_get SNOWFLAKE_USERNAME "$profile" 2> /dev/null || true)"
password="$(secret_get SNOWFLAKE_PASSWORD "$profile" 2> /dev/null || true)"
missing=""
[ -z "$account_raw" ] && missing="$missing SNOWFLAKE_ACCOUNT_NAME"
[ -z "$user" ] && missing="$missing SNOWFLAKE_USERNAME"
[ -z "$password" ] && missing="$missing SNOWFLAKE_PASSWORD"
if [ -n "$missing" ]
then
    logerror "❌ not set:$missing (all the Snowflake examples need them)"
    logerror "👉 playground account snowflake setup"
    exit 1
fi
account=$(snowflake_normalize_account "$account_raw")
if [ "$account" != "$(echo "$account_raw" | tr '[:upper:]' '[:lower:]')" ]
then
    logwarn "⚠️ SNOWFLAKE_ACCOUNT_NAME is \"$account_raw\": the examples build https://\$SNOWFLAKE_ACCOUNT_NAME.snowflakecomputing.com, it must be \"$account\""
    logwarn "   👉 playground account snowflake setup (it stores the right form)"
fi

# 1. login
log "🔑 password login of $user on $account.snowflakecomputing.com (like snowsql in the examples)"
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
    exit 1
fi
rm -f /tmp/playground-snowflake-login.$$
trap 'snowflake_logout' EXIT
log "✅ login works"

nb_failed=0
row=$(snowflake_query "SELECT CURRENT_VERSION(), CURRENT_ROLE(), CURRENT_AVAILABLE_ROLES(), CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME(), CURRENT_REGION()") || row=""
if [ -z "$row" ] || [ "${row:0:1}" != "[" ]
then
    logerror "❌ the login works but a query fails: $row"
    exit 1
fi
version=$(echo "$row" | jq -r '.[0][0]')
default_role=$(echo "$row" | jq -r '.[0][1]')
roles=$(echo "$row" | jq -r '.[0][2] | fromjson | .[]' 2> /dev/null)
org=$(echo "$row" | jq -r '.[0][3] | ascii_downcase')
account_name=$(echo "$row" | jq -r '.[0][4] | ascii_downcase')
region=$(echo "$row" | jq -r '.[0][5]')
echo -e "✅ ${GREEN}Account${NC} $org-${account_name//_/-} (region $region, Snowflake $version)"

# 2. roles: ACCOUNTADMIN inherits SECURITYADMIN (which inherits USERADMIN) and SYSADMIN
has_accountadmin=""
echo "$roles" | grep -qx "ACCOUNTADMIN" && has_accountadmin=1
for role in SECURITYADMIN SYSADMIN USERADMIN
do
    if [[ -n "$has_accountadmin" ]] || echo "$roles" | grep -qx "$role"
    then
        echo -e "✅ ${GREEN}Role $role${NC}"
    else
        echo -e "❌ ${RED}Role $role${NC}: $user can't use it        👉 GRANT ROLE $role TO USER $user (as ACCOUNTADMIN)"
        echo "      needed by: all the Snowflake examples (they create a role, a warehouse and a user)"
        nb_failed=$((nb_failed + 1))
    fi
done
if [[ -n "$has_accountadmin" ]]
then
    echo -e "✅ ${GREEN}Role ACCOUNTADMIN${NC}"
else
    echo -e "⚠️ ${YELLOW}Role ACCOUNTADMIN${NC}: $user can't use it"
    echo "      needed by: the Iceberg variants (connect-snowflake-sink, fm-snowflake-sink)"
fi
case "$default_role" in
    ACCOUNTADMIN)
        echo -e "✅ ${GREEN}Default role${NC} ACCOUNTADMIN" ;;
    SYSADMIN)
        echo -e "✅ ${GREEN}Default role${NC} SYSADMIN (the Iceberg external volume variants need ACCOUNTADMIN as default role)" ;;
    *)
        echo -e "❌ ${RED}Default role${NC} $default_role: the examples create their database with the default role        👉 ALTER USER $user SET DEFAULT_ROLE = ACCOUNTADMIN"
        nb_failed=$((nb_failed + 1)) ;;
esac

# 3. edition (Enterprise for Iceberg), visible to ORGADMIN only
edition=""
if echo "$roles" | grep -qx "ORGADMIN" && snowflake_query "USE ROLE ORGADMIN" > /dev/null
then
    if snowflake_query "SHOW ORGANIZATION ACCOUNTS" > /dev/null
    then
        edition=$(snowflake_query "SELECT \"edition\" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE LOWER(\"account_name\") = '$account_name'" 2> /dev/null | jq -r '.[0][0] // empty' 2> /dev/null) || true
    fi
    snowflake_query "USE ROLE $default_role" > /dev/null || true
fi
case "$edition" in
    ENTERPRISE|BUSINESS_CRITICAL|VIRTUAL_PRIVATE_SNOWFLAKE)
        echo -e "✅ ${GREEN}Edition${NC} $edition" ;;
    STANDARD)
        echo -e "⚠️ ${YELLOW}Edition${NC} STANDARD: the Iceberg variants need Enterprise (pick it when signing up for a trial)" ;;
    *)
        echo -e "⚠️ ${YELLOW}Edition${NC} unknown (only ORGADMIN sees it): the Iceberg variants need Enterprise" ;;
esac

# 4. warehouses the examples left behind (PGWH<user>..., snowflake_object_name): a running one costs credits
if snowflake_query "SHOW WAREHOUSES LIKE 'PGWH%'" > /dev/null
then
    counts=$(snowflake_query "SELECT COUNT(*), COUNT_IF(\"state\" = 'STARTED') FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))" 2> /dev/null) || counts=""
    total=$(echo "$counts" | jq -r '.[0][0] // 0' 2> /dev/null)
    started=$(echo "$counts" | jq -r '.[0][1] // 0' 2> /dev/null)
    if [ "${total:-0}" != "0" ]
    then
        echo -e "ℹ️  $total warehouse(s) PGWH… left by the examples, $started running (they suspend themselves; drop them with DROP WAREHOUSE)"
    fi
fi

echo ""
if [ $nb_failed -gt 0 ]
then
    logwarn "⚠️ $nb_failed check(s) failed: the examples listed above would fail"
else
    log "🎉 the Snowflake account is ready for the Snowflake examples"
fi
