# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
name="${args[--name]}"
to="${args[--to]}"
destination_url="${args[--destination-url]}"
destination_auth="${args[--destination-auth]}"
context_type="${args[--context-type]}"
destination_context="${args[--destination-context]}"
subjects="${args[--subjects]}"
subject_rename_format="${args[--subject-rename-format]}"
verbose="${args[--verbose]}"

get_sr_url_and_security
sr_exporter_check_available || exit 1

if [ -z "$destination_url" ]
then
    if [[ "$environment" != mdc* ]]
    then
        logerror "❌ set --destination-url (and --destination-auth if needed): --to only works in an mdc-* environment"
        exit 1
    fi
    if [ -z "$to" ]
    then
        if [ "$mdc_cluster" == "europe" ]
        then
            to="us"
        else
            to="europe"
        fi
    fi
    # the exporter runs in the source registry: the destination url is the one of the docker network
    destination_url="http://schema-registry-${to}:8081"
fi

if [ -z "$context_type" ]
then
    if [ -n "$destination_context" ]
    then
        context_type="CUSTOM"
    else
        context_type="AUTO"
    fi
fi
if [ "$context_type" == "CUSTOM" ] && [ -z "$destination_context" ]
then
    logerror "❌ --context-type CUSTOM needs --destination-context <name>"
    exit 1
fi

config=$(jq -cn --arg url "$destination_url" --arg auth "$destination_auth" \
    '{"schema.registry.url": $url} + (if $auth != "" then {"basic.auth.credentials.source": "USER_INFO", "basic.auth.user.info": $auth} else {} end)')
body=$(jq -cn --arg name "$name" --arg ct "$context_type" --arg ctx "${destination_context#.}" --arg subjects "${subjects:-*}" \
    --arg fmt "$subject_rename_format" --argjson config "$config" \
    '{name: $name, contextType: $ct, subjects: ($subjects | split(",") | map(gsub("^\\s+|\\s+$"; "")))}
     + (if $ct == "CUSTOM" then {context: $ctx} else {} end)
     + (if $fmt != "" then {subjectRenameFormat: $fmt} else {} end)
     + {config: $config}')
log "🔗 Creating exporter ${name}: subjects ${subjects:-*} → ${destination_url} (context type ${context_type}${destination_context:+, context .${destination_context#.}})"
sr_request POST "/exporters" "$body" || sr_exit_on_error "exporter ${name}"
playground schema exporter status --name "$name" ${args[--cluster]:+--cluster ${args[--cluster]}} --wait
