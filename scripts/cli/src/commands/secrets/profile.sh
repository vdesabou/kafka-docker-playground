profile="${args[profile]}"

if [[ ! -n "$profile" ]]
then
    active=$(get_active_secret_profile)
    log "🗂️ Active secrets profile: $active"
    echo ""
    for p in $(secret_store_profiles)
    do
        nb=$(secret_store_names "$p" | wc -l | tr -d ' ')
        if [ "$p" == "$active" ]
        then
            echo "👉 $p ($nb variable(s))"
        else
            echo "   $p ($nb variable(s))"
        fi
    done
    echo ""
    log "🎓 Tip: playground secrets profile <name> to switch"
    exit 0
fi

playground config set secrets.profile "$profile"
log "🗂️ Active secrets profile is now $profile ($(secret_store_names "$profile" | wc -l | tr -d ' ') variable(s))"
