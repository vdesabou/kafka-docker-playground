containers="${args[--container]}"
action="${args[--action]}"
settings="${args[--settings]}"
output_dir="${args[--output-dir]}"
no_analyze="${args[--no-analyze]}"
eval "trace_methods=(${args[--trace-method]})"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

# settings: a .jfc file of the playground, or settings shipped with the JDK
case "${settings}" in
    playground) settings_file="$root_folder/tools/jfr-analyzer/playground.jfc" ;;
    all) settings_file="$root_folder/scripts/cli/all.jfc" ;;
    *) settings_file="" ;;
esac

get_environment_used

if [[ ${#trace_methods[@]} -gt 0 && "$action" == "start" ]]
then
    if [[ -z "$settings_file" ]]
    then
        logerror "❌ --trace-method needs --settings playground or all (the settings $settings of the JDK cannot be extended)"
        exit 1
    fi
    for container in "${container_array[@]}"
    do
        check_method_trace_supported "$container"
    done
    settings_file=$(jfr_settings_with_method_trace "$settings_file" "${trace_methods[@]}") || exit 1
    log "🎯 tracing every call of ${trace_methods[*]} (JDK 25 method tracing)"
fi

# the recording of each container is kept in playground.ini, flight_recorder.<container>:
#   jmx <jmx port> <recording id> <settings> <start epoch>   recording driven over JMX (FlightRecorderMXBean)
#   jcmd - dump1 <settings> <start epoch>                    recording started with jcmd (cfk pods, no JMX port)
function jmx_port_of () {
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" 2> /dev/null | sed -n 's/^[A-Z_]*JMX_PORT=//p' | head -1
}

function format_epoch () {
    date -r "$1" "$2" 2> /dev/null || date -d "@$1" "$2" 2> /dev/null || echo "$1"
}

function has_jcmd () {
    playground --output-level ERROR container exec --container "$1" --command "type jcmd" > /dev/null 2>&1
}

function analyze_recording () {
    local file="$1"
    if [[ -n "$no_analyze" ]]
    then
        log "🔎 analyze it with: playground analyze flight-recorder -f $file"
        return
    fi
    log "🔎 analyzing $file (--no-analyze to skip it)"
    playground analyze flight-recorder -f "$file" --output-dir "$(dirname "$file")" || logwarn "⚠️ the recording could not be analyzed, open it with JDK Mission Control (https://jdk.java.net/jmc/)"
}

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

for container in "${container_array[@]}"
do
    state=$(playground state get "flight_recorder.$container" 2> /dev/null)
    read -r mode port id recorded_settings started_at <<< "$state"

    case "${action}" in
        start)
            if [[ -n "$state" ]]
            then
                logwarn "🛩️ flight recorder is already started on $container (settings $recorded_settings, since $(format_epoch "$started_at" '+%H:%M:%S')): stop it with --action stop"
                continue
            fi
            # over JMX first: no jcmd needed (the cp images ship a JRE) and no restart
            port=""
            if [[ "$environment" != cfk* ]]
            then
                port=$(jmx_port_of "$container")
            fi
            if [[ -n "$port" ]]
            then
                benchmark_jmx_init "$container $port"
                if recording=$(jfr_jmx_start "$container $port" "${settings_file:-$settings}")
                then
                    read -r _ _ id <<< "$recording"
                    playground state set "flight_recorder.$container" "jmx $port $id $settings $(date +%s)"
                    log "🛩️ flight recorder is now started on $container over JMX (recording $id, settings $settings)"
                    continue
                fi
                logwarn "⚠️ the flight recorder of $container could not be started over JMX (localhost:$port), trying jcmd"
            fi
            if ! has_jcmd "$container"
            then
                logerror "❌ cannot start the flight recorder of $container: no JMX port (KAFKA_JMX_PORT, SCHEMA_REGISTRY_JMX_PORT...) reachable and no jcmd in the image"
                log "💡 playground container change-jdk --version <n> installs a JDK with jcmd, but it restarts the container"
                exit 1
            fi
            remote_settings="$settings"
            if [[ -n "$settings_file" ]]
            then
                remote_settings="/tmp/$(basename "$settings_file")"
                playground container cp --source "$settings_file" --destination "$container:$remote_settings" > /dev/null 2>&1
            fi
            if playground --output-level ERROR container exec --container "$container" --command "jcmd 1 JFR.start name=dump1 settings=$remote_settings"
            then
                playground state set "flight_recorder.$container" "jcmd - dump1 $settings $(date +%s)"
                log "🛩️ flight recorder is now started on $container with jcmd (settings $settings)"
            else
                logerror "❌ failed to start the flight recorder of $container with jcmd"
                exit 1
            fi
        ;;
        stop)
            if [[ -z "$state" ]]
            then
                logerror "🛩️ flight recorder is not started on $container !"
                exit 1
            fi
            filename="$output_dir/flight-recorder-$container-$(date '+%Y-%m-%d-%H-%M-%S').jfr"
            if [[ "$mode" == "jmx" ]]
            then
                benchmark_jmx_init "$container $port"
                recorded=$(jfr_jmx_stop "$container $port $id" "${filename%.jfr}.tmp")
                if [[ -z "$recorded" ]]
                then
                    playground state del "flight_recorder.$container" > /dev/null 2>&1
                    logerror "❌ failed to stop the flight recorder of $container over JMX (recording $id): the JVM restarted, or the recording was closed"
                    exit 1
                fi
                mv "$recorded" "$filename"
            else
                remote="/tmp/$(basename "$filename")"
                if ! playground --output-level ERROR container exec --container "$container" --command "jcmd 1 JFR.stop name=dump1 filename=$remote"
                then
                    playground state del "flight_recorder.$container" > /dev/null 2>&1
                    logerror "❌ failed to stop the flight recorder of $container with jcmd"
                    exit 1
                fi
                playground container cp --source "$container:$remote" --destination "$filename" > /dev/null 2>&1
                playground --output-level ERROR container exec --container "$container" --command "rm -f $remote" > /dev/null 2>&1
            fi
            playground state del "flight_recorder.$container" > /dev/null 2>&1
            log "🛩️ flight recording of $container ($(( $(date +%s) - started_at ))s, settings $recorded_settings) is available at $filename"
            log "use JDK Mission Control JMC (https://jdk.java.net/jmc/) to open it"
            analyze_recording "$filename"
        ;;
        status)
            if [[ -z "$state" ]]
            then
                log "🛩️ no flight recording started on $container by the playground"
            else
                log "🛩️ flight recording running on $container since $(format_epoch "$started_at" '+%Y-%m-%d %H:%M:%S') ($(( $(date +%s) - started_at ))s), with $mode, settings $recorded_settings"
            fi
        ;;
        *)
            logerror "should not happen"
            exit 1
        ;;
    esac
done
