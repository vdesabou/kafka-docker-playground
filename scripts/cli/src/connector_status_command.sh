ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

connectors=$(curl -s $security "$connect_url/connectors/" | jq -r '.[]')

printf "%-30s %-10s %-15s %-50s\n" "Connector Name" "Status" "Tasks" "Stack Trace"
echo "----------------------------------------------------------------------------------------------"

for connector in $connectors
do
    status=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.connector.state')
    tasks=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.tasks[].state' | tr '\n' ',' | sed 's/,$/\n/')
    stacktrace=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.connector.trace | select(length > 0)')
    
    if [ -z "$stacktrace" ]
    then
        stacktrace="-"
    fi
    
    printf "%-30s %-10s %-15s %-50s\n" "$connector" "$status" "$tasks" "$stacktrace"
done