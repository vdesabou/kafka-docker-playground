subject="${args[--subject]}"
version="${args[--version]}"
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

# https://docs.confluent.io/platform/current/schema-registry/develop/api.html#delete--subjects-(string-%20subject)-versions-(versionId-%20version)
if [[ -n "$subject" ]]
then
    if [[ -n "$version" ]]
    then
        log "🧟 Soft deleting 💯 version ${version} from subject 🔰 ${subject}"
        #url encode subject
        subject=$(urlencode "${subject}")
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
        logwarn "--version is not set, deleting all versions !"
        log "🧟 Soft deleting subject 🔰 ${subject}"
        #url encode subject
        subject=$(urlencode "${subject}")
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