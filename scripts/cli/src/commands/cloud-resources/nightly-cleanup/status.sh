lines="${args[--lines]}"
nightly_cleanup_files
if [[ "$OSTYPE" == "darwin"* ]]
then
    if [ -f "$nightly_cleanup_plist" ]
    then
        hour=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Hour" "$nightly_cleanup_plist" 2> /dev/null)
        minute=$(/usr/libexec/PlistBuddy -c "Print :StartCalendarInterval:Minute" "$nightly_cleanup_plist" 2> /dev/null)
        if launchctl print "gui/$(id -u)/$NIGHTLY_CLEANUP_LABEL" > /dev/null 2>&1
        then
            log "🌙 nightly cleanup scheduled every day at $(printf '%02d:%02d' "$hour" "$minute") (launchd agent loaded)"
        else
            logwarn "⚠️ $nightly_cleanup_plist exists but is not loaded: playground cloud-resources nightly-cleanup enable"
        fi
    else
        log "💤 the nightly cleanup is not scheduled: playground cloud-resources nightly-cleanup enable"
    fi
else
    line=$(crontab -l 2> /dev/null | grep -F "$NIGHTLY_CLEANUP_MARKER")
    if [ -n "$line" ]
    then
        log "🌙 nightly cleanup scheduled every day at $(printf '%02d:%02d' "$(echo "$line" | awk '{print $2}')" "$(echo "$line" | awk '{print $1}')") (crontab)"
    else
        log "💤 the nightly cleanup is not scheduled: playground cloud-resources nightly-cleanup enable"
    fi
fi
if [ -f "$nightly_cleanup_log" ]
then
    log "📄 last $lines lines of $nightly_cleanup_log:"
    tail -n "$lines" "$nightly_cleanup_log"
else
    log "📄 no run yet ($nightly_cleanup_log)"
fi
