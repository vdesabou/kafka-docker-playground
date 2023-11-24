get_connect_url_and_security

package="${args[--package]}"

if [[ -n "$package" ]]
then
  log "🧬 Get log level for package $package"
  curl $security -s "$connect_url/admin/loggers/$package"
else
  log "🧬 Get log level for all packages"
  curl $security -s "$connect_url/admin/loggers" | jq .
fi