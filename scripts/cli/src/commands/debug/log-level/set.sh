get_connect_url_and_security

package="${args[--package]}"
level="${args[--level]}"

current_level=$(curl $security -s "$connect_url/admin/loggers/$package" | jq -r '.level')

if [ "$current_level" != "$level" ]
then
    get_connect_image
    if ! version_gt $CP_CONNECT_TAG "7.6.99"
    then
        log "🧬 Set log level for package $package to $level"
        curl $security -s --request PUT \
        --url "$connect_url/admin/loggers/$package" \
        --header 'Accept: application/json' \
        --header 'Content-Type: application/json' \
        --data "{
        \"level\": \"$level\"
        }" | jq .
    else
        log "🧬 Set log level for package $package to $level (scope=cluster)"
        curl $security -s --request PUT \
        --url "$connect_url/admin/loggers/$package?scope=cluster" \
        --header 'Accept: application/json' \
        --header 'Content-Type: application/json' \
        --data "{
        \"level\": \"$level\"
        }" | jq .
    fi

    playground debug log-level get -p "$package"
else
    log "🧬⏭️ Skipping as log level for package $package was already set to $level"
fi