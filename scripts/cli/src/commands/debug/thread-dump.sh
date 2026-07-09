containers="${args[--container]}"
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

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    resolved_container=$(resolve_container_name_for_environment "$container")
    target_container_name=$(get_cfk_target_container_name "$container")
    filename="/tmp/thread-dump-$container-$(date '+%Y-%m-%d-%H-%M-%S').log"

    set +e
    playground --output-level ERROR container exec --container "$resolved_container" --command "type jstack" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        if [[ "$environment" == "cfk" ]]
        then
            logwarn "jstack is not available on pod $resolved_container, attaching debug container $debug_image"
            debug_stderr=$(mktemp -t pg-debug-XXXXXXXXXX)
            kubectl -n confluent debug "$resolved_container" --image="$debug_image" --target="$target_container_name" --profile=sysadmin -- bash -lc 'set -e; TARGET_PID=""; for p in /proc/[0-9]*; do if grep -aq "java" "$p/cmdline" 2>/dev/null; then TARGET_PID="${p#/proc/}"; break; fi; done; [ -n "$TARGET_PID" ] || TARGET_PID=1; TARGET_ROOT="/proc/${TARGET_PID}/root"; mkdir -p "${TARGET_ROOT}/tmp/jdk-tools/bin"; JSTACK_BIN="$(command -v jstack)"; JDK_HOME="$(cd "$(dirname "$JSTACK_BIN")/.." && pwd)"; cp "$JSTACK_BIN" "${TARGET_ROOT}/tmp/jdk-tools/bin/"; rm -rf "${TARGET_ROOT}/tmp/jdk-tools/lib"; cp -r "$JDK_HOME/lib" "${TARGET_ROOT}/tmp/jdk-tools/"' > /dev/null 2>"$debug_stderr"
            if [ $? != 0 ]
            then
                logerror "❌ could not prepare jstack tools in pod $resolved_container"
                cat "$debug_stderr"
                rm -f "$debug_stderr"
                exit 1
            fi
            rm -f "$debug_stderr"

            playground --output-level ERROR container exec --container "$resolved_container" --command "test -x /tmp/jdk-tools/bin/jstack" > /dev/null 2>&1
            if [ $? != 0 ]
            then
                logerror "❌ jstack tool copy completed but /tmp/jdk-tools/bin/jstack is missing in pod $resolved_container"
                exit 1
            fi
        else
            logwarn "jstack is not installed on container $container, attempting to install jdk 17"
            playground container change-jdk --version 17

            playground --output-level ERROR container exec --container "$resolved_container" --command "type jstack" > /dev/null 2>&1
            if [ $? != 0 ]
            then
                logerror "❌ jstack could not be installed on container $container"
                exit 1
            fi
        fi
    fi
    set -e
    log "🎯 Taking thread dump on container ${container} for pid 1"
    if [[ "$environment" == "cfk" ]]
    then
        kubectl -n confluent exec "$resolved_container" -c "$target_container_name" -- /bin/sh -c "cd /tmp/jdk-tools && ./bin/jstack 1" > "$filename" 2>&1
    else
        playground --output-level ERROR container exec --container "$resolved_container" --command "jstack 1" > "$filename" 2>&1
    fi
    if [ $? -eq 0 ]
    then
        playground open --file "${filename}"
    else
        logerror "❌ failed to take thread dump"
    fi
done

