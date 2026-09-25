containers="${args[--container]}"
open="${args[--open]}"
log="${args[--wait-for-log]}"
grep="${args[--grep]}"
max_wait="${args[--max-wait]}"
previous="${args[--previous]}"
since="${args[--since]}"
tail_lines="${args[--tail]}"
no_follow="${args[--no-follow]}"
errors="${args[--errors]}"
include_warnings="${args[--include-warnings]}"
max_findings="${args[--max-findings]}"

get_environment_used

if [[ -n "$tail_lines" ]] && [[ "$tail_lines" != "all" ]] && ! [[ "$tail_lines" =~ ^[0-9]+$ ]]
then
    logerror "❌ --tail must be a number of lines or \"all\", got \"$tail_lines\""
    exit 1
fi

if [[ -n "$errors" ]] && [[ -n "$grep" ]]
then
    logerror "❌ --errors and --grep cannot be used together"
    exit 1
fi

# the digest needs the whole (bounded) log, so it never follows
if [[ -n "$errors" ]]
then
    no_follow=1
fi

if [[ -z "$tail_lines" ]]
then
    if [[ -n "$since" ]] || [[ -n "$errors" ]] || { [[ -n "$grep" ]] && [[ -n "$no_follow" ]]; }
    then
        tail_lines="all"
    else
        tail_lines="200"
    fi
fi

follow_opt=()
if [[ -z "$no_follow" ]]
then
    follow_opt=(-f)
fi

since_opt=()
if [[ -n "$since" ]]
then
    since_opt=(--since "$since")
fi

kubectl_tail="$tail_lines"
if [[ "$kubectl_tail" == "all" ]]
then
    kubectl_tail="-1"
fi

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

# Followed logs of several containers are streamed in parallel; otherwise one after the other
run_in_background=""
if [ ${#container_array[@]} -gt 1 ] && [[ -z "$no_follow" ]]
then
    run_in_background=1
fi

for container in "${container_array[@]}"
do
    resolved_container=$(resolve_container_name_for_environment "$container")

    if [[ -n "$errors" ]]
    then
        log "🔥 ERROR/FATAL digest for $container logs${since:+ since $since}"
        if [[ "$environment" == "cfk" ]]
        then
            maybe_previous=""
            if [[ -n "$previous" ]]
            then
                maybe_previous="--previous"
            fi
            kubectl -n confluent logs "$resolved_container" --all-containers=true $maybe_previous "${since_opt[@]}" --tail="$kubectl_tail" 2>&1 | summarize_log_errors "$max_findings" "$include_warnings"
        else
            docker container logs "${since_opt[@]}" --tail "$tail_lines" "$resolved_container" 2>&1 | summarize_log_errors "$max_findings" "$include_warnings"
        fi
        continue
    fi

    if [[ "$environment" == "cfk" ]]
    then
        maybe_previous=""
        if [[ -n "$previous" ]]
        then
            maybe_previous="--previous"
        fi
        if [[ -n "$open" ]]
        then
            filename="/tmp/${container}-$(date '+%Y-%m-%d-%H-%M-%S').log"
            kubectl -n confluent logs "$resolved_container" --all-containers=true $maybe_previous > "$filename" 2>&1
            if [ $? -eq 0 ]
            then
                playground open --file "${filename}"
            else
                logerror "❌ failed to get logs using kubectl logs $resolved_container"
            fi
        elif [[ -n "$log" ]]
        then
            cur_wait=0
            log "⌛ Waiting up to $max_wait seconds for message $log to be present in $resolved_container pod logs..."
            while true
            do
                kubectl -n confluent logs "$resolved_container" --all-containers=true > /tmp/out.txt 2>&1
                if grep "$log" /tmp/out.txt > /dev/null
                then
                    grep "$log" /tmp/out.txt
                    log "The log is there !"
                    break
                fi
                sleep 10
                cur_wait=$(( cur_wait+10 ))
                if [[ "$cur_wait" -gt "$max_wait" ]]
                then
                    logerror "The logs in $resolved_container pod do not show '$log' after $max_wait seconds:"
                    kubectl -n confluent logs "$resolved_container" --all-containers=true --tail=100
                    exit 1
                fi
            done
        elif [[ -n "$grep" ]]
        then
            if [[ -n "$run_in_background" ]]; then
                kubectl -n confluent logs --tail="$kubectl_tail" "${since_opt[@]}" $maybe_previous "${follow_opt[@]}" "$resolved_container" 2>&1 | grep --line-buffered "$grep" | sed "s/^/[$container] /" &
            elif [ ${#container_array[@]} -gt 1 ]; then
                kubectl -n confluent logs --tail="$kubectl_tail" "${since_opt[@]}" $maybe_previous "${follow_opt[@]}" "$resolved_container" 2>&1 | grep --line-buffered "$grep" | sed "s/^/[$container] /"
            else
                kubectl -n confluent logs --tail="$kubectl_tail" "${since_opt[@]}" $maybe_previous "${follow_opt[@]}" "$resolved_container" 2>&1 | grep --line-buffered "$grep"
            fi
        else
            if [[ -n "$run_in_background" ]]; then
                kubectl -n confluent logs --tail="$kubectl_tail" "${since_opt[@]}" $maybe_previous "${follow_opt[@]}" "$resolved_container" 2>&1 | sed "s/^/[$container] /" &
            elif [ ${#container_array[@]} -gt 1 ]; then
                kubectl -n confluent logs --tail="$kubectl_tail" "${since_opt[@]}" $maybe_previous "${follow_opt[@]}" "$resolved_container" 2>&1 | sed "s/^/[$container] /"
            else
                kubectl -n confluent logs --tail="$kubectl_tail" "${since_opt[@]}" $maybe_previous "${follow_opt[@]}" "$resolved_container"
            fi
        fi
        continue
    fi

    if [[ -n "$previous" ]]
    then
        logwarn "--previous is not supported for container logs, only for pod logs"
    fi
    if [[ -n "$open" ]]
    then
        filename="/tmp/${container}-$(date '+%Y-%m-%d-%H-%M-%S').log"
        docker container logs "$resolved_container" > "$filename" 2>&1
        if [ $? -eq 0 ]
        then
            playground open --file "${filename}"
        else
            logerror "❌ failed to get logs using container logs $container"
        fi
    elif [[ -n "$log" ]]
    then
        wait_for_log "$log" "$resolved_container" "$max_wait"
    elif [[ -n "$grep" ]]
    then
        if [[ -n "$run_in_background" ]]; then
            # For multiple containers, filter and prefix each stream in parallel.
            docker container logs --tail "$tail_lines" "${since_opt[@]}" "${follow_opt[@]}" "$resolved_container" 2>&1 | grep --line-buffered "$grep" | sed "s/^/[$container] /" &
        elif [ ${#container_array[@]} -gt 1 ]; then
            docker container logs --tail "$tail_lines" "${since_opt[@]}" "${follow_opt[@]}" "$resolved_container" 2>&1 | grep --line-buffered "$grep" | sed "s/^/[$container] /"
        else
            docker container logs --tail "$tail_lines" "${since_opt[@]}" "${follow_opt[@]}" "$resolved_container" 2>&1 | grep --line-buffered "$grep"
        fi
    else
        if [[ -n "$run_in_background" ]]; then
            # Add container prefix to distinguish logs from different containers
            docker container logs --tail "$tail_lines" "${since_opt[@]}" "${follow_opt[@]}" "$resolved_container" 2>&1 | sed "s/^/[$container] /" &
        elif [ ${#container_array[@]} -gt 1 ]; then
            docker container logs --tail "$tail_lines" "${since_opt[@]}" "${follow_opt[@]}" "$resolved_container" 2>&1 | sed "s/^/[$container] /"
        else
            # For single container, use normal behavior without prefix
            docker container logs --tail "$tail_lines" "${since_opt[@]}" "${follow_opt[@]}" "$resolved_container"
        fi
    fi
done

# If multiple containers were followed in parallel, wait for all background processes
if [[ -n "$run_in_background" ]]; then
    wait
fi
