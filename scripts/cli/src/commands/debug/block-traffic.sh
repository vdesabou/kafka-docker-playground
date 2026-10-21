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

install_iptables_if_needed() {
	local container=$1

	if [[ "$environment" == cfk* ]]
	then
		return
	fi

	set +e
	playground --output-level ERROR container exec --container "$container" --command "type iptables" > /dev/null 2>&1
	if [ $? != 0 ]
	then
		tag=$(get_running_cp_tag)
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

for container in "${resolved_container_array[@]}"
do
	install_iptables_if_needed "$container"
done

mapfile -t destination_ips < <(resolve_traffic_destination_ips "$destination")

if [[ ${#destination_ips[@]} -eq 0 ]]
then
	logerror "❌ Unable to determine destination IPs for $destination"
	exit 1
fi

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

for container in "${resolved_container_array[@]}"
do
	log "Applying iptables rule to container: $container"
	for ip in "${destination_ips[@]}"
	do
		if [[ -n "$port" ]]
		then
			if [[ "$environment" == cfk* ]]
			then
					rule_cmd="iptables -${action} OUTPUT -p tcp -d ${ip} --dport ${port} -j DROP"
					check_cmd="iptables -C OUTPUT -p tcp -d ${ip} --dport ${port} -j DROP"
					run_cfk_netshoot_command "$container" "$rule_cmd"
					if [[ "$action" == "A" ]]
					then
						run_cfk_netshoot_command "$container" "$check_cmd"
					fi
			else
				docker exec --privileged --user root ${container} bash -c "iptables -${action} OUTPUT -p tcp -d ${ip} --dport ${port} -j DROP"
			fi
		else
			if [[ "$environment" == cfk* ]]
			then
					rule_cmd="iptables -${action} OUTPUT -d ${ip} -j DROP"
					check_cmd="iptables -C OUTPUT -d ${ip} -j DROP"
					run_cfk_netshoot_command "$container" "$rule_cmd"
					if [[ "$action" == "A" ]]
					then
						run_cfk_netshoot_command "$container" "$check_cmd"
					fi
			else
				docker exec --privileged --user root ${container} bash -c "iptables -${action} OUTPUT -d ${ip} -j DROP"
			fi
		fi
	done

	log "Output of command iptables-save for container $container"
	if [[ "$environment" == cfk* ]]
	then
		run_cfk_netshoot_command "$container" "iptables-save" "true"
	else
		docker exec --privileged --user root ${container} bash -c "iptables-save"
	fi
done
