containers="${args[--container]}"
port="${args[--port]}"
destination="${args[--destination]}"
action="${args[--action]}"

# Convert space-separated string to array
IFS=' ' read -ra container_array <<< "$containers"

# Function to install iptables on a container if needed
install_iptables_if_needed() {
    local container=$1
    set +e
    docker exec $container type iptables > /dev/null 2>&1
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
    docker exec $container type iptables > /dev/null 2>&1
    if [ $? != 0 ]
    then
        logerror "❌ iptables could not be installed on container $container"
        exit 1
    fi
    set -e
}

# Install iptables on all containers if needed
for container in "${container_array[@]}"
do
    install_iptables_if_needed "$container"
done

ip_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

function get_container_ip() {
    local container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1")
    if [ $? -eq 0 ]
    then
        echo "$container_ip"
    fi
}

function get_ip_by_nslookup() {
    local ip_address=$(nslookup "$1" | awk '/^Address: / { print $2 }')
    if [ $? -eq 0 ]
    then
        echo "$ip_address"
    fi
}

ip=""
if [[ $destination =~ $ip_pattern ]]
then
    ip=$destination
else
    ip_address=$(get_container_ip "$destination")
    if [[ -n $ip_address ]]
    then
        ip=$ip_address
    else
        log "🌐 Using nslookup to get IP address..."
        ip_address=$(get_ip_by_nslookup "$destination")
        if [[ -n $ip_address ]]
        then
            ip=$ip_address
        else
            logerror "❌ Unable to retrieve IP address for $destination using nslookup"
            exit 1
        fi
    fi
fi

case "${action}" in
    start)
        action="A"
        if [[ -n "$port" ]]
        then
            log "🚫 Blocking traffic on containers ${containers} and port ${port} for destination ${destination} (${ip})"
        else
            log "🚫 Blocking traffic on containers ${containers} for all ports for destination ${destination} (${ip})"
        fi
    ;;
    stop)
        action="D"

        if [[ -n "$port" ]]
        then
            log "🟢 Unblocking traffic on containers ${containers} and port ${port} for destination ${destination} (${ip})"
        else
            log "🟢 Unblocking traffic on containers ${containers} for all ports from destination ${destination} (${ip})"
        fi
    ;;
    *)
        logerror "should not happen"
        exit 1
    ;;
esac

# Apply iptables rules to all containers
for container in "${container_array[@]}"
do
    log "Applying iptables rule to container: $container"
    if [[ -n "$port" ]]
    then
      docker exec --privileged --user root ${container} bash -c "iptables -${action} INPUT -p tcp -s ${ip} --sport ${port} -j DROP"
    else
      docker exec --privileged --user root ${container} bash -c "iptables -${action} INPUT -p tcp -s ${ip} -j DROP"
    fi
    
    log "Output of command iptables-save for container $container"
    docker exec --privileged --user root ${container} bash -c "iptables-save"
done
