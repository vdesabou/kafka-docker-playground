get_connect_url_and_security

connector="${args[--connector]}"
verbose="${args[--verbose]}"

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
    set +e
    log "🧩 Displaying connector status for $connector"
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl -s $security "$connect_url/connectors/$connector/status""
    fi
    printf "%-30s %-12s %-60s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
    echo "-----------------------------------------------------------------------------------------------------------------------------"
    status=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.connector.state')

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
    
    tasks=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.tasks[] | "\(.id):\(.state)[\(.worker_id)]"' | tr '\n' ',' | sed 's/,$/\n/' | sed 's/:8083//g' | sed 's/:8283//g' | sed 's/:8383//g')
    
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
    
    stacktrace_connector=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.connector.trace | select(length > 0)')
    stacktrace_tasks=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.tasks[].trace | select(length > 0)')
    stacktrace=""
    if [ "$stacktrace_connector" != "" ]
    then
        stacktrace="connector: $stacktrace_connector"
    fi

    if [ "$stacktrace_tasks" != "" ]
    then
        stacktrace="$stacktrace tasks: $stacktrace_tasks"
    fi

    if [ -z "$stacktrace" ]
    then
        stacktrace="-"
    fi

    printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status" "$tasks" "$stacktrace"
    echo "-------------------------------------------------------------------------------------------------------------"
done