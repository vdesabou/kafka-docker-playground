secrets_file=$(get_secrets_file)
env_file=$(get_env_file)
plain="${args[--plain]}"

if [[ -n "$plain" ]]
then
    file="$env_file"
    [ -f "$file" ] || { : > "$file"; chmod 0644 "$file"; }
else
    file="$secrets_file"
    [ -f "$file" ] || { : > "$file"; chmod 0600 "$file"; }

    backend=$(get_secret_backend)
    if [ "$backend" == "file" ]
    then
        logwarn "⚠️ the file backend is in use: $file contains your credentials in clear text"
    else
        log "🔐 Backend is $backend, so $file only contains references, not values"
    fi
fi

editor=$(playground config get editor || true)
[ -z "$editor" ] && editor="${EDITOR:-vi}"

log "📖 Opening $file with $editor"
$editor "$file"

# the editor may have recreated the file with default permissions
if [ "$file" == "$secrets_file" ]
then
    chmod 0600 "$file"
fi
