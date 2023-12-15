get_connect_url_and_security
all="${args[--all]}"
verbose="${args[--verbose]}"

log "🎨 Displaying all connector plugins installed"
if [[ -n "$all" ]]
then
    log "🌕 Displaying also transforms, converters, predicates available"
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connector-plugins?connectorsOnly=false" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t"
    fi
    curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connector-plugins?connectorsOnly=false" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t
else
    if [[ -n "$verbose" ]]
    then
        log "🐞 curl command used"
        echo "curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connector-plugins" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t"
    fi
    curl $security -s -X GET -H "Content-Type: application/json" "$connect_url/connector-plugins" | jq -r '.[] | [.class , .version , .type] | @tsv' | column -t
fi
