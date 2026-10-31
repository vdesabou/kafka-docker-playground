# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
subject="${args[--subject]}"
global="${args[--global]}"
json="${args[--json]}"
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

source="subject"
if [[ -n "$subject" ]]
then
    [[ -n "$json" ]] || log "🛡️ Get compatibility for subject ${subject}"
    if ! sr_request GET "/config/$(urlencode "${subject}")"
    then
        # 40408: no subject-level rule, 40401: unknown subject: the global rule applies
        if [ "$sr_error_code" != "40408" ] && [ "$sr_error_code" != "40401" ]
        then
            sr_exit_on_error
        fi
        source="global"
    fi
else
    source="global"
fi

if [ "$source" == "global" ]
then
    sr_global_compatibility
    compatibility="$sr_global_compatibility_value"
else
    compatibility=$(echo "$sr_response" | jq -r '.compatibilityLevel // .compatibility')
fi

if [[ -n "$json" ]]
then
    jq -n --arg subject "$subject" --arg compatibility "$compatibility" --arg source "$source" \
        '{subject: (if $subject == "" then null else $subject end), compatibility: $compatibility, source: $source}'
    exit 0
fi

if [[ -n "$subject" ]] && [ "$source" == "global" ]
then
    log "🌍 subject ${subject} has no subject-level rule: the global rule of the registry applies"
elif [[ -n "$subject" ]]
then
    log "🔰 subject-level rule of ${subject}"
else
    log "🌍 global rule of the registry"
fi
echo "$compatibility"
