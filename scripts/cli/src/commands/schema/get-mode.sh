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
    logerror "❌ set --subject <subject>, or --global for the mode of the whole registry"
    exit 1
fi

get_sr_url_and_security

source="subject"
if [[ -n "$subject" ]]
then
    [[ -n "$json" ]] || log "🔏 Get mode for subject ${subject}"
    if ! sr_request GET "/mode/$(urlencode "${subject}")"
    then
        # 40409: no subject-level mode (older registries answer 40401): the global mode applies
        if [ "$sr_error_code" != "40409" ] && [ "$sr_error_code" != "40401" ]
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
    sr_request GET "/mode" || sr_exit_on_error
fi
mode=$(echo "$sr_response" | jq -r '.mode')

if [[ -n "$json" ]]
then
    jq -n --arg subject "$subject" --arg mode "$mode" --arg source "$source" \
        '{subject: (if $subject == "" then null else $subject end), mode: $mode, source: $source}'
    exit 0
fi

if [[ -n "$subject" ]] && [ "$source" == "global" ]
then
    log "🌍 subject ${subject} has no subject-level mode: the global mode of the registry applies"
fi
echo "$mode"
