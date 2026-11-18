idle_hours="${args[--idle-hours]}"
scheduled="${args[--scheduled]}"

if [ "$idle_hours" -lt 1 ]
then
    logerror "❌ --idle-hours $idle_hours must be 1 or more"
    exit 1
fi

if [[ -n "$scheduled" ]]
then
    log "🔔 forgotten environment check of $(date '+%Y-%m-%d %H:%M'), idle for $idle_hours hours"
fi
if ! docker info > /dev/null 2>&1
then
    log "💤 the container engine is not running: nothing to check"
    exit 0
fi
ids=$(docker ps -q 2> /dev/null)
if [ -z "$ids" ]
then
    log "😴 no container running: nothing forgotten"
    exit 0
fi

# 3 h, 45 min, 2 days
human_duration () {
    local s="$1"
    if [ "$s" -lt 3600 ]
    then
        echo "$((s / 60)) min"
    elif [ "$s" -lt 172800 ]
    then
        echo "$((s / 3600)) h"
    else
        echo "$((s / 86400)) days"
    fi
}
# modification time of $1 in epoch seconds, empty when it does not exist (GNU stat first: BSD stat rejects -c, while
# GNU stat accepts -f with another meaning)
mtime () {
    [ -e "$1" ] || return 0
    stat -c %Y "$1" 2> /dev/null || stat -f %m "$1" 2> /dev/null
}
# value of the key $2 of the [run] section of the playground.ini $1
ini_run_value () {
    awk -F' = ' -v key="$2" '/^\[/ { in_run = ($0 == "[run]") } in_run && $1 == key { print substr($0, length($1) + 4); exit }' "$1" 2> /dev/null
}
# the playground checkout (or worktree) holding the folder $1 (the working dir of a compose project), empty if none
checkout_of () {
    local d="$1"
    while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]
    do
        if [ -f "$d/scripts/cli/playground" ] && [ -d "$d/environment" ]
        then
            (cd "$d" 2> /dev/null && pwd -P)
            return 0
        fi
        d=$(dirname "$d")
    done
}

now=$(date +%s)
# <start epoch> <name> <compose working dir>; StartedAt is UTC with docker (…Z), local time with an offset with podman
containers=$(docker inspect $ids 2> /dev/null | jq -r '
    def epoch: capture("^(?<d>[0-9-]+T[0-9:]+)(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})$")
        | (.d + "Z" | fromdateiso8601) - (if .z == "Z" then 0 else (.z | gsub(":"; "")) as $o
            | (($o[1:3] | tonumber) * 3600 + ($o[3:5] | tonumber) * 60) * (if $o[0:1] == "-" then -1 else 1 end) end);
    .[] | [ ((.State.StartedAt | epoch?) // 0), (.Name | ltrimstr("/")), (.Config.Labels["com.docker.compose.project.working_dir"] // "") ] | @tsv')
if [ -z "$containers" ]
then
    logwarn "⚠️ could not inspect the running containers: nothing to check"
    exit 0
fi
nb_containers=$(echo "$containers" | wc -l | tr -d ' ')

last_start=0
first_start=0
checkouts=()
while IFS=$'\t' read -r started name workdir
do
    if [ "$started" -gt "$last_start" ]
    then
        last_start=$started
    fi
    if [ "$started" -gt 0 ] && { [ "$first_start" -eq 0 ] || [ "$started" -lt "$first_start" ]; }
    then
        first_start=$started
    fi
    checkout=""
    if [ -n "$workdir" ]
    then
        checkout=$(checkout_of "$workdir")
    fi
    # containers of no compose project (CFK k3d nodes, kcat…): this checkout
    checkout="${checkout:-$(cd "$root_folder" && pwd -P)}"
    if [[ " ${checkouts[*]} " != *" $checkout "* ]]
    then
        checkouts+=("$checkout")
    fi
done <<< "$containers"

if [ "$last_start" -eq 0 ]
then
    logwarn "⚠️ could not read when the running containers started: nothing to check"
    exit 0
fi

last_activity=$last_start
what=()
for checkout in "${checkouts[@]}"
do
    activity=0
    for f in "$checkout/playground.ini" "$checkout/playground-run-history"
    do
        m=$(mtime "$f")
        if [[ "$m" =~ ^[0-9]+$ ]] && [ "$m" -gt "$activity" ]
        then
            activity=$m
        fi
    done
    if [ "$activity" -gt "$last_activity" ]
    then
        last_activity=$activity
    fi
    test_file=$(ini_run_value "$checkout/playground.ini" test_file)
    environment=$(ini_run_value "$checkout/playground.ini" environment)
    example="${test_file:+$(basename "$(dirname "$test_file")")/$(basename "$test_file")}"
    activity_text="never"
    if [ "$activity" -gt 0 ]
    then
        activity_text="$(human_duration $((now - activity))) ago"
    fi
    log "📂 $checkout: ${example:-no example recorded} (${environment:-environment unknown}), last playground activity $activity_text"
    what+=("$(basename "${test_file:-$checkout}")")
done

running_for=$(human_duration $((now - ${first_start:-$last_start})))
idle_for=$((now - last_activity))
log "🐳 $nb_containers container(s) running for $running_for, last one started $(human_duration $((now - last_start))) ago"

if [ "$idle_for" -lt $((idle_hours * 3600)) ]
then
    log "🟢 in use: last container start or playground activity $(human_duration "$idle_for") ago (under $idle_hours h), no notification"
    exit 0
fi

# memory used by the containers, from 1.2GiB / 7.6GiB (docker) or 1.2GB / 7.6GB (podman)
memory=$(docker stats --no-stream --format '{{.MemUsage}}' $ids 2> /dev/null | awk '
    { v = $1; n = v + 0; u = v; sub(/^[0-9.]+/, "", u)
      if (u == "KiB") n *= 1024; else if (u == "MiB") n *= 1048576; else if (u == "GiB") n *= 1073741824
      else if (u == "kB" || u == "KB") n *= 1e3; else if (u == "MB") n *= 1e6; else if (u == "GB") n *= 1e9
      total += n }
    END { if (total >= 1e9) printf "%.1f GB", total / 1e9; else if (total > 0) printf "%.0f MB", total / 1e6 }')

summary="${what[*]}: $nb_containers container(s) up for $running_for${memory:+, $memory of RAM}, no playground activity for $(human_duration "$idle_for")"
logwarn "🔔 forgotten? $summary"
log "👉 playground stop   # from the checkout that started it (not done for you: it may run on purpose)"
if [[ -n "$scheduled" ]]
then
    scheduled_job_notify "🔔 kafka-docker-playground environment still running" "$summary. playground stop?"
fi
