time="${args[--time]}"

if [[ ! "$time" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]
then
    logerror "❌ --time $time is not a time HH:MM (00:00 to 23:59)"
    exit 1
fi
hour=$((10#${BASH_REMATCH[1]}))
minute=$((10#${BASH_REMATCH[2]}))

nightly_cleanup_files
mkdir -p "$(dirname "$nightly_cleanup_log")"
playground_bin="$root_folder/scripts/cli/playground"
job_args=(cloud-resources cleanup --resource ccloud --force --nightly)

if ! command -v jq > /dev/null 2>&1
then
    logwarn "⚠️ jq is not installed on this machine: the job would need Docker running at night, install jq (brew install jq)"
fi

if [[ "$OSTYPE" == "darwin"* ]]
then
    # the agent gets no shell startup file: it runs with the PATH of this shell (bash 4+, confluent, jq)
    xml_escape () { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<< "$1"; }
    mkdir -p "$(dirname "$nightly_cleanup_plist")"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0">'
        echo '<dict>'
        echo "  <key>Label</key><string>$NIGHTLY_CLEANUP_LABEL</string>"
        echo '  <key>ProgramArguments</key>'
        echo '  <array>'
        echo "    <string>$(xml_escape "$playground_bin")</string>"
        for arg in "${job_args[@]}"
        do
            echo "    <string>$arg</string>"
        done
        echo '  </array>'
        echo '  <key>EnvironmentVariables</key>'
        echo '  <dict>'
        echo "    <key>PATH</key><string>$(xml_escape "$PATH")</string>"
        echo "    <key>HOME</key><string>$(xml_escape "$HOME")</string>"
        echo "    <key>USER</key><string>$(xml_escape "$USER")</string>"
        echo '  </dict>'
        echo '  <key>StartCalendarInterval</key>'
        echo "  <dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>"
        echo "  <key>StandardOutPath</key><string>$(xml_escape "$nightly_cleanup_log")</string>"
        echo "  <key>StandardErrorPath</key><string>$(xml_escape "$nightly_cleanup_log")</string>"
        echo '</dict>'
        echo '</plist>'
    } > "$nightly_cleanup_plist"
    if ! plutil -lint "$nightly_cleanup_plist" > /dev/null
    then
        logerror "❌ invalid launchd agent $nightly_cleanup_plist"
        exit 1
    fi
    launchctl bootout "gui/$(id -u)/$NIGHTLY_CLEANUP_LABEL" > /dev/null 2>&1 || true
    if ! launchctl bootstrap "gui/$(id -u)" "$nightly_cleanup_plist"
    then
        logerror "❌ could not load the launchd agent $nightly_cleanup_plist"
        exit 1
    fi
    log "🌙 nightly cleanup scheduled every day at $(printf '%02d:%02d' $hour $minute) (launchd agent $nightly_cleanup_plist, also run when the Mac wakes up after that time)"
elif command -v crontab > /dev/null 2>&1
then
    line="$minute $hour * * * PATH='$PATH' HOME='$HOME' USER='$USER' '$playground_bin' ${job_args[*]} >> '$nightly_cleanup_log' 2>&1 $NIGHTLY_CLEANUP_MARKER"
    { crontab -l 2> /dev/null | grep -vF "$NIGHTLY_CLEANUP_MARKER"; echo "$line"; } | crontab -
    log "🌙 nightly cleanup scheduled every day at $(printf '%02d:%02d' $hour $minute) (crontab, skipped when the machine is off)"
else
    logerror "❌ neither launchd (macOS) nor crontab found: schedule this yourself: $playground_bin ${job_args[*]}"
    exit 1
fi
log "📄 log: $nightly_cleanup_log"
log "🔑 the confluent CLI must stay logged in: confluent login --save"
log "🔎 what tonight's run would delete, as of now:"
playground cloud-resources cleanup --resource ccloud --nightly --dry-run
log "👉 playground cloud-resources nightly-cleanup status   # after the first night"
