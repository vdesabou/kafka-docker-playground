eval "containers=(${args[--container]})"
cpus="${args[--cpus]}"
memory="${args[--memory]}"
fill_disk="${args[--fill-disk]}"
path="${args[--path]}"
reset="${args[--reset]}"

get_environment_used
if [[ "$environment" == cfk* ]]
then
    logerror "❌ playground debug resources is not supported with cfk yet"
    exit 1
fi

# the limits of each container before the first change, and the fill file: one file per container, on the host (a
# full disk in the container could not store it)
state_dir="/tmp/playground-debug-resources"
fill_name=".playground-fill-disk"

if [[ -n "$cpus" ]] && [[ ! "$cpus" =~ ^[0-9]+(\.[0-9]+)?$ ]]
then
    logerror "❌ --cpus $cpus is not valid, example: --cpus 0.5"
    exit 1
fi
if [[ -n "$memory" ]]
then
    if [[ ! "$memory" =~ ^[0-9]+[bkmgBKMG]?$ ]]
    then
        logerror "❌ --memory $memory is not valid, example: --memory 512m, --memory 1g"
        exit 1
    fi
    memory_bytes=$(awk -v m="$memory" 'BEGIN {
        u = tolower(substr(m, length(m))); n = m
        if (u ~ /[bkmg]/) { n = substr(m, 1, length(m) - 1) } else { u = "b" }
        f = (u == "k") ? 1024 : (u == "m") ? 1048576 : (u == "g") ? 1073741824 : 1
        printf "%.0f", n * f }')
    # the minimum of docker
    if [ "$memory_bytes" -lt 6291456 ]
    then
        logerror "❌ --memory $memory is below the minimum of docker (6m)"
        exit 1
    fi
fi
if [[ -n "$fill_disk" ]]
then
    fill_disk="${fill_disk%\%}"
    if [[ ! "$fill_disk" =~ ^[0-9]+$ ]] || [ "$fill_disk" -lt 1 ] || [ "$fill_disk" -gt 100 ]
    then
        logerror "❌ --fill-disk ${args[--fill-disk]} is not valid: a percentage from 1% to 100%, e.g. 95%"
        exit 1
    fi
fi
if [[ -n "$path" && -z "$fill_disk" && -n "$reset" ]]
then
    logwarn "🤷 --path is not used with --reset: the fill file recorded is removed"
fi

# ---- helpers -----------------------------------------------------------------------------------------------------
function human_bytes () {
    awk -v b="$1" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " "); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d%s" : "%.1f%s"), b, u[i] }'
}

# the cpus and memory of the docker VM (the host on linux), seen from the container: /proc is not virtualised
# (recorded in the state at the first change: a container restarting after an OOM kill cannot run docker exec)
function host_cpus () {
    local v
    v=$(state_get "$1" vm_cpus)
    [[ -n "$v" ]] && { echo "$v"; return; }
    docker exec "$1" sh -c 'grep -c ^processor /proc/cpuinfo' 2> /dev/null
}
function host_memory_bytes () {
    local v
    v=$(state_get "$1" vm_memory)
    [[ -n "$v" ]] && { echo "$v"; return; }
    # parsed on the host: there is no awk in some images (cp-server)
    docker exec "$1" cat /proc/meminfo 2> /dev/null | awk '/^MemTotal:/ { printf "%.0f", $2 * 1024 }'
}

function container_running () {
    [[ "$(docker inspect -f '{{.State.Status}}' "$1" 2> /dev/null)" == "running" ]]
}

function state_get () {
    local c="$1" key="$2"
    [[ -f "$state_dir/$c" ]] || return 0
    awk -F '=' -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$state_dir/$c"
}
function state_set () {
    local c="$1" key="$2" value="$3" file="$state_dir/$1"
    mkdir -p "$state_dir"
    touch "$file"
    { grep -v "^$key=" "$file" || true; echo "$key=$value"; } > "$file.tmp"
    mv "$file.tmp" "$file"
}

# the state is for this container, not a previous one with the same name (a recreate drops the limits)
function check_state_container () {
    local c="$1" id
    id=$(docker inspect -f '{{.Id}}' "$c")
    if [[ -f "$state_dir/$c" && "$(state_get "$c" id)" != "$id" ]]
    then
        rm -f "$state_dir/$c"
    fi
    if [[ ! -f "$state_dir/$c" ]]
    then
        state_set "$c" id "$id"
        state_set "$c" vm_cpus "$(host_cpus "$c")"
        state_set "$c" vm_memory "$(host_memory_bytes "$c")"
        state_set "$c" original "$(docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.MemorySwap}} {{.HostConfig.NanoCpus}} {{.HostConfig.CpuQuota}} {{.HostConfig.CpuPeriod}}' "$c")"
    fi
}

# folder filled by default: the first log dir of a broker or a controller, /tmp otherwise
function default_path () {
    local c="$1" dirs
    if [[ "$c" == broker* || "$c" == controller* ]]
    then
        dirs=$(docker exec "$c" sh -c 'grep -E "^log\.dirs=" /etc/kafka/kafka.properties 2> /dev/null' | head -1 | cut -d '=' -f 2 | cut -d ',' -f 1)
        echo "${dirs:-/var/lib/kafka/data}"
    else
        echo "/tmp"
    fi
}

# size, used and available kilobytes of the filesystem of a folder of the container
function disk_usage () {
    docker exec "$1" df -Pk "$2" 2> /dev/null | awk 'NR == 2 { print $2, $3, $4 }'
}

function java_max_heap () {
    docker exec "$1" sh -c 'for p in /proc/[0-9]*; do tr "\0" "\n" < $p/cmdline 2> /dev/null | grep -m1 "^-Xmx"; done' 2> /dev/null | tail -1 | sed 's/^-Xmx//'
}

function show_status () {
    local c="$1" memory_limit nano quota period vm_memory vm_cpus cpu_text memory_text stats oom restarts created heap disk_path size used avail fill_file fill_size pct state exit_code
    read -r memory_limit nano quota period <<< "$(docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}} {{.HostConfig.CpuQuota}} {{.HostConfig.CpuPeriod}}' "$c")"
    vm_memory=$(host_memory_bytes "$c")
    vm_cpus=$(host_cpus "$c")
    if [ "$memory_limit" -eq 0 ] || [ "$memory_limit" -ge "${vm_memory:-0}" ]
    then
        memory_text="no limit ($(human_bytes "$vm_memory") on the docker host)"
    else
        memory_text="$(human_bytes "$memory_limit")"
    fi
    if [ "$nano" -gt 0 ]
    then
        cpu_text=$(awk -v n="$nano" 'BEGIN { printf "%g", n / 1e9 }')
    elif [ "$quota" -gt 0 ]
    then
        cpu_text=$(awk -v q="$quota" -v p="${period:-100000}" 'BEGIN { if (p == 0) p = 100000; printf "%g", q / p }')
    fi
    if [[ -z "$cpu_text" ]] || awk -v c="$cpu_text" -v v="$vm_cpus" 'BEGIN { exit !(c >= v) }'
    then
        cpu_text="no limit ($vm_cpus on the docker host)"
    fi
    log "🏋️ $c: cpus $cpu_text, memory $memory_text"
    read -r state exit_code <<< "$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}}' "$c")"
    if [[ "$state" != "running" ]]
    then
        logwarn "🔁 $c is $state (exit code $exit_code)"
    fi
    stats=$(docker stats --no-stream --format '{{.CPUPerc}} cpu, {{.MemUsage}} memory ({{.MemPerc}})' "$c" 2> /dev/null)
    [[ -n "$stats" ]] && log "📊 usage now: $stats"
    container_running "$c" && heap=$(java_max_heap "$c")
    [[ -n "$heap" ]] && log "☕ JVM max heap (-Xmx): $heap"
    # the OOMKilled flag is cleared when the restart policy starts the container again: the oom events of docker stay
    read -r created restarts <<< "$(docker inspect -f '{{.Created}} {{.RestartCount}}' "$c")"
    oom=$(docker events --since "$created" --until "$(date +%s)" --filter "container=$c" --filter event=oom --format '{{.Action}}' 2> /dev/null | grep -c oom || true)
    if [ "${oom:-0}" -gt 0 ]
    then
        logwarn "💀 $c: $oom OOM kill(s) since it was created (the kernel killed a process above the memory limit), $restarts restart(s)"
    fi
    container_running "$c" || return 0
    fill_file=$(state_get "$c" fill_file)
    disk_path="${path:-$(dirname "${fill_file:-$(default_path "$c")/x}")}"
    read -r size used avail <<< "$(disk_usage "$c" "$disk_path")"
    if [[ -n "$size" ]]
    then
        pct=$(awk -v u="$used" -v a="$avail" 'BEGIN { if (u + a > 0) printf "%d", u * 100 / (u + a) + 0.5; else print 0 }')
        log "💾 disk of $disk_path: $pct% used, $(human_bytes $((used * 1024))) of $(human_bytes $(((used + avail) * 1024))), $(human_bytes $((avail * 1024))) free"
    fi
    if [[ -n "$fill_file" ]] && docker exec "$c" test -f "$fill_file" 2> /dev/null
    then
        fill_size=$(docker exec "$c" sh -c "du -k '$fill_file' | cut -f 1")
        log "🧱 fill file: $fill_file ($(human_bytes $((fill_size * 1024))))"
    fi
}

function remove_fill_file () {
    local c="$1" fill_file
    fill_file=$(state_get "$c" fill_file)
    if [[ -n "$fill_file" ]]
    then
        if container_running "$c"
        then
            docker exec -u 0 "$c" rm -f "$fill_file" 2> /dev/null || true
        fi
        state_set "$c" fill_file ""
        log "🧹 $fill_file removed from $c"
    fi
}

for c in "${containers[@]}"
do
    # restarting: the restart policy starts it again after an OOM kill, its limits can still be read and changed
    status=$(docker inspect -f '{{.State.Status}}' "$c" 2> /dev/null)
    if [[ "$status" != "running" && "$status" != "restarting" ]]
    then
        logerror "❌ container $c is not running${status:+ ($status)}"
        exit 1
    fi
done

# ---- status ------------------------------------------------------------------------------------------------------
if [[ -z "$cpus" && -z "$memory" && -z "$fill_disk" && -z "$reset" ]]
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
        id=$(docker inspect -f '{{.Id}}' "$c")
        if [[ ! -f "$state_dir/$c" || "$(state_get "$c" id)" != "$id" ]]
        then
            rm -f "$state_dir/$c"
            log "💫 nothing changed on $c by playground debug resources"
            continue
        fi
        remove_fill_file "$c"
        read -r o_memory o_swap o_nano o_quota o_period <<< "$(state_get "$c" original)"
        # docker update cannot remove a limit (0 means unchanged): no limit is the memory, or the cpus, of the host
        if [ "${o_memory:-0}" -gt 0 ]
        then
            memory_args=(--memory "$o_memory" --memory-swap "$o_swap")
            [ "${o_swap:-0}" -eq 0 ] && memory_args=(--memory "$o_memory" --memory-swap "$((o_memory * 2))")
        else
            vm_memory=$(host_memory_bytes "$c")
            memory_args=(--memory "$vm_memory" --memory-swap "$((vm_memory * 2))")
        fi
        if [ "${o_nano:-0}" -gt 0 ]
        then
            cpu_args=(--cpus "$(awk -v n="$o_nano" 'BEGIN { printf "%g", n / 1e9 }')")
        elif [ "${o_quota:-0}" -gt 0 ]
        then
            cpu_args=(--cpu-quota "$o_quota" --cpu-period "$o_period")
        else
            cpu_args=(--cpus "$(host_cpus "$c")")
        fi
        if ! docker update "${memory_args[@]}" "${cpu_args[@]}" "$c" > /dev/null
        then
            logerror "❌ could not restore the limits of $c"
            exit 1
        fi
        rm -f "$state_dir/$c"
        log "🟢 $c is back to its original limits"
        show_status "$c"
    done
    exit 0
fi

# ---- apply -------------------------------------------------------------------------------------------------------
for c in "${containers[@]}"
do
    check_state_container "$c"
    update_args=()
    if [[ -n "$cpus" ]]
    then
        vm_cpus=$(host_cpus "$c")
        if awk -v c="$cpus" -v v="$vm_cpus" 'BEGIN { exit !(c < 0.01 || c > v) }'
        then
            logerror "❌ --cpus $cpus: from 0.01 to $vm_cpus (the cpus of the docker host)"
            exit 1
        fi
        update_args+=(--cpus "$cpus")
    fi
    if [[ -n "$memory" ]]
    then
        # no swap: above the limit, the kernel kills the process instead of swapping
        update_args+=(--memory "$memory_bytes" --memory-swap "$memory_bytes")
    fi
    if [[ ${#update_args[@]} -gt 0 ]]
    then
        log "🏋️ limiting $c:${cpus:+ $cpus cpus}${cpus:+${memory:+,}}${memory:+ $memory memory (no swap)}"
        if ! docker update "${update_args[@]}" "$c" > /dev/null
        then
            logerror "❌ docker update failed on $c"
            exit 1
        fi
        if [[ -n "$memory" ]]
        then
            heap=$(java_max_heap "$c")
            if [[ -n "$heap" ]]
            then
                heap_bytes=$(awk -v m="$heap" 'BEGIN {
                    u = tolower(substr(m, length(m))); n = m
                    if (u ~ /[kmg]/) { n = substr(m, 1, length(m) - 1) } else { u = "b" }
                    f = (u == "k") ? 1024 : (u == "m") ? 1048576 : (u == "g") ? 1073741824 : 1
                    printf "%.0f", n * f }')
                if [ "$heap_bytes" -ge "$memory_bytes" ]
                then
                    logwarn "💀 the JVM of $c can grow its heap to -Xmx$heap, more than the $memory limit: expect an OOM kill (exit 137, OOMKilled) before any OutOfMemoryError"
                else
                    logwarn "☕ -Xmx$heap: the heap fits in $memory, the off-heap memory (metaspace, threads, direct buffers, the page cache counted by the kernel) must fit in the rest"
                fi
            fi
        fi
    fi

    if [[ -n "$fill_disk" ]]
    then
        if ! container_running "$c"
        then
            logerror "❌ $c is not running: its disk cannot be filled"
            exit 1
        fi
        disk_path="${path:-$(default_path "$c")}"
        if ! docker exec "$c" test -d "$disk_path"
        then
            logerror "❌ $disk_path is not a folder of $c"
            exit 1
        fi
        remove_fill_file "$c" > /dev/null
        read -r size used avail <<< "$(disk_usage "$c" "$disk_path")"
        read -r root_size _ <<< "$(disk_usage "$c" /)"
        if [[ -z "$size" ]]
        then
            logerror "❌ could not read the disk usage of $disk_path in $c"
            exit 1
        fi
        # the same size as the root filesystem of the container (overlay): the disk of docker, shared by every
        # container and image (an anonymous volume, or a folder of the image)
        if [[ "$size" == "$root_size" ]]
        then
            logerror "❌ $disk_path of $c is on the disk of docker itself ($(human_bytes $((size * 1024)))), shared by every container and image: filling it to $fill_disk% would fill all of them"
            logerror "   🎓 give $disk_path a filesystem of its own in the docker-compose override of the example, then run this command again:"
            echo "  $c:"
            echo "    tmpfs:"
            echo "      - $disk_path:size=2g,uid=1000,gid=1000"
            exit 1
        fi
        need_kb=$(awk -v u="$used" -v a="$avail" -v p="$fill_disk" 'BEGIN { printf "%d", (u + a) * p / 100 - u }')
        fill_file="${disk_path%/}/$fill_name"
        if [ "$need_kb" -le 0 ]
        then
            logwarn "💾 $disk_path of $c is already above $fill_disk%: nothing written"
        else
            log "🧱 writing $(human_bytes $((need_kb * 1024))) in $fill_file, to fill $disk_path of $c to $fill_disk%"
            state_set "$c" fill_file "$fill_file"
            # fallocate is instant, dd for the images without it (or a filesystem without fallocate support); at 100%
            # dd stops on 'No space left on device', which is the goal
            docker exec -u 0 "$c" sh -c "fallocate -l ${need_kb}K '$fill_file' 2> /dev/null || dd if=/dev/zero of='$fill_file' bs=1024 count=$need_kb 2> /dev/null; sync" || true
        fi
        if [[ "$c" == broker* || "$c" == controller* ]]
        then
            logwarn "💥 when its log dir is full, the broker gets 'No space left on device', marks the log dir offline (KafkaStorageException for the clients of its partitions) and stops if it was its only log dir"
        fi
    fi
    show_status "$c"
done
log "🧽 back to the original limits: playground debug resources $(printf -- '--container %s ' "${containers[@]}")--reset"
