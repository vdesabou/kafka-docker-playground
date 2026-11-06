repo=$(codespace_repo)

log "🔘 listing your codespaces of $repo"
gh codespace list -R "$repo"
