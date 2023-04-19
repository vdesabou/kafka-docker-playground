ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

package="${args[--package]}"

if [[ -n "$package" ]]
then
  log "🧬 Get log level for package $package"
  curl $security -s "$connect_url/admin/loggers/$package"
else
  log "🧬 Get log level for all packages"
  curl $security -s "$connect_url/admin/loggers" | jq .
fi