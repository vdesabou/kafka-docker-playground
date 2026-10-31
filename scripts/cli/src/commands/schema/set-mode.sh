subject="${args[--subject]}"
global="${args[--global]}"
mode="${args[--mode]}"
verbose="${args[--verbose]}"

if [[ -n "$subject" ]] && [[ -n "$global" ]]
then
    logerror "❌ --subject and --global are mutually exclusive"
    exit 1
fi
if [[ ! -n "$subject" ]] && [[ ! -n "$global" ]]
then
    logerror "❌ set --subject <subject>, or --global for the mode of the whole registry"
    exit 1
fi

get_sr_url_and_security

path="/mode"
if [[ -n "$subject" ]]
then
    log "🔏 Set mode for subject ${subject} to $mode"
    path="/mode/$(urlencode "${subject}")"
else
    log "🌍 Set the global mode of the registry to $mode"
fi
sr_request PUT "$path" "{\"mode\": \"$mode\"}" || sr_exit_on_error
echo "$sr_response" | jq -r '.mode'
