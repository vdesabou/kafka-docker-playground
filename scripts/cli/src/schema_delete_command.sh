subject="${args[--subject]}"
version="${args[--version]}"
permanent="${args[--permanent]}"

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

if [[ -n "$version" ]]
then
    if [[ ! -n "$subject" ]]
    then
        logerror "❌ --version is set without --subject being set"
        exit 1
    fi
fi

# https://docs.confluent.io/platform/current/schema-registry/develop/api.html#delete--subjects-(string-%20subject)-versions-(versionId-%20version)
if [[ -n "$subject" ]]
then
    if [[ -n "$version" ]]
    then
        log "🧟 Soft deleting 💯 version ${version} from subject 🔰 ${subject}"
        curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${version}" | jq .
        if [[ -n "$permanent" ]]
        then
            log "💀 Hard deleting 💯 version ${version} from subject 🔰 ${subject}"
            curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${version}?permanent=true" | jq .
        fi
    else
        logwarn "--version is not set, deleting all versions !"
        log "🧟 Soft deleting subject 🔰 ${subject}"
        curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}" | jq .
        if [[ -n "$permanent" ]]
        then
            log "💀 Hard deleting  subject 🔰 ${subject}"
            curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}?permanent=true" | jq .
        fi
    fi
fi