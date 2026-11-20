eval "containers=(${args[--container]})"
host="${args[--host]}"
nxdomain="${args[--nxdomain]}"
servfail="${args[--servfail]}"
resolve_to="${args[--resolve-to]}"
delay="${args[--delay]}"
reset="${args[--reset]}"

get_environment_used
if [[ "$environment" == cfk* ]]
then
    logerror "❌ playground debug dns is not supported with cfk yet"
    exit 1
fi

# the proxy listens on this address of the loopback of the container (the sidecar shares its network namespace)
proxy_address="127.0.0.53"
proxy_script="$root_folder/tools/debug-dns/dns_proxy.py"
# copy of the original /etc/resolv.conf, in the container: it survives a restart of the container, like the edited file
backup_file="/tmp/playground-debug-dns-resolv.conf"

# ---- the fault requested -----------------------------------------------------------------------------------------
mode=""
value=""
description=""
if [[ -n "$nxdomain" ]]
then
    mode="nxdomain"
    description="does not exist (NXDOMAIN)"
elif [[ -n "$servfail" ]]
then
    mode="servfail"
    description="fails to resolve (SERVFAIL)"
elif [[ -n "$resolve_to" ]]
then
    if [[ ! "$resolve_to" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
    then
        logerror "❌ --resolve-to $resolve_to is not an ipv4 address"
        exit 1
    fi
    mode="resolve-to"
    value="$resolve_to"
    description="resolves to $resolve_to"
elif [[ -n "$delay" ]]
then
    if [[ ! "$delay" =~ ^[0-9]+(\.[0-9]+)?(ms|s)?$ ]]
    then
        logerror "❌ --delay $delay is not valid: seconds, or a number with a unit ms or s, e.g. 500ms, 3s"
        exit 1
    fi
    mode="delay"
    if [[ "$delay" == *ms ]]
    then
        value=$(awk -v d="${delay%ms}" 'BEGIN { printf "%g", d / 1000 }')
    else
        value="${delay%s}"
    fi
    description="answers after $delay"
fi

if [[ -n "$mode" && -z "$host" ]]
then
    logerror "❌ --host is required with --nxdomain, --servfail, --resolve-to and --delay"
    exit 1
fi
if [[ -n "$host" ]]
then
    host=$(echo "$host" | tr '[:upper:]' '[:lower:]')
    host="${host%.}"
    if [[ ! "$host" =~ ^[a-z0-9_]([a-z0-9_.-]*[a-z0-9_])?$ ]]
    then
        logerror "❌ --host $host is not a hostname"
        exit 1
    fi
fi

# ---- helpers -----------------------------------------------------------------------------------------------------
function sidecar_name () {
    echo "playground-debug-dns-$1"
}

# the sidecar runs, in the network namespace of the current run of the container: a restart of the container gives
# it a new namespace, the sidecar keeps the old one and answers nobody
function sidecar_alive () {
    local c="$1" sidecar started label
    sidecar=$(sidecar_name "$c")
    [[ "$(docker inspect -f '{{.State.Running}}' "$sidecar" 2> /dev/null)" == "true" ]] || return 1
    started=$(docker inspect -f '{{.State.StartedAt}}' "$c" 2> /dev/null)
    label=$(docker inspect -f '{{index .Config.Labels "playground.debug-dns.started-at"}}' "$sidecar" 2> /dev/null)
    [[ "$started" == "$label" ]]
}

# /etc/resolv.conf of the container points to the proxy
function resolv_conf_redirected () {
    docker exec "$1" cat /etc/resolv.conf 2> /dev/null | grep -q "^nameserver $proxy_address"
}

function current_rules () {
    docker exec "$(sidecar_name "$1")" cat /rules 2> /dev/null
}

function write_rules () {
    # a new file, then mv: the proxy sees a new mtime, and never reads a half written file
    docker exec -i "$(sidecar_name "$1")" sh -c 'cat > /rules.tmp && mv /rules.tmp /rules'
}

# how the host resolves now, from the container (getent: the resolver of the libc, like a JVM), and how long it took
function show_resolution () {
    local c="$1" start end output ms
    [[ -z "$host" ]] && return
    start=$EPOCHREALTIME
    output=$(docker exec "$c" timeout 25 getent ahostsv4 "$host" 2> /dev/null | awk '{ print $1 }' | sort -u | paste -sd ' ' -)
    end=$EPOCHREALTIME
    ms=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%d", (e - s) * 1000 }')
    if [[ -n "$output" ]]
    then
        log "🔎 from $c, $host resolves to $output (in $ms ms)"
    else
        log "🔎 from $c, $host does not resolve (after $ms ms)"
    fi
}

function setup_proxy () {
    local c="$1" sidecar started original upstream image
    sidecar=$(sidecar_name "$c")
    docker rm -f "$sidecar" > /dev/null 2>&1 || true

    if docker exec "$c" test -f "$backup_file" 2> /dev/null
    then
        # a previous setup (the container was restarted since): the original file is the backup
        original=$(docker exec "$c" cat "$backup_file")
    else
        original=$(docker exec "$c" cat /etc/resolv.conf)
        if ! printf '%s\n' "$original" | docker exec -i -u 0 "$c" sh -c "cat > $backup_file"
        then
            logerror "❌ could not save /etc/resolv.conf of $c"
            exit 1
        fi
    fi
    upstream=$(printf '%s\n' "$original" | awk -v p="$proxy_address" '$1 == "nameserver" && $2 != p { print $2 }' | paste -sd ',' -)
    if [[ -z "$upstream" ]]
    then
        logerror "❌ no nameserver in /etc/resolv.conf of $c"
        exit 1
    fi

    image="$PLAYGROUND_DNS_PROXY_IMAGE"
    if ! docker image inspect "$image" > /dev/null 2>&1
    then
        log "📥 pulling $image (DNS proxy image, only the first time)"
        docker pull "$image" > /dev/null
    fi
    started=$(docker inspect -f '{{.State.StartedAt}}' "$c")
    if ! docker create --name "$sidecar" --network "container:$c" \
        --label "playground.debug-dns.container=$c" \
        --label "playground.debug-dns.started-at=$started" \
        -e "UPSTREAM=$upstream" -e "LISTEN=$proxy_address" -e "RULES_FILE=/rules" \
        "$image" python3 -u /dns_proxy.py > /dev/null
    then
        logerror "❌ could not create the DNS proxy container $sidecar"
        exit 1
    fi
    docker cp "$proxy_script" "$sidecar:/dns_proxy.py" > /dev/null
    docker start "$sidecar" > /dev/null
    for _ in $(seq 1 20)
    do
        docker logs "$sidecar" 2>&1 | grep -q "listening on" && break
        sleep 0.5
    done
    if ! docker logs "$sidecar" 2>&1 | grep -q "listening on"
    then
        logerror "❌ the DNS proxy did not start in $sidecar"
        docker logs "$sidecar" 2>&1 | tail -20
        docker rm -f "$sidecar" > /dev/null 2>&1 || true
        exit 1
    fi

    # written in place (a bind mount: mv would fail), the search and options lines kept
    if ! { echo "# playground debug dns: the original file is $backup_file"; echo "nameserver $proxy_address"; printf '%s\n' "$original" | grep -E '^(search|domain|options)'; } | docker exec -i -u 0 "$c" sh -c 'cat > /etc/resolv.conf'
    then
        logerror "❌ could not point /etc/resolv.conf of $c to the DNS proxy"
        docker rm -f "$sidecar" > /dev/null 2>&1 || true
        exit 1
    fi
}

function reset_container () {
    local c="$1"
    if docker exec "$c" test -f "$backup_file" 2> /dev/null
    then
        docker exec "$c" cat "$backup_file" | docker exec -i -u 0 "$c" sh -c 'cat > /etc/resolv.conf'
        docker exec -u 0 "$c" rm -f "$backup_file"
    fi
    docker rm -f "$(sidecar_name "$c")" > /dev/null 2>&1 || true
    log "🟢 $c uses the real DNS again"
}

function show_status () {
    local c="$1" rules intercepted
    if ! resolv_conf_redirected "$c"
    then
        if docker inspect "$(sidecar_name "$c")" > /dev/null 2>&1
        then
            # the container was restarted: docker wrote its original resolv.conf again, the proxy is a leftover
            docker rm -f "$(sidecar_name "$c")" > /dev/null 2>&1 || true
            docker exec -u 0 "$c" rm -f "$backup_file" 2> /dev/null || true
            log "🧹 $c was restarted since the faults were set (they are gone): DNS proxy removed"
        fi
        log "✅ no DNS fault on $c"
        show_resolution "$c"
        return
    fi
    if ! sidecar_alive "$c"
    then
        logerror "❌ /etc/resolv.conf of $c points to the DNS proxy, but the proxy is not running ($c was restarted?): no name resolves from $c"
        logerror "   🎓 set it up again with the same command plus a fault, or: playground debug dns --container $c --reset"
        return
    fi
    rules=$(current_rules "$c")
    if [[ -z "$rules" ]]
    then
        log "✅ no DNS fault on $c (the proxy forwards every query)"
    else
        log "🔤 DNS faults on $c:"
        echo "$rules" | awk '{
            if ($2 == "nxdomain") d = "does not exist (NXDOMAIN)"
            else if ($2 == "servfail") d = "fails to resolve (SERVFAIL)"
            else if ($2 == "resolve-to") d = "resolves to " $3
            else if ($2 == "delay") d = "answers after " $3 "s"
            else d = $2
            printf "   %s %s\n", $1, d }'
        intercepted=$(docker logs "$(sidecar_name "$c")" 2>&1 | grep -c " (type " || true)
        log "📊 $intercepted queries answered with a fault so far (docker logs $(sidecar_name "$c"))"
    fi
    show_resolution "$c"
}

for c in "${containers[@]}"
do
    if ! docker ps --format '{{.Names}}' | grep -qx "$c"
    then
        logerror "❌ container $c is not running"
        exit 1
    fi
done

# ---- status ------------------------------------------------------------------------------------------------------
if [[ -z "$mode" && -z "$reset" ]]
then
    for c in "${containers[@]}"
    do
        show_status "$c"
    done
    exit 0
fi

# ---- reset -------------------------------------------------------------------------------------------------------
if [[ -n "$reset" ]]
then
    for c in "${containers[@]}"
    do
        if [[ -n "$host" ]] && sidecar_alive "$c"
        then
            rules=$(current_rules "$c" | awk -v h="$host" '$1 != h')
            if [[ -n "$rules" ]]
            then
                echo "$rules" | write_rules "$c"
                log "🟢 $host resolves normally again from $c (other faults kept)"
                show_status "$c"
                continue
            fi
        fi
        reset_container "$c"
        show_resolution "$c"
    done
    exit 0
fi

# ---- apply -------------------------------------------------------------------------------------------------------
for c in "${containers[@]}"
do
    if ! sidecar_alive "$c" || ! resolv_conf_redirected "$c"
    then
        log "🚀 starting the DNS proxy of $c ($(sidecar_name "$c"))"
        setup_proxy "$c"
        rules=""
    else
        rules=$(current_rules "$c")
    fi
    {
        echo "$rules" | awk -v h="$host" 'NF > 0 && $1 != h'
        echo "$host $mode $value"
    } | write_rules "$c"
    log "🔤 from $c, $host $description"
    show_resolution "$c"
done

case "$mode" in
    delay)
        # glibc sends the query again after 5s, and still accepts a late answer to the first one: a lookup only
        # fails when no answer comes in timeout x attempts
        if awk -v v="$value" 'BEGIN { exit !(v >= 10) }'
        then
            logwarn "⏱️ a delay of 10s or more is longer than the glibc resolver waits (options timeout:5 attempts:2): every lookup fails after 10s (UnknownHostException), before the answer comes"
        elif awk -v v="$value" 'BEGIN { exit !(v >= 5) }'
        then
            logwarn "⏱️ glibc sends the query again after 5s (options timeout:5 attempts:2) and still takes the late answer: the lookups succeed, in $delay"
        fi
        ;;
    resolve-to)
        logwarn "🔁 a Kafka client resolves $host when it opens a connection: an established connection keeps the old ip (to force a reconnection: playground debug block-traffic --destination $host --action start, then stop)"
        ;;
esac
logwarn "🗃️ a JVM caches its lookups: networkaddress.cache.ttl (30s by default) for a success, networkaddress.cache.negative.ttl (10s) for a failure"
log "🧽 back to the real DNS: playground debug dns $(printf -- '--container %s ' "${containers[@]}")--reset"
