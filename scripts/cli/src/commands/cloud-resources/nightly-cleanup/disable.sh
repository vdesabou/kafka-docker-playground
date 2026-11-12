nightly_cleanup_files
removed=0
if [[ "$OSTYPE" == "darwin"* ]]
then
    launchctl bootout "gui/$(id -u)/$NIGHTLY_CLEANUP_LABEL" > /dev/null 2>&1 && removed=1
    if [ -f "$nightly_cleanup_plist" ]
    then
        rm -f "$nightly_cleanup_plist"
        removed=1
    fi
elif command -v crontab > /dev/null 2>&1 && crontab -l 2> /dev/null | grep -qF "$NIGHTLY_CLEANUP_MARKER"
then
    crontab -l 2> /dev/null | grep -vF "$NIGHTLY_CLEANUP_MARKER" | crontab -
    removed=1
fi
if [ $removed -eq 1 ]
then
    log "🛑 nightly cleanup disabled (its log stays in $nightly_cleanup_log)"
else
    log "🤷 the nightly cleanup was not scheduled"
fi
