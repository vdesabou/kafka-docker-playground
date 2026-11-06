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
  if ! gh codespace stop -c "$c"
  then
    logerror "❌ could not stop codespace $c"
    continue
  fi
  if state=$(codespace_wait_state "$c" "Shutdown" 120)
  then
    log "✅ codespace $c is stopped: its disk is kept, 'playground codespace start --codespace $c' to resume"
  else
    logwarn "⚠️ codespace $c is still $state after 2 minutes"
  fi
done
