containers="${args[--container]}"
live="${args[--live]}"
histo="${args[--histo]}"
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

set +e

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

for container in "${container_array[@]}"
do
    resolved_container=$(resolve_container_name_for_environment "$container")
    target_container_name=$(get_cfk_target_container_name "$container")

    playground --output-level ERROR container exec --container "$resolved_container" --command "type jmap" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        if [[ "$environment" == "cfk" ]]
        then
            logwarn "jmap is not available on pod $resolved_container, attaching debug container $debug_image"
            debug_stderr=$(mktemp -t pg-debug-XXXXXXXXXX)
            kubectl -n confluent debug "$resolved_container" --image="$debug_image" --target="$target_container_name" --profile=sysadmin -- bash -lc 'set -e; TARGET_PID=""; for p in /proc/[0-9]*; do if grep -aq "java" "$p/cmdline" 2>/dev/null; then TARGET_PID="${p#/proc/}"; break; fi; done; [ -n "$TARGET_PID" ] || TARGET_PID=1; TARGET_ROOT="/proc/${TARGET_PID}/root"; mkdir -p "${TARGET_ROOT}/tmp/jdk-tools/bin"; JMAP_BIN="$(command -v jmap)"; JDK_HOME="$(cd "$(dirname "$JMAP_BIN")/.." && pwd)"; cp "$JMAP_BIN" "${TARGET_ROOT}/tmp/jdk-tools/bin/"; rm -rf "${TARGET_ROOT}/tmp/jdk-tools/lib"; cp -r "$JDK_HOME/lib" "${TARGET_ROOT}/tmp/jdk-tools/"' > /dev/null 2>"$debug_stderr"
            if [ $? != 0 ]
            then
                logerror "❌ could not prepare jmap tools in pod $resolved_container"
                cat "$debug_stderr"
                rm -f "$debug_stderr"
                exit 1
            fi
            rm -f "$debug_stderr"

            playground --output-level ERROR container exec --container "$resolved_container" --command "test -x /tmp/jdk-tools/bin/jmap" > /dev/null 2>&1
            if [ $? != 0 ]
            then
                logerror "❌ jmap tool copy completed but /tmp/jdk-tools/bin/jmap is missing in pod $resolved_container"
                exit 1
            fi
        else
            logwarn "jmap is not installed on container $container, attempting to install jdk 17"
            playground container change-jdk --version 17

            playground --output-level ERROR container exec --container "$resolved_container" --command "type jmap" > /dev/null 2>&1
            if [ $? != 0 ]
            then
                logerror "❌ jmap could not be installed on container $container"
                exit 1
            fi
        fi
    fi

    if [[ -n "$histo" ]]
    then
        filename="heap-dump-$container-histo-$(date '+%Y-%m-%d-%H-%M-%S').txt"
        set -e
        if [[ -n "$live" ]]
        then
            log "📊 Taking histo (with live option) heap dump on container ${container}"
            if [[ "$environment" == "cfk" ]]
            then
                kubectl -n confluent exec "$resolved_container" -c "$target_container_name" -- /bin/sh -c "cd /tmp/jdk-tools && ./bin/jmap -histo:live 1" > /tmp/${filename}
            else
                playground --output-level ERROR container exec --container "$resolved_container" --command "jmap -histo:live 1" > /tmp/${filename}
            fi
        else
            log "📊 Taking histo (without live option) heap dump on container ${container}"
            if [[ "$environment" == "cfk" ]]
            then
                kubectl -n confluent exec "$resolved_container" -c "$target_container_name" -- /bin/sh -c "cd /tmp/jdk-tools && ./bin/jmap -histo 1" > /tmp/${filename}
            else
                playground --output-level ERROR container exec --container "$resolved_container" --command "jmap -histo 1" > /tmp/${filename}
            fi
        fi
        if [ $? -eq 0 ]
        then
            log "👻 heap dump is available at /tmp/${filename}"
        else
            logerror "❌ Failed to take heap dump"
        fi
    else
        filename="heap-dump-$container-$(date '+%Y-%m-%d-%H-%M-%S').hprof"
        set -e
        if [[ -n "$live" ]]
        then
            log "🎯 Taking heap dump (with live option) on container ${container}"
            if [[ "$environment" == "cfk" ]]
            then
                kubectl -n confluent exec "$resolved_container" -c "$target_container_name" -- /bin/sh -c "cd /tmp/jdk-tools && ./bin/jmap -dump:live,format=b,file=/tmp/${filename} 1"
            else
                playground --output-level ERROR container exec --container "$resolved_container" --command "jmap -dump:live,format=b,file=/tmp/${filename} 1"
            fi
        else
            log "🎯 Taking heap dump (without live option) on container ${container}"
            if [[ "$environment" == "cfk" ]]
            then
                kubectl -n confluent exec "$resolved_container" -c "$target_container_name" -- /bin/sh -c "cd /tmp/jdk-tools && ./bin/jmap -dump:format=b,file=/tmp/${filename} 1"
            else
                playground --output-level ERROR container exec --container "$resolved_container" --command "jmap -dump:format=b,file=/tmp/${filename} 1"
            fi
        fi
        if [ $? -eq 0 ]
        then
            log "👻 heap dump is available at ${filename}"
            playground container cp --source ${resolved_container}:/tmp/${filename} --destination ${filename}
        else
            logerror "❌ Failed to take heap dump"
        fi
    fi
done