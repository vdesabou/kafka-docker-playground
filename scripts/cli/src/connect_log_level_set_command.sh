ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

package="${args[--package]}"
level="${args[--level]}"

log "Set log level for package $package to $level"
curl $security -s --request PUT \
  --url "$connect_url/admin/loggers/$package" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data "{
 \"level\": \"$level\"
}" | jq .

playground connect-log-level get -p "$package"