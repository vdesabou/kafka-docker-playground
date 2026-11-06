codespace="${args[--codespace]}"

json=$(codespace_list_json)
if [[ -n "$codespace" ]]
then
  json=$(echo "$json" | jq --arg c "$codespace" '[.[] | select(.name == $c)]')
fi
if [ "$(echo "$json" | jq 'length')" == "0" ]
then
  if [[ -n "$codespace" ]]
  then
    logerror "❌ codespace $codespace was not found in your codespaces of $(codespace_repo)"
    exit 1
  fi
  log "💤 no codespace of $(codespace_repo)"
  exit 0
fi

log "❌ these codespaces will be deleted, with everything in them:"
echo "$json" | jq -r '.[] | "   \(.name) (\(.displayName)) branch \(.gitStatus.ref // "?"), \(.state)" + (if .gitStatus.hasUncommittedChanges then ", ⚠️ uncommitted changes" else "" end) + (if .gitStatus.hasUnpushedChanges then ", ⚠️ unpushed commits" else "" end)'
logwarn "⚠️ the reproduction models written in a codespace are lost with it"
check_if_continue

for c in $(echo "$json" | jq -r '.[].name')
do
  log "❌ deleting codespace $c"
  gh codespace delete -c "$c" --force
done
