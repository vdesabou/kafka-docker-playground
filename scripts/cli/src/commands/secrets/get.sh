name="${args[name]}"
reveal="${args[--reveal]}"
profile="${args[--profile]:-$(get_active_secret_profile)}"

if ! value=$(secret_get "$name" "$profile")
then
    logerror "❌ $name is not set and not stored in profile $profile"
    logerror "👉 playground secrets set $name"
    exit 1
fi

if [[ -n "$reveal" ]]
then
    printf '%s\n' "$value"
else
    log "🔐 $name $(secret_fingerprint "$value")"
    log "🎓 Tip: use --reveal to print the value"
fi
