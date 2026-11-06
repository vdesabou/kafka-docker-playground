codespace=$(codespace_pick "${args[--codespace]}") || exit 1

if [ ${#other_args[@]} -eq 0 ]
then
  log "🐚 opening a shell in codespace $codespace"
  gh codespace ssh -c "$codespace"
  ret=$?
else
  log "🐚 running in codespace $codespace: ${other_args[*]}"
  # from the repository folder, with playground in the PATH (a non-interactive shell does not read the
  # block that .devcontainer/on-create.sh adds to ~/.bashrc); each argument is quoted so that it reaches
  # the remote shell as typed
  remote_command="cd /workspaces/$(basename "$(codespace_repo)") && export PATH=\"\$PWD/scripts/cli:\$PATH\" &&"
  for arg in "${other_args[@]}"
  do
    remote_command="$remote_command $(printf '%q' "$arg")"
  done
  gh codespace ssh -c "$codespace" -- "$remote_command"
  ret=$?
fi

if [ $ret -ne 0 ] && [ $ret -ne 130 ]
then
  logwarn "⚠️ ssh exited with code $ret. If it could not connect ('failed to start SSH server'): a codespace created before the SSH server was added to .devcontainer/, or from an older prebuild, has none: rebuild it with 'gh codespace rebuild -c $codespace'"
fi
exit $ret
