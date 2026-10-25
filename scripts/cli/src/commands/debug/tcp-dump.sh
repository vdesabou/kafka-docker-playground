eval "containers=(${args[--container]})"
port="${args[--port]}"
filter="${args[--filter]}"
duration="${args[--duration]}"
snaplen="${args[--snaplen]}"
action="${args[--action]}"
output_dir="${args[--output-dir]}"
no_analyze="${args[--no-analyze]}"
no_open="${args[--no-open]}"

get_environment_used

#
# tcpdump runs from the netshoot image in the network namespace of each container (an ephemeral container of the pod
# with cfk): nothing is installed in the container, so it works with any image. The capture container stays up after
# tcpdump stops, so that the capture can be copied out (no bind mount: no root-owned files, no shared folder needed),
# then it is removed. playground analyze tcp-dump then analyzes each capture.
#
#   -U --immediate-mode   every packet is written as soon as it is captured: none is lost when the capture stops
#   timeout -s INT        tcpdump stops by itself after --duration and closes the file properly
#

capture_script='mkdir -p /captures
set -- -i any -U --immediate-mode -w "/captures/$TCPDUMP_FILE"
if [ -n "$TCPDUMP_SNAPLEN" ]; then set -- "$@" -s "$TCPDUMP_SNAPLEN"; fi
if [ -n "$TCPDUMP_FILTER" ]; then set -- "$@" "$TCPDUMP_FILTER"; fi
if [ -n "$TCPDUMP_TIMEOUT" ]
then
    timeout -s INT "$TCPDUMP_TIMEOUT" tcpdump "$@" 2> /captures/tcpdump.log
else
    tcpdump "$@" 2> /captures/tcpdump.log
fi
touch /captures/.done
exec sleep 3600'

if [[ -n "$port" ]] && [[ -n "$filter" ]]
then
    expression="port $port and ($filter)"
elif [[ -n "$port" ]]
then
    expression="port $port"
else
    expression="$filter"
fi

duration_seconds=$(duration_to_seconds "$duration")
if [[ -z "$action" ]] && [[ "$duration_seconds" -le 0 ]]
then
    logerror "❌ --duration must be greater than 0"
    exit 1
fi
if [[ -n "$snaplen" ]] && [[ "$snaplen" -le 0 ]]
then
    logerror "❌ --snaplen must be greater than 0"
    exit 1
fi

if [ "$action" == "start" ] || [ -z "$action" ]
then
    if [[ "$environment" != cfk* ]] && ! docker image inspect $PLAYGROUND_NETSHOOT_IMAGE > /dev/null 2>&1
    then
        log "📥 pulling $PLAYGROUND_NETSHOOT_IMAGE (network tools image, only the first time)"
        docker pull $PLAYGROUND_NETSHOOT_IMAGE > /dev/null
    fi
fi

#
# backend: a capture is identified by a handle, the name of the capture container (docker, podman) or <pod>/<ephemeral
# container> (cfk)
#
function capture_start () {
    local container=$1
    local file=$2
    local timeout_seconds=$3
    local handle
    local pod_name
    local target_container
    local debug_container
    local debug_custom_file

    if [[ "$environment" == cfk* ]]
    then
        pod_name=$(resolve_container_name_for_environment "$container")
        target_container=$(kubectl -n confluent get pod "$pod_name" -o jsonpath='{.spec.containers[0].name}' 2> /dev/null)
        if [[ -z "$target_container" ]]
        then
            logerror "❌ pod $pod_name not found" >&2
            return 1
        fi
        debug_container="pg-tcpdump-$(date +%s)"
        debug_custom_file=$(mktemp -t pg-cfk-netshoot-XXXXXXXXXX.yaml)
        printf 'securityContext:\n  runAsUser: 0\n  runAsNonRoot: false\n' > "$debug_custom_file"
        if ! kubectl -n confluent debug "pod/$pod_name" --attach=false --profile=sysadmin --custom="$debug_custom_file" \
            --image=$PLAYGROUND_NETSHOOT_IMAGE --target="$target_container" --container="$debug_container" \
            --env="TCPDUMP_FILE=$file" --env="TCPDUMP_FILTER=$expression" --env="TCPDUMP_SNAPLEN=$snaplen" --env="TCPDUMP_TIMEOUT=$timeout_seconds" \
            -- sh -c "$capture_script" > /dev/null
        then
            rm -f "$debug_custom_file"
            logerror "❌ could not start an ephemeral container in pod $pod_name" >&2
            return 1
        fi
        rm -f "$debug_custom_file"
        handle="$pod_name/$debug_container"
    else
        handle="pg-tcpdump-$container"
        if docker inspect "$handle" > /dev/null 2>&1
        then
            logerror "❌ a capture is already running on $container (container $handle): stop it with --action stop" >&2
            return 1
        fi
        if ! docker run -d --name "$handle" --network "container:$container" --cap-add NET_RAW --cap-add NET_ADMIN \
            -e "TCPDUMP_FILE=$file" -e "TCPDUMP_FILTER=$expression" -e "TCPDUMP_SNAPLEN=$snaplen" -e "TCPDUMP_TIMEOUT=$timeout_seconds" \
            $PLAYGROUND_NETSHOOT_IMAGE sh -c "$capture_script" > /dev/null
        then
            logerror "❌ could not start the capture container in the network namespace of $container" >&2
            return 1
        fi
    fi
    echo "$handle"
}

function capture_exec () {
    local handle=$1
    shift
    if [[ "$environment" == cfk* ]]
    then
        kubectl -n confluent exec -i "${handle%%/*}" -c "${handle#*/}" -- "$@"
    else
        docker exec -i "$handle" "$@"
    fi
}

function capture_copy_in () {
    local handle=$1
    local source=$2
    local destination=$3
    capture_exec "$handle" sh -c "cat > '$destination'" < "$source"
}

function capture_copy_out () {
    local handle=$1
    local source=$2
    local destination=$3
    capture_exec "$handle" cat "$source" > "$destination"
}

function capture_remove () {
    local handle=$1
    if [[ "$environment" == cfk* ]]
    then
        # an ephemeral container can't be removed from its pod: ending its last process stops it
        capture_exec "$handle" pkill sleep > /dev/null 2>&1
    else
        docker rm -f "$handle" > /dev/null 2>&1
    fi
}

function capture_is_running () {
    capture_exec "$1" sh -c "pgrep tcpdump > /dev/null" > /dev/null 2>&1
}

# waits until tcpdump listens (or fails): a bad --filter or interface stops it at once
function capture_wait_listening () {
    local handle=$1
    local container=$2
    local log
    for _ in $(seq 1 20)
    do
        log=$(capture_exec "$handle" cat /captures/tcpdump.log 2> /dev/null)
        if [[ "$log" == *"listening on"* ]]
        then
            return 0
        fi
        if capture_exec "$handle" test -f /captures/.done > /dev/null 2>&1
        then
            break
        fi
        sleep 1
    done
    logerror "❌ tcpdump did not start on $container${expression:+ with filter '$expression'}"
    # the warning about the promiscuous mode of the any device is printed every time
    echo "$log" | grep -v -i "promiscuous"
    return 1
}

# ip address → name of every container (or pod and service), for tshark and Wireshark name resolution
function write_hosts_file () {
    local destination=$1
    local name
    local ip
    if [[ "$environment" == cfk* ]]
    then
        {
            kubectl -n confluent get pods -o jsonpath='{range .items[*]}{.status.podIP}{"\t"}{.metadata.name}{"\n"}{end}' 2> /dev/null
            kubectl -n confluent get svc -o jsonpath='{range .items[*]}{.spec.clusterIP}{"\t"}{.metadata.name}{"\n"}{end}' 2> /dev/null
        } | awk -F '\t' '$1 != "" && $1 != "None" && !seen[$1]++' > "$destination"
    else
        : > "$destination"
        for name in $(docker ps --format '{{.Names}}' | grep -v '^pg-tcpdump-')
        do
            for ip in $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$name" 2> /dev/null)
            do
                printf '%s\t%s\n' "$ip" "$name" >> "$destination"
            done
        done
    fi
}

# stops the capture (if still running), writes the pcap and the hosts file in --output-dir, then analyzes the capture
function capture_collect () {
    local container=$1
    local handle=$2
    local file=$3
    local local_file="$output_dir/$file"
    local hosts_file="${local_file%.pcap}.hosts"
    local stats

    capture_exec "$handle" pkill -INT tcpdump > /dev/null 2>&1
    for _ in $(seq 1 30)
    do
        if capture_exec "$handle" test -f /captures/.done > /dev/null 2>&1
        then
            break
        fi
        sleep 1
    done

    if ! capture_copy_out "$handle" "/captures/$file" "$local_file" || [ ! -s "$local_file" ]
    then
        logerror "❌ the capture of $container could not be copied"
        capture_exec "$handle" cat /captures/tcpdump.log 2> /dev/null
        capture_remove "$handle"
        return 1
    fi

    # tcpdump prints "N packets captured", "M packets dropped by kernel" when it stops
    stats=$(capture_exec "$handle" cat /captures/tcpdump.log 2> /dev/null | grep -E "packets (captured|dropped by kernel)" | tr '\n' ',' | sed 's/,$//; s/,/, /g')
    log "🌶️ capture of $container: $local_file${stats:+ ($stats)}"
    if [[ "$stats" =~ ([1-9][0-9]*)\ packets\ dropped\ by\ kernel ]]
    then
        logwarn "⚠️ the kernel dropped packets: narrow the capture with --port / --filter, or reduce --snaplen"
    fi

    write_hosts_file "$hosts_file"
    capture_remove "$handle"
    collected_files+=("$local_file")
}

# playground analyze tcp-dump: text digest, findings and HTML report next to each capture
function analyze_captures () {
    local file
    if [[ -n "$no_analyze" ]]
    then
        for file in "${collected_files[@]}"
        do
            log "🔎 analyze it with: playground analyze tcp-dump -f $file"
        done
        return
    fi
    for file in "${collected_files[@]}"
    do
        log "🔎 analyzing $file (--no-analyze to skip it)"
        playground analyze tcp-dump -f "$file" --output-dir "$output_dir"
        # 2: the capture has no packet, already explained by the analysis
        case $? in
            0|2) ;;
            *) logwarn "⚠️ the capture could not be analyzed, open it with Wireshark" ;;
        esac
    done
}

function capture_file_name () {
    echo "tcp-dump-${1}-${port:-all-ports}-$(date '+%Y-%m-%d-%H-%M-%S').pcap"
}

# opens the captures in Wireshark, in the background, when it runs in a terminal
function open_in_wireshark () {
    local file
    if [[ ${#collected_files[@]} -eq 0 ]] || [[ -n "$no_open" ]] || [ -n "$GITHUB_RUN_NUMBER" ] || [ ! -t 1 ]
    then
        return
    fi
    log "🏷️ each .hosts file maps the ip addresses to container names: to see the names in Wireshark, copy it as 'hosts' into the Wireshark personal configuration folder (Help → About Wireshark → Folders) and enable View → Name Resolution → Resolve Network Addresses"
    if [[ "$(uname)" == "Darwin" ]] && [ -d "/Applications/Wireshark.app" ]
    then
        for file in "${collected_files[@]}"
        do
            log "🦈 opening $file with Wireshark (--no-open to skip it)"
            open -a Wireshark "$file"
        done
    elif command -v wireshark > /dev/null 2>&1
    then
        for file in "${collected_files[@]}"
        do
            log "🦈 opening $file with Wireshark (--no-open to skip it)"
            nohup wireshark "$file" > /dev/null 2>&1 &
        done
    else
        log "🦈 open the captures with Wireshark: https://www.wireshark.org/"
    fi
}

# true when the container was (re)started after the capture began: the capture stays in the network namespace of the
# previous run of the container and sees nothing new (with cfk, a pod restart removes the ephemeral container)
function target_restarted_since () {
    local container=$1
    local since=$2
    local started_at
    local started_epoch
    if [[ "$environment" == cfk* ]]
    then
        return 1
    fi
    started_at=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2> /dev/null)
    started_at=${started_at%%.*}
    started_at=${started_at%Z}
    started_epoch=$(date -u -d "$started_at" +%s 2> /dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S" "$started_at" +%s 2> /dev/null)
    [[ -n "$started_epoch" ]] && [[ "$started_epoch" -gt "$since" ]]
}

function format_epoch () {
    date -r "$1" "$2" 2> /dev/null || date -d "@$1" "$2" 2> /dev/null || echo "$1"
}

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
collected_files=()
failed=0

case "$action" in
    "")
        # 1. every capture starts at the same time, so that both sides of a connection can be compared
        handles=()
        files=()
        started=()
        for container in "${containers[@]}"
        do
            file=$(capture_file_name "$container")
            if ! handle=$(capture_start "$container" "$file" "$duration_seconds")
            then
                failed=1
                continue
            fi
            if ! capture_wait_listening "$handle" "$container"
            then
                capture_remove "$handle"
                failed=1
                continue
            fi
            handles+=("$handle")
            files+=("$file")
            started+=("$container")
        done
        if [[ ${#started[@]} -eq 0 ]]
        then
            exit 1
        fi

        log "🕵️‍♂️ capturing the traffic of ${started[*]}${expression:+ ($expression)} for ${duration_seconds} seconds, reproduce the issue now (Ctrl+C stops it earlier and keeps the capture)"

        # 2. wait, Ctrl+C included
        interrupted=""
        trap 'interrupted=1' INT
        end=$((SECONDS + duration_seconds))
        while [ $SECONDS -lt $end ] && [ -z "$interrupted" ]
        do
            sleep 1
        done
        trap - INT
        if [ -n "$interrupted" ]
        then
            log "✋ stopped after $((duration_seconds - (end - SECONDS))) seconds"
        fi

        # 3. stop, copy, summarize
        for i in "${!handles[@]}"
        do
            capture_collect "${started[$i]}" "${handles[$i]}" "${files[$i]}" || failed=1
        done
        analyze_captures
        open_in_wireshark
        ;;
    start)
        for container in "${containers[@]}"
        do
            state=$(playground state get "tcp_dump.$container" 2> /dev/null)
            if [[ -n "$state" ]]
            then
                read -r handle file started_at <<< "$state"
                logwarn "🕵️‍♂️ a capture is already running on $container (since $(format_epoch "$started_at" '+%H:%M:%S')): stop it with --action stop"
                continue
            fi
            file=$(capture_file_name "$container")
            if ! handle=$(capture_start "$container" "$file" "")
            then
                failed=1
                continue
            fi
            if ! capture_wait_listening "$handle" "$container"
            then
                capture_remove "$handle"
                failed=1
                continue
            fi
            playground state set "tcp_dump.$container" "$handle $file $(date +%s)"
            log "🕵️‍♂️ capturing the traffic of $container${expression:+ ($expression)}: stop it with playground debug tcp-dump -c $container --action stop"
        done
        ;;
    stop)
        for container in "${containers[@]}"
        do
            state=$(playground state get "tcp_dump.$container" 2> /dev/null)
            if [[ -z "$state" ]]
            then
                logwarn "🤷 no capture started on $container with --action start"
                continue
            fi
            read -r handle file started_at <<< "$state"
            playground state del "tcp_dump.$container" > /dev/null 2>&1
            log "✋ stopping the capture of $container, started at $(format_epoch "$started_at" '+%H:%M:%S')"
            if target_restarted_since "$container" "$started_at"
            then
                logwarn "⚠️ $container was restarted after the capture started: it only has the traffic before the restart"
            fi
            capture_collect "$container" "$handle" "$file" || failed=1
        done
        analyze_captures
        open_in_wireshark
        ;;
    status)
        for container in "${containers[@]}"
        do
            state=$(playground state get "tcp_dump.$container" 2> /dev/null)
            if [[ -z "$state" ]]
            then
                log "💤 no capture running on $container"
                continue
            fi
            read -r handle file started_at <<< "$state"
            if target_restarted_since "$container" "$started_at"
            then
                logwarn "⚠️ $container was restarted after the capture started at $(format_epoch "$started_at" '+%H:%M:%S'): the capture only has the traffic before the restart, --action stop collects it, then start a new one"
            elif capture_is_running "$handle"
            then
                log "🕵️‍♂️ capturing the traffic of $container since $(format_epoch "$started_at" '+%H:%M:%S') ($file)"
            else
                logwarn "⚠️ the capture of $container started at $(format_epoch "$started_at" '+%H:%M:%S') is no longer running (container restarted?): --action stop collects what was captured"
            fi
        done
        ;;
esac

if [ $failed -eq 1 ]
then
    exit 1
fi
