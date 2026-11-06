codespace="${args[--codespace]}"

if [[ -n "$codespace" ]]
then
  codespaces="$codespace"
else
  codespaces=$(codespace_list_json | jq -r '.[] | select(.state == "Available") | .name')
  if [ -z "$codespaces" ]
  then
    log "💤 no running codespace of $(codespace_repo)"
    exit 0
  fi
fi

for c in $codespaces
do
  log "🔴 stopping codespace $c"
  gh codespace stop -c "$c"
done
