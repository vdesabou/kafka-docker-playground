codespace=$(codespace_pick "${args[--codespace]}") || exit 1

codespace_wait_ssh "$codespace" || exit 1
if ! ssh_config=$(codespace_ssh_config "$codespace")
then
    logerror "❌ could not get the ssh configuration of codespace $codespace (gh codespace ssh --config)"
    exit 1
fi
read -r cfg host <<< "$ssh_config"

log "👈 Sync codespace $codespace reproduction-models folder to local"
rsync -cauv --exclude '.git' --filter=':- .gitignore' -e "ssh -F $cfg" "$host:$(codespace_remote_root)/reproduction-models" "$root_folder"
ret=$?
rm -f "$cfg"
exit $ret
