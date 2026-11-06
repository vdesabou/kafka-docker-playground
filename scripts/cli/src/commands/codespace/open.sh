web="${args[--web]}"

codespace=$(codespace_pick "${args[--codespace]}") || exit 1

code_args=(-c "$codespace")
if [[ -n "$web" ]]
then
  code_args+=(--web)
  log "🌐 opening codespace $codespace in VS Code in the browser"
else
  log "👨‍💻 opening codespace $codespace in VS Code"
fi

if ! gh codespace code "${code_args[@]}"
then
  logerror "❌ could not open codespace $codespace"
  if [[ ! -n "$web" ]]
  then
    logerror "👉 the local VS Code needs the GitHub Codespaces extension, or use: playground codespace open --codespace $codespace --web"
  fi
  exit 1
fi
