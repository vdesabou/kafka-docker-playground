machine="${args[--machine]}"
branch="${args[--branch]}"
suffix="${args[--suffix]}"
location="${args[--location]}"
no_open="${args[--no-open]}"
push_secrets="${args[--push-secrets]}"
sync_repro_folder="${args[--sync-repro-folder]}"

repo=$(codespace_repo)

case "$machine" in
  4-core) machine_name="standardLinux32gb" ;;
  8-core) machine_name="premiumLinux" ;;
  16-core) machine_name="largePremiumLinux" ;;
esac

# the machines depend on your account (a personal account may only get 4-core): check before creating
available=$(gh api "repos/$repo/codespaces/machines" --jq '.machines[] | "\(.name) \(.cpus) \(.memory_in_bytes / 1073741824 | floor)"' 2> /dev/null)
if [ -n "$available" ] && ! echo "$available" | grep -q "^$machine_name "
then
  logerror "❌ $machine ($machine_name) is not available to your account for $repo. Available:"
  echo "$available" | while read -r name cpus memory
  do
    logerror "   --machine ${cpus}-core   ($name, $memory GB)"
  done
  exit 1
fi

if [[ ! -n "$suffix" ]]
then
  suffix=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
fi
username=$(whoami | tr -d '.' | tr '[:upper:]' '[:lower:]')
# gh allows 48 characters for a display name
display_name=$(echo "pg-${username}-${suffix}" | cut -c1-48)

create_args=(-R "$repo" -b "$branch" -m "$machine_name" -d "$display_name" --default-permissions)
if [[ -n "$location" ]]
then
  create_args+=(-l "$location")
fi

log "👷 creating codespace $display_name ($machine, branch $branch of $repo)"
if ! codespace=$(gh codespace create "${create_args[@]}")
then
  logerror "❌ gh codespace create failed, see the error above"
  exit 1
fi
codespace=$(echo "$codespace" | tail -1)
log "✅ codespace $codespace created"
log "📥 the default images are already there with a prebuild, otherwise they are pulled in the background (Codespaces: View Creation Log)"
log "💰 it uses your Codespaces quota while it runs: 'playground codespace stop' when you pause, 'playground codespace delete' when you are done"

if [[ -n "$push_secrets" ]] || [[ -n "$sync_repro_folder" ]]
then
  log "⏳ waiting for codespace $codespace to be available"
  if ! state=$(codespace_wait_state "$codespace" "Available")
  then
    logerror "❌ codespace $codespace is still $state after 5 minutes, run 'playground codespace push-secrets' / 'sync-repro-folder local-to-codespace' yourself later"
    exit 1
  fi
  if [[ -n "$push_secrets" ]]
  then
    playground codespace push-secrets --codespace "$codespace" || logwarn "⚠️ push-secrets failed, run it again: playground codespace push-secrets --codespace $codespace"
  fi
  if [[ -n "$sync_repro_folder" ]]
  then
    playground codespace sync-repro-folder local-to-codespace --codespace "$codespace" || logwarn "⚠️ the sync failed, run it again: playground codespace sync-repro-folder local-to-codespace --codespace $codespace"
  fi
fi

if [[ -n "$no_open" ]]
then
  log "👉 open it with: playground codespace open --codespace $codespace"
  exit 0
fi

playground codespace open --codespace "$codespace"
