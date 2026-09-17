file="${args[--file]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"
shred="${args[--shred]}"

force=""
if [[ -n "${args[--secret]}" ]]
then
    force="secret"
elif [[ -n "${args[--plain]}" ]]
then
    force="plain"
fi

backend=$(get_secret_backend)

# with --plain nothing reaches the backend, so do not ask it to be unlocked
if [ "$force" != "plain" ]
then
    secret_backend_ready "$backend" || exit 1
    log "📥 Importing $file into profile $profile (backend: $backend)"
else
    log "📥 Importing $file into profile $profile as plain variables"
fi

nb_secrets=0
nb_plain=0
nb_skipped=0

while IFS= read -r line || [ -n "$line" ]
do
    # skip comments and blank lines
    case "$line" in
        ''|\#*|\;*) continue ;;
    esac

    # tolerate `export FOO=bar`
    line="${line#export }"

    case "$line" in
        *=*) ;;
        *) continue ;;
    esac

    name="${line%%=*}"
    value="${line#*=}"

    # trim surrounding whitespace on the name
    name="$(echo "$name" | tr -d '[:space:]')"

    if [[ ! "$name" =~ ^[A-Z][A-Z0-9_]*$ ]]
    then
        logwarn "⏭️ skipping <$name>, not an uppercase environment variable name"
        nb_skipped=$((nb_skipped+1))
        continue
    fi

    # strip one level of surrounding quotes
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac

    if [ -z "$value" ]
    then
        logwarn "⏭️ skipping $name, empty value"
        nb_skipped=$((nb_skipped+1))
        continue
    fi

    if secret_store_value "$name" "$value" "$profile" "$force"
    then
        if [ "$(secret_store_location "$name" "$profile" || true)" == "secret" ]
        then
            nb_secrets=$((nb_secrets+1))
        else
            nb_plain=$((nb_plain+1))
        fi
    else
        nb_skipped=$((nb_skipped+1))
    fi
done < "$file"

log "✅ Imported $nb_secrets secret(s) and $nb_plain plain variable(s), $nb_skipped skipped"

if [[ -n "$shred" ]]
then
    if [ $nb_secrets -eq 0 ] && [ $nb_plain -eq 0 ]
    then
        logwarn "⚠️ nothing was imported, $file is left untouched"
        exit 0
    fi
    log "🔥 Securely deleting $file"
    if command -v shred > /dev/null 2>&1
    then
        shred -u "$file"
    elif [[ "$OSTYPE" == "darwin"* ]]
    then
        rm -P "$file"
    else
        rm -f "$file"
    fi
    log "✅ $file deleted"
else
    logwarn "⚠️ $file still contains your credentials in clear text"
    logwarn "👉 re-run with --shred to securely delete it, or delete it yourself"
fi
