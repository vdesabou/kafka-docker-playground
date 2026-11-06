codespace=$(codespace_pick "${args[--codespace]}") || exit 1

state=$(gh api "user/codespaces/$codespace" --jq .state)
if [ "$state" == "Available" ]
then
  log "🟢 codespace $codespace is already running"
  exit 0
fi

log "🟢 starting codespace $codespace"
if ! gh api -X POST "user/codespaces/$codespace/start" --silent
then
  logerror "❌ could not start codespace $codespace"
  exit 1
fi

# usually about a minute
for i in $(seq 1 60)
do
  state=$(gh api "user/codespaces/$codespace" --jq .state 2> /dev/null)
  if [ "$state" == "Available" ]
  then
    log "✅ codespace $codespace is available: playground codespace open --codespace $codespace"
    exit 0
  fi
  sleep 5
done
logerror "❌ codespace $codespace is still $state after 5 minutes"
exit 1
