nb_errors=0
nb_warnings=0

function doctor_ok() {
    log "✅ $@"
}

function doctor_warn() {
    nb_warnings=$((nb_warnings+1))
    logwarn "$@"
}

function doctor_error() {
    nb_errors=$((nb_errors+1))
    logerror "$@"
}

log "🩺 Checking the container engine"

######################################################################
# the docker CLI itself
######################################################################
if ! command -v docker >/dev/null 2>&1
then
    doctor_error "the 'docker' CLI is not in your PATH"
    logerror "the playground always drives the engine through the 'docker' CLI, including with podman"
    logerror "  with docker  : https://docs.docker.com/get-docker"
    logerror "  with podman  : install the podman-docker package, which provides a 'docker' shim"
    exit 1
fi
doctor_ok "'docker' CLI found: $(docker --version 2>/dev/null)"

######################################################################
# which engine is behind it, and is it reachable
######################################################################
engine=$(get_container_engine)
if [ "$engine" = "podman" ]
then
    log "🦭 engine detected: podman"
else
    log "🐳 engine detected: docker"
fi
# in a subshell: the playground() wrapper exits when it cannot find the CLI, and
# remembering the engine must never end the checks
( playground state set run.container_engine "$engine" ) > /dev/null 2>&1 || true

if ! docker_info_error=$(docker info 2>&1 > /dev/null)
then
    doctor_error "the engine is not reachable"
    # "permission denied" and "no such file" call for different fixes, show which one
    echo "$docker_info_error" | grep -v '^\s*$' | tail -3
    log_container_engine_not_running "no-doctor-hint"
    exit 1
fi
doctor_ok "engine is reachable"

if [ ! -z "${DOCKER_HOST:-}" ]
then
    log "🔌 DOCKER_HOST is ${DOCKER_HOST}"
fi

######################################################################
# compose
######################################################################
compose_version=$(docker compose version --short 2>/dev/null)
if [ -z "$compose_version" ]
then
    doctor_error "'docker compose' is not available, every environment of the playground is started with it"
    logerror "install the compose v2 plugin: https://docs.docker.com/compose/install"
else
    if version_gt "2.0.0" "$compose_version"
    then
        doctor_error "'docker compose' is ${compose_version}, the playground needs 2.0.0 or greater"
    else
        doctor_ok "'docker compose' is ${compose_version}"
    fi
fi

if docker compose version 2>/dev/null | grep -qi "podman-compose"
then
    doctor_warn "'docker compose' is backed by podman-compose"
    logwarn "podman-compose is a separate reimplementation with partial support for profiles and build,"
    logwarn "which the playground relies on heavily. Prefer the real compose v2 plugin pointed at the"
    logwarn "podman socket with DOCKER_HOST."
fi

######################################################################
# memory
######################################################################
mem_total=$(docker info --format '{{.MemTotal}}' 2>/dev/null)
if [[ "$mem_total" =~ ^[0-9]+$ ]] && [ "$mem_total" -gt 0 ]
then
    mem_gb=$((mem_total/1024/1024/1024))
    if [ "$mem_gb" -lt 8 ]
    then
        doctor_warn "the engine only has ${mem_gb}GB of memory, the playground needs at least 8GB"
        if [ "$engine" = "podman" ]
        then
            logwarn "recreate the machine with more memory, for example:"
            logwarn "  podman machine stop && podman machine rm"
            logwarn "  podman machine init --cpus 4 --memory 12288 --disk-size 100 && podman machine start"
        else
            logwarn "raise it in Docker Desktop > Settings > Resources"
        fi
    else
        doctor_ok "engine memory is ${mem_gb}GB"
    fi
fi

######################################################################
# podman specific checks
#
# these use the native podman CLI when it is available: the docker compat API
# does not expose the registry, rootless or machine information we need
######################################################################
if [ "$engine" = "podman" ]
then
    # -- builder --------------------------------------------------------------
    # utils_function.sh only sets it when DOCKER_HOST mentions podman
    if [ "${DOCKER_BUILDKIT:-}" = "0" ]
    then
        doctor_ok "builds use the classic builder (DOCKER_BUILDKIT=0)"
    else
        doctor_error "builds would go through buildx, which ignores podman's local images and discards its result"
        logerror "the connect image would never get its extra tools (openssl, ...) and every SSL environment fails."
        logerror "the playground sets it automatically when DOCKER_HOST points at podman, otherwise:"
        logerror "  export DOCKER_BUILDKIT=0"
    fi

    if ! command -v podman >/dev/null 2>&1
    then
        logwarn "the native 'podman' CLI is not in the PATH, skipping the podman specific checks"
    else
        # ask the daemon the docker CLI really talks to: on Linux a bare `podman`
        # run by a regular user reports its own rootless setup, not the rootful
        # daemon behind DOCKER_HOST. Without DOCKER_HOST, the endpoint may come
        # from a docker context; with neither, `docker` is the podman-docker shim
        # and a bare `podman` is the same thing
        engine_endpoint="${DOCKER_HOST:-}"
        if [ -z "$engine_endpoint" ]
        then
            engine_endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
        fi
        podman_cli=(podman)
        if [[ "$engine_endpoint" == unix://* ]]
        then
            podman_cli=(podman --url "$engine_endpoint")
            log "🔎 podman checks are run against ${engine_endpoint}"
        else
            log "🔎 podman checks are run against the default podman connection"
        fi

        # -- version ---------------------------------------------------------
        # 4.9 is the oldest version the playground has run on (Ubuntu 24.04, CI).
        # 3.x has no netavark at all, which Ubuntu 22.04 still ships
        podman_version=$("${podman_cli[@]}" version --format '{{.Server.Version}}' 2>/dev/null)
        if [ -n "$podman_version" ]
        then
            if version_gt "4.0.0" "$podman_version"
            then
                doctor_error "podman ${podman_version} is too old, the playground needs podman 4.9 or later"
                logerror "it predates netavark, which containers need to resolve each other by name."
                logerror "Ubuntu 22.04 only ships podman 3.4: use Ubuntu 24.04 or later (playground ec2 does)"
            elif version_gt "4.9.0" "$podman_version"
            then
                doctor_warn "podman ${podman_version} is older than 4.9, the oldest version the playground was tested with"
            else
                doctor_ok "podman ${podman_version}"
            fi
        fi

        # -- OCI runtime -----------------------------------------------------
        # podman writes pids.limit=0 ("no limit") for containers created by docker run;
        # runc 1.5 hands it to systemd as TasksMax=1, so nothing can fork in them
        # ("bash: fork: Resource temporarily unavailable"). That runc is the one of
        # docker's containerd.io package, which podman falls back to without crun
        oci_runtime=$("${podman_cli[@]}" info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null)
        oci_runtime_version=$("${podman_cli[@]}" info --format '{{.Host.OCIRuntime.Version}}' 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
        if [ "$oci_runtime" = "runc" ] && [ -n "$oci_runtime_version" ] && ! version_gt "1.5.0" "$oci_runtime_version"
        then
            doctor_error "podman uses runc ${oci_runtime_version}: containers started with docker run cannot create any process"
            logerror "install crun, podman's usual runtime: once installed, podman picks it over runc"
            logerror "  sudo apt-get install -y crun        # or: sudo dnf install -y crun"
            logerror "  sudo systemctl stop podman.service  # restarted on the next connection, with crun"
        elif [ "$oci_runtime" = "runc" ]
        then
            doctor_warn "podman uses runc ${oci_runtime_version}, the playground is tested with crun"
        elif [ -n "$oci_runtime" ]
        then
            doctor_ok "podman runtime is ${oci_runtime} ${oci_runtime_version}"
        fi

        # -- rootless or rootful ---------------------------------------------
        rootless=$("${podman_cli[@]}" info --format '{{.Host.Security.Rootless}}' 2>/dev/null)
        if [ "$rootless" = "true" ]
        then
            doctor_warn "podman is running rootless, the playground is tested with rootful podman"
            logwarn "containers write generated certificates and secrets into bind mounts, and the host"
            logwarn "reads them back: rootless podman maps container UIDs to subuids, so those files can"
            logwarn "end up unreadable from the host, and privileged: true containers may not start."
            logwarn "👉 rootful setup: https://kafka-docker-playground.io/#/podman"
        elif [ "$rootless" = "false" ]
        then
            doctor_ok "podman is running rootful"
        fi

        # -- network backend -------------------------------------------------
        # compose services reach each other by name (broker, connect, ...): that
        # needs netavark + aardvark-dns, the legacy cni backend has no DNS by default
        network_backend=$("${podman_cli[@]}" info --format '{{.Host.NetworkBackend}}' 2>/dev/null)
        if [ "$network_backend" = "cni" ]
        then
            doctor_error "podman uses the cni network backend, containers will not resolve each other by name"
            logerror "install netavark and aardvark-dns, set this in /etc/containers/containers.conf and run 'podman system reset':"
            logerror "  [network]"
            logerror "  network_backend = \"netavark\""
        elif [ -n "$network_backend" ]
        then
            doctor_ok "podman network backend is ${network_backend}"
        fi

        # -- unqualified image names -----------------------------------------
        # every image: in the compose files is a short name (postgres:14,
        # osixia/openldap:1.3.0, ...). The playground pulls through the docker
        # compat API, which resolves short names to docker.io by itself
        # (compat_api_enforce_docker_hub in containers.conf, true by default),
        # so registries.conf only matters for native `podman pull` (verified on 4.9.3
        # and 6.1.3, library and non-library images)
        search_registries=$("${podman_cli[@]}" info --format '{{range .Registries.search}}{{.}} {{end}}' 2>/dev/null)
        if echo "$search_registries" | grep -q "docker.io"
        then
            doctor_ok "docker.io is in the podman search registries"
        else
            log "ℹ️  short image names resolve to docker.io through the docker compat API, nothing to configure"
        fi

        # -- macOS machine ----------------------------------------------------
        # the docker CLI sends bind mount sources verbatim, so the VM must expose
        # host paths at the same path. podman refuses /tmp as a mount destination
        # (the VM needs its own), but macOS /tmp is a symlink to /private/tmp and
        # the default machine shares /Users, /private and /var/folders
        if [[ "$OSTYPE" == "darwin"* ]]
        then
            # `podman machine inspect` does not list the mounts on every version,
            # so ask the VM which host folders it really has (virtiofs)
            machine_mounts=$(podman machine ssh -- findmnt -rn -t virtiofs -o TARGET 2>/dev/null | tr -d '\r')
            # /private matters for /tmp: bind mounts use PLAYGROUND_HOST_TMP_DIR=/private/tmp
            for shared in "$HOME" /private /var/folders
            do
                # a mount covers $shared if it is $shared or one of its parents
                covered=0
                for target in $machine_mounts
                do
                    case "$shared/" in
                        "${target%/}/"*) covered=1 ;;
                    esac
                done
                if [ "$covered" = "1" ]
                then
                    doctor_ok "the podman machine shares ${shared}"
                else
                    doctor_warn "the podman machine does not share ${shared}"
                    logwarn "bind mounts under ${shared} will silently mount an empty directory of the VM instead."
                    logwarn "recreate the machine without any -v flag, the defaults share /Users, /private and /var/folders"
                fi
            done
        fi
    fi

    # -- privileged ports ----------------------------------------------------
    # the ldap-* and kerberos environments publish 220, 389, 636 and 749
    if [[ "$OSTYPE" != "darwin"* ]] && [ "$rootless" = "true" ]
    then
        port_start=$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null)
        if [[ "$port_start" =~ ^[0-9]+$ ]] && [ "$port_start" -gt 220 ]
        then
            doctor_warn "net.ipv4.ip_unprivileged_port_start is ${port_start}"
            logwarn "the ldap-* and kerberos environments publish ports 220, 389, 636 and 749, which"
            logwarn "rootless podman cannot bind. Lower it with:"
            logwarn "  sudo sysctl net.ipv4.ip_unprivileged_port_start=0"
        else
            doctor_ok "privileged ports can be published"
        fi
    fi

    # -- SELinux --------------------------------------------------------------
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]
    then
        doctor_warn "SELinux is Enforcing"
        logwarn "the compose files of the playground do not label their bind mounts, which produces"
        logwarn "avc denials. Either run with 'setenforce 0' while using the playground, or add"
        logwarn "  --security-opt label=disable"
        logwarn "to the engine defaults in ~/.config/containers/containers.conf"
    fi
fi

######################################################################
# summary
######################################################################
echo ""
if [ "$nb_errors" -gt 0 ]
then
    logerror "🩺 ${nb_errors} problem(s) and ${nb_warnings} warning(s) found"
    exit 1
fi

if [ "$nb_warnings" -gt 0 ]
then
    logwarn "🩺 no blocking problem, but ${nb_warnings} warning(s) found"
    exit 0
fi

log "🩺 all good, the ${engine} engine is ready for the playground"
