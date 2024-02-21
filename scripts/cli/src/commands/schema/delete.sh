subject="${args[--subject]}"
version="${args[--version]}"
id="${args[--id]}"
permanent="${args[--permanent]}"
verbose="${args[--verbose]}"

get_sr_url_and_security

if [[ -n "$version" ]]
then
    if [[ ! -n "$subject" ]]
    then
        logerror "❌ --version is set without --subject being set"
        exit 1
    fi
fi

if [[ -n "$id" ]]
then
    if [[ ! -n "$subject" ]]
    then
        logerror "❌ --id is set without --subject being set"
        exit 1
    fi
fi

# https://docs.confluent.io/platform/current/schema-registry/develop/api.html#delete--subjects-(string-%20subject)-versions-(versionId-%20version)
if [[ -n "$subject" ]]
then
    if [[ -n "$version" ]]
    then
        log "🧟 Soft deleting 💯 version ${version} from subject 🔰 ${subject}"
        if [[ -n "$verbose" ]]
        then
            log "🐞 curl command used"
            echo "curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${version}""
        fi
        curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${version}" | jq .
        if [[ -n "$permanent" ]]
        then
            log "💀 Hard deleting 💯 version ${version} from subject 🔰 ${subject}"
            if [[ -n "$verbose" ]]
            then
                log "🐞 curl command used"
                echo "curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${version}?permanent=true""
            fi
            curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${version}?permanent=true" | jq .
        fi
    else
        if [[ -n "$version" ]]
        then
            log "🧟 Soft deleting 🫵 id ${id} for subject 🔰 ${subject}"
            if [[ -n "$verbose" ]]
            then
                log "🐞 curl command used"
                echo "curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${id}""
            fi
            curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${id}" | jq .
            if [[ -n "$permanent" ]]
            then
                log "💀 Hard deleting 🫵 id ${id} for subject 🔰 ${subject}"
                if [[ -n "$verbose" ]]
                then
                    log "🐞 curl command used"
                    echo "curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${id}?permanent=true""
                fi
                curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${id}?permanent=true" | jq .
            fi
        else
            logwarn "--version is not set, deleting all versions !"
            log "🧟 Soft deleting subject 🔰 ${subject}"
            if [[ -n "$verbose" ]]
            then
                log "🐞 curl command used"
                echo "curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}""
            fi
            curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}" | jq .
            if [[ -n "$permanent" ]]
            then
                log "💀 Hard deleting subject 🔰 ${subject}"
                if [[ -n "$verbose" ]]
                then
                    log "🐞 curl command used"
                    echo "curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}?permanent=true""
                fi
                curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}?permanent=true" | jq .
            fi
        fi
    fi
fi