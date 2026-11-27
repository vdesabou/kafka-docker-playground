eval "containers=(${args[--container]})"
offset="${args[--offset]}"
at="${args[--at]}"
reset="${args[--reset]}"

get_environment_used
if [[ "$environment" == cfk* ]]
then
    logerror "❌ playground debug clock is not supported with cfk yet"
    exit 1
fi

stage_root="/tmp/playground-faketime"
remote_dir="/tmp/faketime"

# true when the container runs with libfaketime (LD_PRELOAD set by a previous 'debug clock')
function clock_faked () {
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2> /dev/null | grep -q "^LD_PRELOAD=$remote_dir/libfaketime.so.1"
}

# every running container with a fake clock (set-environment-variables remembers their values: passing them again is
# harmless, and keeps the ones started before that change working)
function all_faked_containers () {
    local c
    for c in $(docker ps --format '{{.Names}}')
    do
        clock_faked "$c" && echo "$c"
    done
}

function show_clock () {
    local c="$1" now real rc
    real=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    if ! clock_faked "$c"
    then
        log "🕰️ $c: real time ($real), no fake clock"
        return
    fi
    now=$(docker exec "$c" date -u '+%Y-%m-%d %H:%M:%S UTC' 2> /dev/null)
    rc=$(cat "$stage_root/$c/faketime.rc" 2> /dev/null)
    if [[ "$rc" == "+0" || -z "$rc" ]]
    then
        log "🕰️ $c: $now, real time (libfaketime loaded, offset +0)"
    else
        log "🕰️ $c: $now (real $real, offset $rc)"
    fi
}

function recreate_with_faketime () {
    local flags=() c
    for c in "$@"
    do
        flags+=(--container "$c")
    done
    if ! playground container set-environment-variables "${flags[@]}" \
        --env "LD_PRELOAD: $remote_dir/libfaketime.so.1" \
        --env "FAKETIME_TIMESTAMP_FILE: $remote_dir/faketime.rc" \
        --env "FAKETIME_CACHE_DURATION: 1" \
        --env "FAKETIME_DONT_FAKE_MONOTONIC: 1" \
        --mount-faketime-files
    then
        logerror "❌ could not recreate $* with libfaketime"
        exit 1
    fi
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
if [[ -z "$offset" && -z "$at" && -z "$reset" ]]
then
    for c in "${containers[@]}"
    do
        show_clock "$c"
    done
    exit 0
fi

# ---- reset -------------------------------------------------------------------------------------------------------
if [[ -n "$reset" ]]
then
    to_reset=()
    for c in "${containers[@]}"
    do
        if clock_faked "$c"
        then
            # real time right away, even if the recreate below fails
            echo "+0" > "$stage_root/$c/faketime.rc"
            to_reset+=("$c")
        else
            log "💫 $c has no fake clock"
        fi
    done
    [[ ${#to_reset[@]} -eq 0 ]] && exit 0
    remaining=()
    for c in $(all_faked_containers)
    do
        [[ " ${to_reset[*]} " == *" $c "* ]] || remaining+=("$c")
    done
    # set-environment-variables remembers the values of each container: restoring the ones reset keeps the fake clock
    # of the others (replayed with them), the ones reset get their original definition
    if [[ ${#remaining[@]} -eq 0 ]]
    then
        log "🧽 recreating ${to_reset[*]} without libfaketime"
    else
        log "🧽 recreating ${to_reset[*]} without libfaketime (still on a fake clock: ${remaining[*]})"
    fi
    flags=()
    for c in "${to_reset[@]}"
    do
        flags+=(--container "$c")
    done
    playground container set-environment-variables "${flags[@]}" --restore-original-values || exit 1
    for c in "${containers[@]}"
    do
        show_clock "$c"
    done
    exit 0
fi

# ---- offset / at -------------------------------------------------------------------------------------------------
if [[ -n "$at" ]]
then
    # an absolute date becomes an offset from now: with "@<date>" in the rc file, each process would start at that
    # date when it reads the file, and processes started later would not agree
    if ! offset=$(python3 -I -c '
import datetime, re, sys
s = sys.argv[1].strip()
m = re.match(r"^(\d{4}-\d{2}-\d{2})(?:[ T](\d{2}:\d{2}(?::\d{2})?))?\s*(Z|UTC|[+-]\d{2}:?\d{2})?$", s)
if not m:
    sys.exit(1)
date, time, zone = m.groups()
time = time or "00:00:00"
if time.count(":") == 1:
    time += ":00"
d = datetime.datetime.strptime(date + " " + time, "%Y-%m-%d %H:%M:%S")
if zone in (None, "Z", "UTC"):
    d = d.replace(tzinfo=datetime.timezone.utc)
else:
    z = zone.replace(":", "")
    sign = 1 if z[0] == "+" else -1
    d = d.replace(tzinfo=datetime.timezone(sign * datetime.timedelta(hours=int(z[1:3]), minutes=int(z[3:5]))))
seconds = int(round((d - datetime.datetime.now(datetime.timezone.utc)).total_seconds()))
print("%+d" % seconds)' "$at")
    then
        logerror "❌ --at $at is not a date: use \"YYYY-MM-DD HH:MM:SS\" (UTC), with an optional Z or +02:00 offset"
        exit 1
    fi
else
    if [[ ! "$offset" =~ ^[+-]?[0-9]+(\.[0-9]+)?[smhdy]?$ ]]
    then
        logerror "❌ --offset $offset is not valid: a number of seconds, or with a unit s, m, h, d, y, e.g. +2h, +1d, or --offset=-30m to go back"
        exit 1
    fi
    [[ "$offset" =~ ^[0-9] ]] && offset="+$offset"
fi

to_recreate=()
for c in "${containers[@]}"
do
    if docker exec "$c" sh -c 'ls /lib/ld-musl-* > /dev/null 2>&1'
    then
        logerror "❌ $c is a musl (alpine) image: libfaketime is built for glibc"
        exit 1
    fi
    stage="$stage_root/$c"
    mkdir -p "$stage"
    if ! clock_faked "$c"
    then
        image=$(docker inspect -f '{{.Config.Image}}' "$c")
        arch=$(docker image inspect -f '{{.Architecture}}' "$image" 2> /dev/null)
        case "$arch" in
            amd64|arm64) ;;
            *) logerror "❌ architecture $arch of $c ($image) is not supported (amd64, arm64)"; exit 1 ;;
        esac
        lib=$(faketime_library "$arch") || exit 1
        cp "$lib" "$stage/libfaketime.so.1"
        to_recreate+=("$c")
    fi
    echo "$offset" > "$stage/faketime.rc"
    chmod -R a+rX "$stage"
done

if [[ ${#to_recreate[@]} -gt 0 ]]
then
    others=()
    for c in $(all_faked_containers)
    do
        [[ " ${to_recreate[*]} " == *" $c "* ]] || others+=("$c")
    done
    log "🔁 recreating ${to_recreate[*]} with libfaketime (once: then the clock changes without a restart)"
    recreate_with_faketime "${to_recreate[@]}" "${others[@]}"
else
    # FAKETIME_CACHE_DURATION=1: the processes read the rc file again within a second
    sleep 2
fi

for c in "${containers[@]}"
do
    show_clock "$c"
done
if [[ "$offset" == +* && "$offset" != "+0" ]]
then
    logwarn "⏩ a jump forward fires the timeouts based on wall clock time at once (sessions, token and ticket lifetimes, metadata max age): expect reconnections, a rebalance, a token refresh"
    # the brokers refuse the records of a client too far in the future (Kafka 4.0, KIP-937: 1 hour by default): connect
    # cannot even write its status and offsets, InvalidTimestampException
    offset_seconds=$(awk -v o="$offset" 'BEGIN {
        unit = substr(o, length(o)); n = o
        if (unit ~ /[smhdy]/) { n = substr(o, 1, length(o) - 1) } else { unit = "s" }
        f = (unit == "m") ? 60 : (unit == "h") ? 3600 : (unit == "d") ? 86400 : (unit == "y") ? 31536000 : 1
        printf "%d", n * f }')
    clients=()
    for c in "${containers[@]}"
    do
        [[ "$c" == broker* || "$c" == controller* ]] || clients+=("$c")
    done
    if [[ ${#clients[@]} -gt 0 ]] && [ "${offset_seconds:-0}" -gt 3000 ]
    then
        after_max_ms=$(playground broker config get --key log.message.timestamp.after.max.ms 2> /dev/null | awk '$1 ~ /^[0-9]+$/ { print $2; exit }')
        after_max_ms="${after_max_ms:-3600000}"
        if [ $((offset_seconds * 1000)) -gt "$after_max_ms" ]
        then
            logwarn "🚫 the brokers refuse records more than log.message.timestamp.after.max.ms=$after_max_ms ms in the future (InvalidTimestampException): ${clients[*]} cannot produce, and a connect worker stops (Error writing session key to Kafka) and restarts in a loop"
            logwarn "   🎓 shift the brokers too (--container broker), or: playground broker config set --key log.message.timestamp.after.max.ms --value 9223372036854775807"
        fi
    fi
fi
log "🧽 back to real time: playground debug clock $(printf -- '--container %s ' "${containers[@]}")--reset"
