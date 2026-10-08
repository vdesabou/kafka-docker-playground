target_context=$(playground state get run.docker_context_before_podman)
if [ -z "$target_context" ] || ! docker_with_user_config context inspect "$target_context" > /dev/null 2>&1
then
    # nothing remembered: Docker Desktop's context when it exists, the plain one otherwise
    if docker_with_user_config context inspect desktop-linux > /dev/null 2>&1
    then
        target_context="desktop-linux"
    else
        target_context="default"
    fi
fi

current_context=$(docker_with_user_config context show 2>/dev/null)
if [ "$current_context" = "$target_context" ]
then
    log "🐳 Already on docker context '$target_context'"
else
    warn_container_engine_switch "${current_context:-podman}"
    docker_with_user_config context use "$target_context" > /dev/null
    log "🐳 Switched to docker: docker context '$target_context'"
fi
playground state del run.docker_context_before_podman > /dev/null 2>&1 || true

reset_container_engine_detection
playground doctor
