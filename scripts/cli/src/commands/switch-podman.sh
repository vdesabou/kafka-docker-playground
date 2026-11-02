context_name="podman"
docs_url="https://kafka-docker-playground.io/#/how-to-use?id=🦭-using-podman-instead-of-docker"

if ! command -v podman > /dev/null 2>&1
then
    logerror "❌ podman is not installed"
    logerror "👉 $docs_url"
    exit 1
fi

# the rootful podman socket, as set up in the documentation
if [[ "$OSTYPE" == "darwin"* ]]
then
    # the machine to use: the default one, the only one, podman-machine-default, or the first one ('podman machine
    # inspect' without a name only looks for podman-machine-default)
    machines=$(podman machine list --format '{{.Name}}|{{.Default}}' 2>/dev/null)
    machine=$(echo "$machines" | awk -F'|' '$2 == "true" {print $1; exit}')
    if [ -z "$machine" ] && [ "$(echo "$machines" | grep -c .)" == "1" ]
    then
        machine=$(echo "$machines" | cut -d '|' -f 1)
    fi
    if [ -z "$machine" ] && echo "$machines" | grep -q '^podman-machine-default|'
    then
        machine="podman-machine-default"
    fi
    if [ -z "$machine" ] && [ -n "$machines" ]
    then
        machine=$(echo "$machines" | head -1 | cut -d '|' -f 1)
        logwarn "⚠️ several podman machines and no default one, using $machine (set it with 'podman system connection default')"
    fi
    if [ -z "$machine" ]
    then
        logerror "❌ no podman machine found, create one first:"
        logerror "  podman machine init --rootful --cpus 4 --memory 12288 --disk-size 100"
        logerror "👉 $docs_url"
        exit 1
    fi
    if [ "$(podman machine inspect "$machine" --format '{{.State}}' 2>/dev/null)" != "running" ]
    then
        log "🚀 Starting the podman machine $machine"
        podman machine start "$machine" > /dev/null
    fi
    podman_socket=$(podman machine inspect "$machine" --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)
else
    # the rootful socket of the documentation, otherwise the one podman reports (rootless user socket)
    podman_socket="/run/podman-api/podman.sock"
    if [ ! -S "$podman_socket" ]
    then
        podman_socket=$(podman info --format '{{.Host.RemoteSocket.Path}}' 2>/dev/null | sed 's#^unix://##')
    fi
fi

if [ ! -S "$podman_socket" ]
then
    logerror "❌ podman socket ${podman_socket:-<none>} does not exist, set up the rootful podman socket first"
    logerror "👉 $docs_url"
    exit 1
fi

current_context=$(docker_with_user_config context show 2>/dev/null)
if [ "$current_context" != "$context_name" ]
then
    warn_container_engine_switch "${current_context:-docker}"
    if [ -n "$current_context" ]
    then
        playground state set run.docker_context_before_podman "$current_context"
    fi
fi

if docker_with_user_config context inspect "$context_name" > /dev/null 2>&1
then
    docker_with_user_config context update "$context_name" --docker "host=unix://${podman_socket}" > /dev/null
else
    docker_with_user_config context create "$context_name" --description "Podman (kafka-docker-playground)" --docker "host=unix://${podman_socket}" > /dev/null
fi
docker_with_user_config context use "$context_name" > /dev/null

log "🦭 Switched to podman: docker context '$context_name' (unix://${podman_socket})"
if [ -n "$current_context" ] && [ "$current_context" != "$context_name" ]
then
    log "💺 'playground switch-docker' goes back to docker context '$current_context'"
fi

reset_container_engine_detection
playground doctor
