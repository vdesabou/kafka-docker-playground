ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connectors=$(curl -s $security "$connect_url/connectors/" | jq -r '.[]')

printf "%-30s %-12s %-30s %-50s\n" "Name" "Status" "Tasks" "Stack Trace"
echo "------------------------------------------------------------------------------------------------------------------------"

for connector in $connectors
do
    # Get the status of the connector and pretty-print using jq
    status=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.connector.state')

    # Add emoji based on status
    if [ "$status" == "RUNNING" ]
    then
        status="✅ RUNNING"
    elif [ "$status" == "PAUSED" ]
    then
        status="⏸️  PAUSED"
    elif [ "$status" == "FAILED" ]
    then
        status="❌ FAILED"
    else
        status="🤔 UNKNOWN"
    fi
    
    tasks=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.tasks[] | "\(.id):\(.state)"' | tr '\n' ',' | sed 's/,$/\n/')
    
    # Add emoji based on tasks
    if [[ "$tasks" == *"RUNNING"* ]]
    then
        tasks="${tasks//RUNNING/🟢 RUNNING}"
    elif [[ "$tasks" == *"PAUSED"* ]]
    then
        tasks="${tasks//PAUSED/⏸️  PAUSED}"
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

    # Print the data for each connector in row format
    printf "%-30s %-12s %-30s %-50s\n" "$connector" "$status" "$tasks" "$stacktrace"

    echo "------------------------------------------------------------------------------------------------------------------------"
done