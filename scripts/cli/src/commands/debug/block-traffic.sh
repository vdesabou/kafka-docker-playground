containers="${args[--container]}"
port="${args[--port]}"
destination="${args[--destination]}"
action="${args[--action]}"

get_environment_used

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"
resolved_container_array=()
for container in "${container_array[@]}"
do
    resolved_container_array+=("$(resolve_container_name_for_environment "$container")")
done

ip_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

run_cfk_netfilter_command() {
    local pod_name=$1
    local cmd=$2
    local emit_output=${3:-false}
    local target_container
    local debug_output
    local cleaned_output
    local debug_exit_code

    target_container=$(kubectl -n confluent get pod "$pod_name" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
    if [[ -z "$target_container" ]]
    then
        logerror "❌ Could not resolve target container for pod $pod_name"
        exit 1
    fi

    debug_output=$(kubectl -n confluent debug "pod/$pod_name" --profile=sysadmin --image=nicolaka/netshoot --target="$target_container" -- bash -lc "$cmd" 2>&1)
    debug_exit_code=$?
    cleaned_output=$(echo "$debug_output" | sed -E '/^Targeting container /d; /^Defaulting debug container name to /d')
    if [ $debug_exit_code -ne 0 ]
    then
        logerror "❌ failed to execute netfilter command on pod $pod_name"
        if [[ -n "$cleaned_output" ]]
        then
            echo "$cleaned_output"
        else
            echo "$debug_output"
        fi
        exit 1
    fi

    if [[ "$emit_output" == "true" ]]
    then
        if [[ -n "$cleaned_output" ]]
        then
            echo "$cleaned_output"
        else
            log "(no output from: $cmd)"
        fi
    fi
}

# Function to install iptables on a container if needed
install_iptables_if_needed() {
    local container=$1

    if [[ "$environment" == "cfk" ]]
    then
        # CFK uses kubectl debug with sysadmin profile, which carries iptables capabilities.
        return
    fi

    set +e
    playground --output-level ERROR container exec --container "$container" --command "type iptables" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        tag=$(docker ps --format '{{.Image}}' | grep -E 'confluentinc/cp-.*-connect.*:' | awk -F':' '{print $2}')
        if [ $? != 0 ] || [ "$tag" == "" ]
        then
            logerror "Could not find current CP version from docker ps"
            exit 1
        fi
        logwarn "iptables is not installed on container $container, attempting to install it"
        if [[ "$tag" == *ubi8 ]] || version_gt $tag "5.9.0"
        then
          docker exec --privileged --user root $container bash -c "yum -y install --disablerepo='Confluent*' iptables"
        else
          docker exec --privileged --user root $container bash -c "apt-get update && echo iptables | xargs -n 1 apt-get install --force-yes -y && rm -rf /var/lib/apt/lists/*"
        fi
    fi
    playground --output-level ERROR container exec --container "$container" --command "type iptables" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        logerror "❌ iptables could not be installed on container $container"
        exit 1
    fi
    set -e
}

# Install iptables on all containers if needed
for container in "${resolved_container_array[@]}"
do
    install_iptables_if_needed "$container"
done

function get_container_ip() {
    if [[ "$environment" == "cfk" ]]
    then
        local pod_ip
        pod_ip=$(kubectl -n confluent get pod "$1" -o jsonpath='{.status.podIP}' 2>/dev/null)
        if [[ -n "$pod_ip" ]]
        then
            echo "$pod_ip"
            return
        fi

        local service_ip
        service_ip=$(kubectl -n confluent get svc "$1" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
        if [[ -n "$service_ip" && "$service_ip" != "None" && "$service_ip" != "none" ]]
        then
            echo "$service_ip"
        fi
    else
        local container_ip
        container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1" 2>/dev/null)
        if [ $? -eq 0 ]
        then
            echo "$container_ip"
        fi
    fi
}

function get_service_endpoint_ips() {
    if [[ "$environment" != "cfk" ]]
    then
        return
    fi

    kubectl -n confluent get endpoints "$1" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -E "$ip_pattern" || true
}

function get_ips_by_nslookup() {
    nslookup "$1" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E "$ip_pattern" || true
}

destination_ips=()
if [[ $destination =~ $ip_pattern ]]
then
    destination_ips+=("$destination")
else
    ip_address=$(get_container_ip "$destination")
    if [[ -n $ip_address ]]
    then
        destination_ips+=("$ip_address")
    else
        log "🌐 Using nslookup to get IP address..."
        mapfile -t service_endpoint_ips < <(get_service_endpoint_ips "$destination")
        if [[ ${#service_endpoint_ips[@]} -gt 0 ]]
        then
            destination_ips=("${service_endpoint_ips[@]}")
        else
            mapfile -t nslookup_ips < <(get_ips_by_nslookup "$destination")
            if [[ ${#nslookup_ips[@]} -gt 0 ]]
            then
                destination_ips=("${nslookup_ips[@]}")
            else
                logerror "❌ Unable to retrieve IP address for $destination using service endpoints/nslookup"
                exit 1
            fi
        fi
    fi
fi

if [[ ${#destination_ips[@]} -eq 0 ]]
then
    logerror "❌ Unable to determine destination IPs for $destination"
    exit 1
fi

# Deduplicate destination IPs while preserving first-seen order.
deduped_destination_ips=()
for ip in "${destination_ips[@]}"
do
    if [[ ! " ${deduped_destination_ips[*]} " =~ " ${ip} " ]]
    then
        deduped_destination_ips+=("$ip")
    fi
done
destination_ips=("${deduped_destination_ips[@]}")

ip_display=$(printf "%s " "${destination_ips[@]}")
ip_display=${ip_display% }

case "${action}" in
    start)
        action="A"
        if [[ -n "$port" ]]
        then
            log "🚫 Blocking traffic on containers ${containers} and port ${port} for destination ${destination} (${ip_display})"
        else
            log "🚫 Blocking traffic on containers ${containers} for all ports for destination ${destination} (${ip_display})"
        fi
    ;;
    stop)
        action="D"

        if [[ -n "$port" ]]
        then
            log "🟢 Unblocking traffic on containers ${containers} and port ${port} for destination ${destination} (${ip_display})"
        else
            log "🟢 Unblocking traffic on containers ${containers} for all ports from destination ${destination} (${ip_display})"
        fi
    ;;
    *)
        logerror "should not happen"
        exit 1
    ;;
esac

# Apply iptables rules to all containers
for container in "${resolved_container_array[@]}"
do
    log "Applying iptables rule to container: $container"
    for ip in "${destination_ips[@]}"
    do
        if [[ -n "$port" ]]
        then
            if [[ "$environment" == "cfk" ]]
            then
                run_cfk_netfilter_command "$container" "iptables -${action} INPUT -p tcp -s ${ip} --sport ${port} -j DROP"
            else
                docker exec --privileged --user root ${container} bash -c "iptables -${action} INPUT -p tcp -s ${ip} --sport ${port} -j DROP"
            fi
        else
            if [[ "$environment" == "cfk" ]]
            then
                run_cfk_netfilter_command "$container" "iptables -${action} INPUT -p tcp -s ${ip} -j DROP"
            else
                docker exec --privileged --user root ${container} bash -c "iptables -${action} INPUT -p tcp -s ${ip} -j DROP"
            fi
        fi
    done

    log "Output of command iptables-save for container $container"
    if [[ "$environment" == "cfk" ]]
    then
        run_cfk_netfilter_command "$container" "iptables-save" "true"
    else
        docker exec --privileged --user root ${container} bash -c "iptables-save"
    fi
done
