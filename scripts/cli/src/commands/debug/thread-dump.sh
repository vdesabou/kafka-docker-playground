containers="${args[--container]}"
use_jstack="${args[--jstack]}"
debug_image="${DEBUG_IMAGE:-eclipse-temurin:17-jdk}"

get_environment_used

get_cfk_target_container_name() {
    local requested_name="$1"
    case "$requested_name" in
        connect|connect2|connect3|connect-us|connect-europe)
            echo "connect"
            ;;
        broker|kafka)
            echo "kafka"
            ;;
        schema-registry|schemaregistry)
            echo "schemaregistry"
            ;;
        control-center|controlcenter)
            echo "controlcenter"
            ;;
        ksqldb-server|ksqldb)
            echo "ksqldb"
            ;;
        *)
            echo "$requested_name"
            ;;
    esac
}

# jstack -l (adds the java.util.concurrent lock owners); never restarts the container
# $1: container, $2: resolved container, $3: output file
take_thread_dump_with_jstack() {
    local container="$1" resolved_container="$2" filename="$3"
    local target_container_name
    target_container_name=$(get_cfk_target_container_name "$container")

    if [[ "$environment" == cfk* ]]
    then
        if ! playground --output-level ERROR container exec --container "$resolved_container" --command "test -x /tmp/jdk-tools/bin/jstack || type jstack" > /dev/null 2>&1
        then
            logwarn "jstack is not available on pod $resolved_container, attaching debug container $debug_image (the pod is not restarted)"
            debug_stderr=$(mktemp -t pg-debug-XXXXXXXXXX)
            kubectl -n confluent debug "$resolved_container" --image="$debug_image" --target="$target_container_name" --profile=sysadmin -- bash -lc 'set -e; TARGET_PID=""; for p in /proc/[0-9]*; do if grep -aq "java" "$p/cmdline" 2>/dev/null; then TARGET_PID="${p#/proc/}"; break; fi; done; [ -n "$TARGET_PID" ] || TARGET_PID=1; TARGET_ROOT="/proc/${TARGET_PID}/root"; mkdir -p "${TARGET_ROOT}/tmp/jdk-tools/bin"; JSTACK_BIN="$(command -v jstack)"; JDK_HOME="$(cd "$(dirname "$JSTACK_BIN")/.." && pwd)"; cp "$JSTACK_BIN" "${TARGET_ROOT}/tmp/jdk-tools/bin/"; rm -rf "${TARGET_ROOT}/tmp/jdk-tools/lib"; cp -r "$JDK_HOME/lib" "${TARGET_ROOT}/tmp/jdk-tools/"' > /dev/null 2>"$debug_stderr"
            if [ $? != 0 ]
            then
                logerror "❌ could not prepare jstack tools in pod $resolved_container"
                cat "$debug_stderr"
                rm -f "$debug_stderr"
                return 1
            fi
            rm -f "$debug_stderr"
        fi
        kubectl -n confluent exec "$resolved_container" -c "$target_container_name" -- /bin/sh -c "if [ -x /tmp/jdk-tools/bin/jstack ]; then cd /tmp/jdk-tools && ./bin/jstack -l 1; else jstack -l 1; fi" > "$filename" 2>&1
        return $?
    fi

    if ! playground --output-level ERROR container exec --container "$resolved_container" --command "type jstack" > /dev/null 2>&1
    then
        logerror "❌ jstack is not installed in container $container (the image has a JRE only)"
        log "💡 playground container change-jdk --version 17 installs a JDK, but it RESTARTS the container: the state you want to look at is lost"
        return 1
    fi
    playground --output-level ERROR container exec --container "$resolved_container" --command "date '+%Y-%m-%d %H:%M:%S'; jstack -l 1" > "$filename" 2>&1
}

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    set +e
    resolved_container=$(resolve_container_name_for_environment "$container")
    filename="/tmp/thread-dump-$container-$(date '+%Y-%m-%d-%H-%M-%S').log"

    done_ok=""
    if [[ -z "$use_jstack" ]]
    then
        log "🎯 Taking thread dump on container ${container} with kill -3"
        if take_thread_dumps_with_kill_quit "$container" 1 0 "$filename"
        then
            done_ok=1
        else
            logwarn "⚠️  the kill -3 output did not reach the logs of $container, trying jstack"
        fi
    fi
    if [[ -z "$done_ok" ]]
    then
        log "🎯 Taking thread dump on container ${container} with jstack -l"
        take_thread_dump_with_jstack "$container" "$resolved_container" "$filename" && grep -q "Full thread dump" "$filename" && done_ok=1
    fi
    set -e

    if [[ -n "$done_ok" ]]
    then
        log "👻 thread dump is available at ${filename}"
        log "🔬 Analyze it with: playground analyze thread-dump --file ${filename}"
        playground open --file "${filename}"
    else
        logerror "❌ failed to take thread dump on container $container"
    fi
done
