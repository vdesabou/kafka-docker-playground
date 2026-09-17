file="${args[--file]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"
confirmed="${args[--yes-i-want-plaintext]}"

if [[ ! -n "$confirmed" ]]
then
    logerror "❌ this writes every credential of profile $profile in clear text to $file"
    logerror "👉 re-run with --yes-i-want-plaintext if that is really what you want"
    exit 1
fi

case "$file" in
    "$root_folder"/*)
        logerror "❌ refusing to write credentials inside the repository ($root_folder)"
        logerror "👉 pick a path outside the repo, it would be one 'git add -A' away from being committed"
        exit 1
    ;;
esac

tmp="${file}.tmp.$$"
: > "$tmp"
chmod 0600 "$tmp"

nb=0
for name in $(secret_store_names "$profile")
do
    if value=$(secret_get "$name" "$profile")
    then
        printf "%s=%s\n" "$name" "$value" >> "$tmp"
        nb=$((nb+1))
    else
        logwarn "⚠️ $name could not be resolved, skipped"
    fi
done

mv -f "$tmp" "$file"
chmod 0600 "$file"

log "📤 Exported $nb variable(s) of profile $profile to $file (mode 0600)"
logwarn "⚠️ $file now contains credentials in clear text, delete it as soon as you are done"
