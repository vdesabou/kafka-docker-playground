subject="${args[--subject]}"
global="${args[--global]}"
compatibility="${args[--compatibility]}"
verbose="${args[--verbose]}"

if [[ -n "$subject" ]] && [[ -n "$global" ]]
then
    logerror "❌ --subject and --global are mutually exclusive"
    exit 1
fi
if [[ ! -n "$subject" ]] && [[ ! -n "$global" ]]
then
    logerror "❌ set --subject <subject>, or --global for the rule of the whole registry"
    exit 1
fi

get_sr_url_and_security

path="/config"
if [[ -n "$subject" ]]
then
    log "🛡️ Set compatibility for subject ${subject} to $compatibility"
    path="/config/$(urlencode "${subject}")"
else
    log "🌍 Set the global compatibility of the registry to $compatibility"
fi
sr_request PUT "$path" "{\"compatibility\": \"$compatibility\"}" || sr_exit_on_error
# PUT /config answers {"compatibility": …} (GET answers compatibilityLevel)
echo "$sr_response" | jq -r '.compatibility // .compatibilityLevel'
