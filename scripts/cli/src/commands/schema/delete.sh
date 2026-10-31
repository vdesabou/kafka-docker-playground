# errexit can be left on by a filter or a library function: the checks below handle the failures themselves
set +e
subject="${args[--subject]}"
version="${args[--version]}"
permanent="${args[--permanent]}"
dry_run="${args[--dry-run]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

encoded_subject=$(urlencode "${subject}")

# the versions that will be deleted, with their ids (soft-deleted versions are included: a permanent delete removes them too)
sr_request GET "/subjects/${encoded_subject}/versions?deleted=true" || sr_exit_on_error "subject ${subject}"
all_versions=$(echo "$sr_response" | jq -r '.[]')
if [[ -n "$version" ]]
then
    if ! echo "$all_versions" | grep -qx "$version"
    then
        logerror "❌ subject ${subject} has no version ${version} (versions: $(echo $all_versions | tr ' ' ','))"
        exit 1
    fi
    target_versions="$version"
else
    target_versions="$all_versions"
fi

# explain a refused delete: the version is used as a reference by other schemas
function explain_references() {
    local v
    for v in $target_versions
    do
        if sr_request GET "/subjects/${encoded_subject}/versions/${v}/referencedby" && [ "$(echo "$sr_response" | jq 'length')" != "0" ]
        then
            for ref_id in $(echo "$sr_response" | jq -r '.[]')
            do
                if sr_request GET "/schemas/ids/${ref_id}/versions"
                then
                    logerror "   🔗 version ${v} is referenced by schema id ${ref_id}: $(echo "$sr_response" | jq -r 'map("\(.subject) v\(.version)") | join(", ")')"
                fi
            done
        fi
    done
    logerror "   delete the referencing schemas first, or keep this version"
}

if [[ -n "$dry_run" ]]
then
    log "🧪 dry run: nothing is deleted"
    for v in $target_versions
    do
        if sr_request GET "/subjects/${encoded_subject}/versions/${v}?deleted=true"
        then
            id=$(echo "$sr_response" | jq -r .id)
            deleted=$(echo "$sr_response" | jq -r '.deleted // false')
            used_by=""
            if sr_request GET "/schemas/ids/${id}/versions?deleted=true"
            then
                used_by=$(echo "$sr_response" | jq -r --arg s "$subject" 'map(select(.subject != $s)) | map("\(.subject) v\(.version)") | join(", ")')
            fi
            if [ "$deleted" == "true" ]
            then
                state="🧟 already soft deleted"
            else
                state="🧟 soft delete"
            fi
            if [[ -n "$permanent" ]]
            then
                if [ -n "$used_by" ]
                then
                    log "💀 version ${v} (id ${id}): permanent delete, the id still resolves (also used by ${used_by})"
                else
                    log "💀 version ${v} (id ${id}): permanent delete, ❌ id ${id} will stop resolving: old records written with it can't be deserialized any more"
                fi
            else
                log "${state} of version ${v} (id ${id}): the id still resolves, existing records still deserialize"
            fi
        fi
    done
    exit 0
fi

if [[ -n "$version" ]]
then
    path="/subjects/${encoded_subject}/versions/${version}"
    what="💯 version ${version} from subject 🔰 ${subject}"
else
    logwarn "--version is not set, deleting all versions !"
    path="/subjects/${encoded_subject}"
    what="subject 🔰 ${subject}"
fi

log "🧟 Soft deleting ${what}"
if ! sr_request DELETE "$path"
then
    # 40404 / 40406: already soft deleted, fine when a permanent delete follows
    if [[ -n "$permanent" ]] && { [ "$sr_error_code" == "40404" ] || [ "$sr_error_code" == "40406" ]; }
    then
        log "🧟 already soft deleted"
    else
        logerror "❌ Command failed with error code $sr_error_code"
        logerror "$sr_error_message"
        [ "$sr_error_code" == "42206" ] && explain_references
        exit 1
    fi
else
    echo "$sr_response" | jq .
fi

if [[ -n "$permanent" ]]
then
    log "💀 Hard deleting ${what}"
    if ! sr_request DELETE "${path}?permanent=true"
    then
        logerror "❌ Command failed with error code $sr_error_code"
        logerror "$sr_error_message"
        [ "$sr_error_code" == "42206" ] && explain_references
        exit 1
    fi
    echo "$sr_response" | jq .
fi
