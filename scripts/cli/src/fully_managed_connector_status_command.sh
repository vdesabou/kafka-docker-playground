connector="${args[--connector]}"
verbose="${args[--verbose]}"

get_ccloud_connect

if [[ ! -n "$connector" ]]
then
    set +e
    log "✨ --connector flag was not provided, applying command to all ccloud connectors"
    connector=$(playground get-fully-managed-connector-list)
    if [ $? -ne 0 ]
    then
        logerror "❌ Could not get list of connectors"
        echo "$connector"
        exit 1
    fi
    if [ "$connector" == "" ]
    then
        logerror "💤 No ccloud connector is running !"
        exit 1
    fi
    set -e
fi

items=($connector)
for connector in ${items[@]}
do
    log "🧩 Displaying connector status for $connector"
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
    fi
    curl_output=$(curl -s --request GET "https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status" --header "authorization: Basic $authorization")
    ret=$?
    set -e
    if [ $ret -eq 0 ]
    then
        if echo "$curl_output" | jq 'if .error then .error | has("code") else has("error_code") end' 2> /dev/null | grep -q true
        then
            if echo "$curl_output" | jq '.error | has("code")' 2> /dev/null | grep -q true
            then
                code=$(echo "$curl_output" | jq -r .error.code)
                message=$(echo "$curl_output" | jq -r .error.message)
            else
                code=$(echo "$curl_output" | jq -r .error_code)
                message=$(echo "$curl_output" | jq -r .message)
            fi
            logerror "Command failed with error code $code"
            logerror "$message"
            exit 1
        else
            printf "%-30s %-12s %-60s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
            echo "-------------------------------------------------------------------------------------------------------------"
            status=$(echo "$curl_output" | jq -r '.connector.state')

            if [ "$status" == "RUNNING" ]
            then
                status="✅ RUNNING"
            elif [ "$status" == "PAUSED" ]
            then
                status="⏸️  PAUSED"
            elif [ "$status" == "FAILED" ]
            then
                status="❌ FAILED"
            elif [ "$status" == "STOPPED" ]
            then
                status="🛑 STOPPED"
            else
                status="🤔 UNKNOWN"
            fi
            
            tasks=$(echo "$curl_output" | jq -r '.tasks[] | "\(.id):\(.state)"' | tr '\n' ',' | sed 's/,$/\n/')
            
            if [[ "$tasks" == *"RUNNING"* ]]
            then
                tasks="${tasks//RUNNING/🟢 RUNNING}"
            elif [[ "$tasks" == *"PAUSED"* ]]
            then
                tasks="${tasks//PAUSED/⏸️  PAUSED}"
            elif [[ "$tasks" == *"STOPPED"* ]]
            then
                tasks="${tasks//STOPPED/🛑  STOPPED}"
            elif [[ "$tasks" == *"FAILED"* ]]
            then
                tasks="${tasks//FAILED/🛑 FAILED}"
            else
                tasks="🤔 N/A"
            fi
            
            stacktrace_connector=$(echo "$curl_output" | jq -r '.connector.trace | select(length > 0)')
            errors_from_trace=$(echo "$curl_output" | jq -r '.errors_from_trace[0].error | select(length > 0)')
            validation_errors=$(echo "$curl_output" | jq -r '.validation_errors[0].error | select(length > 0)')
            stacktrace=""
            if [ "$stacktrace_connector" != "" ]
            then
                stacktrace="connector: $stacktrace_connector"
            fi

            if [ "$errors_from_trace" != "" ]
            then
                stacktrace="$stacktrace errors_from_trace: $errors_from_trace"
            fi

            if [ "$validation_errors" != "" ]
            then
                stacktrace="$stacktrace validation_errors: $validation_errors"
            fi

            if [ -z "$stacktrace" ]
            then
                stacktrace="-"
            fi

            printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status" "$tasks" "$stacktrace"
            echo "-------------------------------------------------------------------------------------------------------------"
        fi
    else
        logerror "❌ curl request failed with error code $ret!"
        exit 1
    fi
done