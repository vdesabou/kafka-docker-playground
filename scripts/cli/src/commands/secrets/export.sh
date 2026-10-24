file="${args[--file]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"
confirmed="${args[--yes-i-want-plaintext]}"
only="${args[--only]:-all}"

if [[ ! -n "$confirmed" ]]
then
    logerror "❌ this writes every credential of profile $profile in clear text to $file"
    logerror "👉 re-run with --yes-i-want-plaintext if that is really what you want"
    exit 1
fi

#
# Compare physical absolute paths: a relative path (./x.properties, run from
# the repository) or a symlinked one would otherwise slip past the check.
#
file_dir=$(cd "$(dirname "$file")" 2> /dev/null && pwd -P || true)
if [ -z "$file_dir" ]
then
    logerror "❌ the folder of $file does not exist"
    exit 1
fi
file="${file_dir}/$(basename "$file")"
real_root_folder=$(cd "$root_folder" && pwd -P)

case "$file" in
    "$real_root_folder"/*)
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
    location=$(secret_store_location "$name" "$profile" || true)
    if [ "$only" != "all" ] && [ "$location" != "$only" ]
    then
        continue
    fi

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
