alias="${args[--alias]}"
json="${args[--json]}"
verbose="${args[--verbose]}"

if [[ "$environment" != "ccloud" ]]
then
    get_connect_image

    if ! version_gt $CP_CONNECT_TAG "7.4.1"
    then
        logerror "❌ subject aliases are available since CP 7.4.1 only"
        exit 1
    fi
fi

get_sr_url_and_security

[[ -n "$json" ]] || log "🔯 Get alias for alias ${alias}"
sr_request GET "/config/$(urlencode "${alias}")" || sr_exit_on_error
target=$(echo "$sr_response" | jq -r '.alias // empty')
if [[ -n "$json" ]]
then
    jq -n --arg alias "$alias" --arg subject "$target" '{alias: $alias, subject: (if $subject == "" then null else $subject end)}'
    exit 0
fi
if [ -z "$target" ]
then
    logerror "❌ ${alias} is not an alias"
    exit 1
fi
echo "$target"
