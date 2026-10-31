# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
name="${args[--name]}"
wait_running="${args[--wait]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

get_sr_url_and_security
sr_exporter_check_available || exit 1
for i in $(seq 1 15)
do
    sr_request GET "/exporters/${name}/status" || sr_exit_on_error "exporter ${name}"
    state=$(echo "$sr_response" | jq -r .state)
    if [[ ! -n "$wait_running" ]] || [ "$state" == "RUNNING" ] || [ "$state" == "PAUSED" ] || [ "$state" == "ERROR" ]
    then
        break
    fi
    sleep 2
done
if [[ -n "$json" ]]
then
    echo "$sr_response" | jq .
else
    echo "$sr_response" | jq -r '"🔗 exporter \(.name): \(.state), offset \(.offset), \(.objectsExported // 0) object(s) exported\(if .trace and .trace != "" then "\n   🔥 " + .trace else "" end)"'
fi
# ERROR, or PAUSED with a trace: the exporter stopped on a failure (a destination that refuses the IMPORT mode…)
trace=$(echo "$sr_response" | jq -r '.trace // empty')
if [ "$state" == "ERROR" ] || { [ "$state" == "PAUSED" ] && [ -n "$trace" ]; }
then
    exit 1
fi
exit 0
