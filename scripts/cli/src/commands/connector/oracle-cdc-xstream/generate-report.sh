log "⚙️ Generate and open oracle cdc xstream connector diagnostics"
tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# defaults of the playground examples, overridden by the running XStream connector config when there is one
xstream_admin="C##CFLTADMIN"
xstream_user="C##CFLTUSER"
xstream_server="XOUT"
connector_type=$(playground state get run.connector_type)
if [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ] && [ "$connector_type" != "$CONNECTOR_TYPE_CUSTOM" ]
then
    for c in $(playground get-connector-list 2> /dev/null || true)
    do
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$c/config\"" > /dev/null 2>&1 || continue
        if echo "$curl_output" | jq -e '."connector.class" | test("XStream")' > /dev/null 2>&1
        then
            server=$(echo "$curl_output" | jq -r '."database.out.server.name" // empty')
            user=$(echo "$curl_output" | jq -r '."database.user" // empty' | tr '[:lower:]' '[:upper:]')
            [ -n "$server" ] && xstream_server="$server"
            [ -n "$user" ] && xstream_user="$user"
            log "🔎 using outbound server $xstream_server and connect user $xstream_user of connector $c"
            break
        fi
    done
fi

cd $tmp_dir
# the URL contains a hash that changes when the docs are republished: fail with an explicit message rather than silently
diag_url="https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/_downloads/6d672a473a3153a88f9c67de5e0b558f/orclcdc_diag.sql"
if ! curl -fsSL -o orclcdc_diag.sql "$diag_url"
then
    logerror "❌ could not download orclcdc_diag.sql from $diag_url"
    logerror "💡 the link may have changed: get the script from https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/troubleshooting.html#connector-diagnostics-script"
    exit 1
fi

# never present the report of a previous run as the new one
rm -f /tmp/orclcdc_diag.html
playground container exec --container oracle --command "rm -f /home/oracle/orclcdc_diag_*.html" > /dev/null 2>&1 || true

playground container cp --source orclcdc_diag.sql --destination oracle:/orclcdc_diag.sql > /dev/null 2>&1
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
     CONNECT sys/Admin123 AS SYSDBA
     @/orclcdc_diag.sql $xstream_admin $xstream_user $xstream_server ''
END;
/
EOF
playground container exec --container oracle --command "mv \$(ls -t /home/oracle/orclcdc_diag_*.html | head -1) /home/oracle/orclcdc_diag.html" || true
playground container cp --source oracle:/home/oracle/orclcdc_diag.html --destination /tmp/ > /dev/null 2>&1 || true
if [ -f /tmp/orclcdc_diag.html ]
then
    # a timestamped copy, plus /tmp/orclcdc_diag.html (the latest, read by playground analyze oracle-xstream-report)
    report="/tmp/orclcdc_diag_$(date '+%Y%m%d_%H%M%S').html"
    cp /tmp/orclcdc_diag.html "$report"
    log "⚙️ oracle cdc xstream connector diagnostics report is available at $report (latest also in /tmp/orclcdc_diag.html)"
    # only open a browser in an interactive terminal
    if [[ -t 1 ]]
    then
        if command -v open &>/dev/null
        then
            open "$report"
        elif command -v xdg-open &>/dev/null
        then
            xdg-open "$report" > /dev/null 2>&1 || true
        fi
    fi
else
    logerror "❌ oracle cdc xstream connector diagnostics report is not available"
    exit 1
fi
