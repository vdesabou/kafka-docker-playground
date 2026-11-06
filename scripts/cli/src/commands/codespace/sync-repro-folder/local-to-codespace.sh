codespace=$(codespace_pick "${args[--codespace]}") || exit 1

if [ ! -d "$root_folder/reproduction-models" ]
then
    logerror "❌ $root_folder/reproduction-models does not exist: git submodule update --init reproduction-models"
    exit 1
fi

codespace_wait_ssh "$codespace" || exit 1
if ! ssh_config=$(codespace_ssh_config "$codespace")
then
    logerror "❌ could not get the ssh configuration of codespace $codespace (gh codespace ssh --config)"
    exit 1
fi
read -r cfg host <<< "$ssh_config"

log "👉 Sync local reproduction-models folder to codespace $codespace"
rsync -cauv --exclude '.git' --filter=':- .gitignore' -e "ssh -F $cfg" "$root_folder/reproduction-models" "$host:$(codespace_remote_root)"
ret=$?
rm -f "$cfg"
exit $ret
