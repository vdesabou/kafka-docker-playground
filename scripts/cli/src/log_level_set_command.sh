ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

package="${args[--package]}"
level="${args[--level]}"

current_level=$(curl $security -s "$connect_url/admin/loggers/$package" | jq -r '.level')

if [ "$current_level" != "$level" ]
then
    log "🧬 Set log level for package $package to $level"
    curl $security -s --request PUT \
    --url "$connect_url/admin/loggers/$package" \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data "{
    \"level\": \"$level\"
    }" | jq .

    playground log-level get -p "$package"
else
    log "🧬⏭️ Skipping as log level for package $package was already set to $level"
fi