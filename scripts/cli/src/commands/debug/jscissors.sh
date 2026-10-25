containers="${args[--container]}"
action="${args[--action]}"
# Convert the space delimited strings to arrays
eval "operations=(${args[--operation]})"
eval "classes=(${args[--class]})"
eval "methods=(${args[--method]})"
config_file="${args[--config-file]}"
duration="${args[--duration]}"
restart="${args[--restart]}"
pid="${args[--pid]}"
max_calls="${args[--max-calls]}"
max_calls_per_method="${args[--max-calls-per-method]}"
max_value_length="${args[--max-value-length]}"
only_failed="${args[--only-failed]}"
slower_than="${args[--slower-than]}"
output_dir="${args[--output-dir]}"
no_analyze="${args[--no-analyze]}"

# names of jscissors 1.0
case "$action" in
    enable) action="start" ;;
    disable) action="stop" ;;
esac

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

# in the container: the agent, its rules and the files of the session (out/pid-<pid>/)
remote_dir="/tmp/jscissors"
agent_args="config=$remote_dir/jscissors.props,out=$remote_dir/out"

function format_epoch () {
    date -r "$1" "$2" 2> /dev/null || date -d "@$1" "$2" 2> /dev/null || echo "$1"
}

function jmx_port_of () {
    if [[ "$environment" == cfk* ]]
    then
        return 0
    fi
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2> /dev/null | sed -n 's/^[A-Z_]*JMX_PORT=//p' | head -1
}

function in_container () {
    playground --output-level ERROR container exec --container "$1" --command "$2"
}

# loads the agent in the running JVM of the container (jscissors.Attach), with the agent arguments $2
function attach () {
    local container="$1" arguments="$2" port jmx_arg=""
    port=$(jmx_port_of "$container")
    if [[ -n "$port" ]]
    then
        jmx_arg="--jmx localhost:$port"
    fi
    in_container "$container" "env -u JAVA_TOOL_OPTIONS -u _JAVA_OPTIONS java -Xmx64m -cp $remote_dir/jscissors.jar jscissors.Attach --pid $pid $jmx_arg --agent-args $arguments"
}

# summary.json of the traced JVM: with --restart, every JVM started in the container (kafka tools...) loads the agent
# too, so the one with the most calls, then the most classes instrumented, then the oldest
function summary_of () {
    in_container "$1" "cat $remote_dir/out/pid-*/summary.json 2> /dev/null" 2> /dev/null \
        | jq -c -s 'sort_by(-.calls, -(.instrumented | length), .pid) | first // empty' 2> /dev/null
}

function write_rules () {
    local file="$1" class method operation_string
    operation_string=$(IFS=+; echo "${operations[*]}")
    {
        echo "# written by playground debug jscissors on $(date '+%Y-%m-%d %H:%M:%S')"
        if [[ -n "$config_file" ]]
        then
            cat "$config_file"
        fi
        for class in "${classes[@]}"
        do
            for method in "${methods[@]}"
            do
                echo "${class}{${method}}=${operation_string}"
            done
        done
        if [[ -n "$max_calls" ]]
        then
            echo "jscissors.maxCalls=$max_calls"
        fi
        if [[ -n "$max_calls_per_method" ]]
        then
            echo "jscissors.maxCallsPerMethod=$max_calls_per_method"
        fi
        if [[ -n "$max_value_length" ]]
        then
            echo "jscissors.maxValueLength=$max_value_length"
        fi
        if [[ -n "$only_failed" ]]
        then
            echo "jscissors.onlyFailed=1"
        fi
        if [[ -n "$slower_than_ms" ]]
        then
            echo "jscissors.slowerThanMs=$slower_than_ms"
        fi
    } > "$file"
}

# prints what the agent instrumented, from its summary.json
function report_start () {
    local container="$1" summary="$2" instrumented
    instrumented=$(echo "$summary" | jq -r '.instrumented | length' 2> /dev/null)
    echo "$summary" | jq -r '.warnings[]?, .errors[]?' 2> /dev/null | while read -r line
    do
        logwarn "⚠️ $line"
    done
    if [[ "$instrumented" == "0" ]]
    then
        logwarn "🔍 no class of $container matches the rules yet: they are instrumented when they load (start the connector now), unless the class name is wrong (exact name, or a regex like io.confluent.connect.jdbc.*) or it is a JDK class (java.*: not supported)"
    else
        log "✂️ $instrumented class(es) instrumented in $container: $(echo "$summary" | jq -r '.instrumented[:5] | join(", ")')$([[ $instrumented -gt 5 ]] && echo ", ...")"
    fi
}

function start_one () {
    local container="$1" stage="/tmp/playground-jscissors/$1" summary output i
    rm -rf "$stage"
    mkdir -p "$stage/out"
    cp "$jar" "$stage/jscissors.jar"
    write_rules "$stage/jscissors.props"
    log "✂️ rules for $container:"
    grep -v '^#' "$stage/jscissors.props" | sed 's/^/     /'

    if [[ -n "$restart" ]]
    then
        # the container is recreated with the agent in JAVA_TOOL_OPTIONS: the startup of the JVM is traced too.
        # docker: $stage is mounted on $remote_dir (written by appuser, uid 1000); cfk: copied in a new image
        chmod -R a+rwX "$stage"
        log "🔁 recreating $container with the agent loaded at the start of the JVM"
        if ! playground container set-environment-variables --container "$container" --env "JAVA_TOOL_OPTIONS: -javaagent:$remote_dir/jscissors.jar=$agent_args" --mount-jscissors-files
        then
            logerror "❌ could not recreate $container with the agent"
            exit 1
        fi
        playground state set "jscissors.$container" "restart $(date +%s)"
    else
        in_container "$container" "mkdir -p $remote_dir && rm -rf $remote_dir/out $remote_dir/jscissors.jar $remote_dir/jscissors.props"
        playground container cp --source "$stage/jscissors.jar" --destination "$container:$remote_dir/jscissors.jar" > /dev/null 2>&1
        playground container cp --source "$stage/jscissors.props" --destination "$container:$remote_dir/jscissors.props" > /dev/null 2>&1
        log "💉 loading the agent in the running JVM of $container (no restart)"
        if ! output=$(attach "$container" "$agent_args" 2>&1)
        then
            echo "$output" | sed 's/^/     /'
            logerror "❌ could not load the agent in $container: the JVM refuses the attach (-XX:+DisableAttachMechanism), or its JDK is older than 16 and it has no JMX port"
            log "💡 use --restart to load the agent at the start of the JVM (the container is recreated)"
            exit 1
        fi
        echo "$output" | sed 's/^/     /'
        playground state set "jscissors.$container" "attach $(date +%s)"
    fi

    for i in $(seq 1 30)
    do
        summary=$(summary_of "$container")
        [[ -n "$summary" ]] && break
        sleep 2
    done
    if [[ -z "$summary" ]]
    then
        logerror "❌ the agent did not start in $container, see: playground container logs -c $container --grep jscissors --no-follow"
        exit 1
    fi
    report_start "$container" "$summary"
}

function stop_one () {
    local container="$1" stage="/tmp/playground-jscissors/$1" state mode started_at dest file files output
    state=$(playground state get "jscissors.$container" 2> /dev/null)
    read -r mode started_at <<< "$state"
    if [[ -z "$state" ]]
    then
        logerror "✂️ jscissors is not started on $container !"
        exit 1
    fi
    dest="$output_dir/jscissors-$container-$(date '+%Y-%m-%d-%H-%M-%S')"
    mkdir -p "$dest"

    # stops the session: original classes restored, final summary.json written
    if ! output=$(attach "$container" "action=stop" 2>&1)
    then
        echo "$output" | sed 's/^/     /'
        logwarn "⚠️ could not stop the agent in $container cleanly: copying what it wrote so far"
    fi
    if [[ "$mode" == "restart" && "$environment" != cfk* ]]
    then
        # mounted from the host: the files are already there, and survive the recreation of the container
        log "🧽 recreating $container without the agent"
        playground container set-environment-variables --container "$container" --restore-original-values
        cp -R "$stage/out/." "$dest/"
    else
        files=$(in_container "$container" "cd $remote_dir/out 2> /dev/null && find . -type f")
        for file in $files
        do
            mkdir -p "$dest/$(dirname "$file")"
            playground container cp --source "$container:$remote_dir/out/${file#./}" --destination "$dest/${file#./}" > /dev/null 2>&1
        done
        in_container "$container" "rm -rf $remote_dir/out" > /dev/null 2>&1
        if [[ "$mode" == "restart" ]]
        then
            log "🧽 restoring $container without the agent"
            playground container set-environment-variables --container "$container" --restore-original-values
        fi
    fi
    playground state del "jscissors.$container" > /dev/null 2>&1
    if ! ls "$dest"/pid-*/summary.json > /dev/null 2>&1
    then
        logerror "❌ no trace copied from $container to $dest"
        exit 1
    fi
    log "✂️ trace of $container ($(( $(date +%s) - started_at ))s) copied to $dest"
    if [[ -n "$no_analyze" ]]
    then
        log "🔎 analyze it with: playground analyze jscissors -f $dest"
        return
    fi
    playground analyze jscissors -f "$dest" --output-dir "$dest" || logwarn "⚠️ the trace could not be analyzed: the raw events are in $dest/pid-*/events.jsonl"
}

function status_one () {
    local container="$1" state mode started_at summary
    state=$(playground state get "jscissors.$container" 2> /dev/null)
    read -r mode started_at <<< "$state"
    if [[ -z "$state" ]]
    then
        log "✂️ jscissors is not started on $container by the playground"
        return
    fi
    summary=$(summary_of "$container")
    log "✂️ jscissors running on $container since $(format_epoch "$started_at" '+%Y-%m-%d %H:%M:%S') ($(( $(date +%s) - started_at ))s), $([[ "$mode" == "restart" ]] && echo "loaded at the start of the JVM" || echo "attached")"
    if [[ -n "$summary" ]]
    then
        echo "$summary" | jq -r '"     \(.calls) call(s) (summary refreshed every 5s), \(.calls_recorded) with details, \(.instrumented | length) class(es) instrumented, \(.error_count) agent error(s)", (.rules[] | "     rule \(.)")'
        echo "$summary" | jq -r '.methods | sort_by(-.total_us) | .[:5][] | "     \(.calls) call(s) \(.total_us / 1000 | floor) ms  \(.class | split(".") | last).\(.method)"'
    fi
}

# --slower-than: 500ms, 2s, 1m or a number of milliseconds
slower_than_ms=""
if [[ -n "$slower_than" ]]
then
    case "$slower_than" in
        *ms) slower_than_ms="${slower_than%ms}" ;;
        *s|*m|*h) slower_than_ms=$(( $(duration_to_seconds "$slower_than") * 1000 )) ;;
        *) slower_than_ms="$slower_than" ;;
    esac
    if ! [[ "$slower_than_ms" =~ ^[0-9]+$ ]] || [[ "$slower_than_ms" -eq 0 ]]
    then
        logerror "❌ --slower-than $slower_than: expected a duration like 500ms, 2s or 1m"
        exit 1
    fi
fi

if [[ "$action" == "start" ]]
then
    if [[ ${#classes[@]} -eq 0 && -z "$config_file" ]]
    then
        logerror "❌ --class (or --config-file) is required with --action start"
        exit 1
    fi
    if [[ -n "$config_file" && ! -f "$config_file" ]]
    then
        logerror "❌ --config-file $config_file not found"
        exit 1
    fi
    if ! jar=$(jscissors_agent_jar)
    then
        exit 1
    fi
fi

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

for container in "${container_array[@]}"
do
    case "${action}" in
        start)
            if [[ -n "$(playground state get "jscissors.$container" 2> /dev/null)" ]]
            then
                logwarn "✂️ jscissors is already started on $container: its rules are replaced (the trace so far is discarded)"
            fi
            start_one "$container"
        ;;
        stop)
            stop_one "$container"
        ;;
        status)
            status_one "$container"
        ;;
        *)
            logerror "should not happen"
            exit 1
        ;;
    esac
done

if [[ "$action" == "start" && -n "$duration" ]]
then
    seconds=$(duration_to_seconds "$duration")
    log "⏱️ tracing for ${seconds}s, then stopping and analyzing (reproduce the problem now)"
    sleep "$seconds"
    for container in "${container_array[@]}"
    do
        stop_one "$container"
    done
elif [[ "$action" == "start" ]]
then
    log "🛑 stop it, copy the trace and analyze it with: playground debug jscissors --action stop$(for c in "${container_array[@]}"; do printf ' -c %s' "$c"; done)"
fi
