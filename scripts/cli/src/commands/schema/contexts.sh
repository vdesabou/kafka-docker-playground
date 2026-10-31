# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
json="${args[--json]}"
verbose="${args[--verbose]}"

get_sr_url_and_security
sr_request GET "/contexts" || sr_exit_on_error
contexts="$sr_response"
if [[ -n "$json" ]]
then
    echo "$contexts" | jq .
    exit 0
fi
log "🗂️ Schema Registry contexts (. is the default context)"
for ctx in $(echo "$contexts" | jq -r '.[]')
do
    if [ "$ctx" == "." ]
    then
        n=$(curl $sr_security -s "${sr_url}/subjects" | jq '[.[] | select(startswith(":.") | not)] | length')
    else
        n=$(curl $sr_security -s "${sr_url}/contexts/${ctx}/subjects" | jq 'length')
    fi
    if [ "$ctx" == "." ]
    then
        mode=$(curl $sr_security -s "${sr_url}/mode" | jq -r '.mode // "?"')
    else
        mode=$(curl $sr_security -s "${sr_url}/contexts/${ctx}/mode" | jq -r '.mode // "?"')
    fi
    echo "   ${ctx}  ${n} subject(s)  mode ${mode}"
done
log "🎓 --context <ctx> on the schema commands reads and writes one context, e.g. playground schema list --context .europe"
