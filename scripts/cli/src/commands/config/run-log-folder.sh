folder="${args[folder]}"
folder="${folder/#\~/$HOME}"
if ! mkdir -p "$folder"
then
    logerror "❌ cannot create folder $folder"
    exit 1
fi
log "🗂️ configuring run-log-folder with $folder"
playground config set run-log-folder "$folder"
