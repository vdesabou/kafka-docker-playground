subject="${args[--subject]}"
version="${args[--version]}"
id="${args[--id]}"
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
        versions=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions")
        ret=$?
        set -e
        if [ $ret -eq 0 ]
        then
            if echo "$versions" | jq -r .error_code >/dev/null 2>&1
            then
                error_code=$(echo "$versions" | jq -r .error_code)
                if [ "$error_code" != "null" ]
                then
                    message=$(echo "$versions" | jq -r .message)
                    logerror "Command failed with error code $error_code"
                    logerror "$message"
                    exit 1
                fi
            else
                for version in $(echo "${versions}" | jq -r '.[]')
                do
                    if test "$version" -eq "$version" 2>/dev/null
                    then
                        log "🧟 Soft deleting 💯 version ${version} from subject 🔰 ${subject}"
                        curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${version}" | jq .
                        if [[ -n "$permanent" ]]
                        then
                            log "💀 Hard deleting 💯 version ${version} from subject 🔰 ${subject}"
                            curl $sr_security -X DELETE -s "${sr_url}/subjects/${subject}/versions/${version}?permanent=true" | jq .
                        fi
                    else
                        logerror "$version is not a number"
                        exit 1
                    fi
                done
            fi
        else
            logerror "❌ curl request failed with error code $ret!"
            exit 1
        fi
    fi
fi