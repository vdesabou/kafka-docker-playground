containers="${args[--container]}"
port="${args[--port]}"
destination="${args[--destination]}"
action="${args[--action]}"
both_ways="${args[--both-ways]}"
duration="${args[--duration]}"
isolate="${args[--isolate]}"

get_environment_used

if [[ -z "$destination" && -z "$isolate" ]]
then
	logerror "❌ --destination or --isolate is required"
	exit 1
fi
if [[ -n "$isolate" && "$environment" == cfk* ]]
then
	logerror "❌ --isolate is not supported with cfk (the pods are on the network of the Kubernetes cluster): use --destination with each pod to cut"
	exit 1
fi
if [[ -n "$isolate" && -n "$port" ]]
then
	logerror "❌ --isolate cuts all the traffic with the other containers: --port does not apply"
	exit 1
fi
duration_seconds=""
if [[ -n "$duration" ]]
then
	if [[ "$action" != "start" ]]
	then
		logerror "❌ --duration only applies to --action start (the traffic heals by itself after it)"
		exit 1
	fi
	if [[ ! "$duration" =~ ^([0-9]+)([smh]?)$ ]] || [[ "${BASH_REMATCH[1]}" -eq 0 ]]
	then
		logerror "❌ --duration $duration: use a number of seconds, minutes or hours (30s, 2m, 1h)"
		exit 1
	fi
	case "${BASH_REMATCH[2]}" in
		m) duration_seconds=$(( BASH_REMATCH[1] * 60 )) ;;
		h) duration_seconds=$(( BASH_REMATCH[1] * 3600 )) ;;
		*) duration_seconds=${BASH_REMATCH[1]} ;;
	esac
fi

# --isolate: the container to isolate replaces --container
if [[ -n "$isolate" ]]
then
	containers="$isolate"
fi

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

# run one iptables command in the network namespace of a container (pod with cfk)
run_iptables() {
	local container=$1
	local cmd=$2
	if [[ "$environment" == cfk* ]]
	then
		run_cfk_netshoot_command "$container" "$cmd"
	else
		docker exec --privileged --user root ${container} bash -c "$cmd"
	fi
}

# add (A) or delete (D) a rule of --both-ways or --isolate. A delete is skipped when the rule is not there, so that
# --action stop works whether the start used these flags or not, and a timer that fires after a manual stop is
# harmless. An add is skipped when the rule is already there (--isolate run twice)
apply_extra_rule() {
	local container=$1
	local op=$2
	local rule=$3
	set +e
	run_iptables "$container" "iptables -C $rule" > /dev/null 2>&1
	local present=$?
	set -e
	if [[ "$op" == "A" && $present -ne 0 ]] || [[ "$op" == "D" && $present -eq 0 ]]
	then
		run_iptables "$container" "iptables -${op} $rule"
	fi
}

# the rules of --both-ways are also removed by a stop without the flag, except with cfk, where each check is a
# kubectl debug call: there, pass --both-ways to the stop too
with_both_ways_rules=""
if [[ -n "$both_ways" ]] || [[ "$action" == "stop" && "$environment" != cfk* ]]
then
	with_both_ways_rules=1
fi

# the timers of --duration: one detached process per block, which runs the stop at the end
timer_dir="/tmp/playground-block-traffic"
timer_key=$(echo "$root_folder|${resolved_container_array[*]}|${destination}|${isolate}|${port}" | cksum | awk '{print $1}')
timer_info="$timer_dir/$timer_key.info"

cancel_timer() {
	local reason=$1
	[[ -f "$timer_info" ]] || return 0
	local timer_pid
	timer_pid=$(sed -n 's/^pid=//p' "$timer_info" | head -1)
	# the timer itself runs the stop: it must not kill itself
	if [[ -z "$PG_BLOCK_TRAFFIC_TIMER" && -n "$timer_pid" ]] && kill -0 "$timer_pid" 2> /dev/null
	then
		kill_tree "$timer_pid"
		log "⏹️ timer of --duration cancelled ($reason, pid $timer_pid)"
	fi
	rm -f "$timer_info"
}

for container in "${resolved_container_array[@]}"
do
	install_iptables_if_needed "$container"
done

destination_ips=()
ip_display=""
if [[ -n "$destination" ]]
then
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
fi

# --isolate: the networks of the container (ip/prefix and gateway, also with podman)
isolate_networks=()
isolate_display=""
if [[ -n "$isolate" ]]
then
	mapfile -t isolate_networks < <(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}/{{.IPPrefixLen}} {{.Gateway}}{{"\n"}}{{end}}' "${resolved_container_array[0]}" 2> /dev/null | awk 'NF && $1 !~ /^\//')
	if [[ ${#isolate_networks[@]} -eq 0 ]]
	then
		logerror "❌ could not find the networks of container $isolate (docker inspect)"
		exit 1
	fi
	for network in "${isolate_networks[@]}"
	do
		read -r cidr gateway <<< "$network"
		isolate_display+="${cidr}${gateway:+ (gateway $gateway)}, "
	done
	isolate_display=${isolate_display%, }
fi

case "${action}" in
	start)
		action="A"
		if [[ -n "$isolate" ]]
		then
			log "🏝️ Isolating container ${isolate} from the other containers of its network(s): ${isolate_display}"
			log "   still working: loopback, the docker DNS, the gateway (the host, published ports) and the internet"
		elif [[ -n "$both_ways" ]]
		then
			if [[ -n "$port" ]]
			then
				log "🚫 Blocking traffic both ways between containers ${containers} and destination ${destination} (${ip_display}) on port ${port}"
			else
				log "🚫 Blocking traffic both ways between containers ${containers} and destination ${destination} (${ip_display}), all ports"
			fi
		elif [[ -n "$port" ]]
		then
			log "🚫 Blocking traffic on containers ${containers} and port ${port} for destination ${destination} (${ip_display})"
		else
			log "🚫 Blocking traffic on containers ${containers} for all ports for destination ${destination} (${ip_display})"
		fi
	;;
	stop)
		action="D"
		cancel_timer "--action stop"
		if [[ -n "$isolate" ]]
		then
			log "🟢 Ending the isolation of container ${isolate}: ${isolate_display}"
		elif [[ -n "$port" ]]
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
	if [[ -n "$isolate" ]]
	then
		# the accepts first, then the drops: loopback (the container talking to itself, the docker DNS on
		# 127.0.0.11), the gateway (the host, published ports, the route to the internet), then every other address
		# of its subnets, in both directions
		extra_rules=("OUTPUT -o lo -j ACCEPT" "INPUT -i lo -j ACCEPT")
		for network in "${isolate_networks[@]}"
		do
			read -r cidr gateway <<< "$network"
			if [[ -n "$gateway" ]]
			then
				extra_rules+=("OUTPUT -d ${gateway} -j ACCEPT" "INPUT -s ${gateway} -j ACCEPT")
			fi
			extra_rules+=("OUTPUT -d ${cidr} -j DROP" "INPUT -s ${cidr} -j DROP")
		done
		if [[ "$action" == "D" ]]
		then
			# the drops first, so that no accept is removed while its drop is still there
			for (( i=${#extra_rules[@]}-1; i>=0; i-- ))
			do
				apply_extra_rule "$container" "D" "${extra_rules[$i]}"
			done
		else
			for rule in "${extra_rules[@]}"
			do
				apply_extra_rule "$container" "A" "$rule"
			done
		fi
	else
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
				# --both-ways: the packets from the destination on that port (the replies of the connections to it),
				# and the connections of the destination to the same port of the container
				if [[ -n "$with_both_ways_rules" ]]
				then
					for rule in "INPUT -p tcp -s ${ip} --sport ${port} -j DROP" "INPUT -p tcp -s ${ip} --dport ${port} -j DROP" "OUTPUT -p tcp -d ${ip} --sport ${port} -j DROP"
					do
						apply_extra_rule "$container" "$action" "$rule"
					done
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
				# --both-ways: nothing from the destination reaches the container either
				if [[ -n "$with_both_ways_rules" ]]
				then
					apply_extra_rule "$container" "$action" "INPUT -s ${ip} -j DROP"
				fi
			fi
		done
	fi

	log "Output of command iptables-save for container $container"
	if [[ "$environment" == cfk* ]]
	then
		run_cfk_netshoot_command "$container" "iptables-save" "true"
	else
		docker exec --privileged --user root ${container} bash -c "iptables-save"
	fi
done

# --duration: a detached process runs the stop at the end (cancelled by an earlier --action stop or 'playground stop')
if [[ "$action" == "A" && -n "$duration_seconds" ]]
then
	cancel_timer "replaced by a new --duration"
	mkdir -p "$timer_dir"
	stop_args=(debug block-traffic --action stop)
	if [[ -n "$isolate" ]]
	then
		stop_args+=(--isolate "$isolate")
	else
		for container in "${container_array[@]}"
		do
			stop_args+=(--container "$container")
		done
		stop_args+=(--destination "$destination")
		[[ -n "$port" ]] && stop_args+=(--port "$port")
		[[ -n "$both_ways" ]] && stop_args+=(--both-ways)
	fi
	PG_BLOCK_TRAFFIC_TIMER=1 nohup bash -c 'sleep "$1"; shift; "$@"' playground-block-traffic-timer "$duration_seconds" "$root_folder/scripts/cli/playground" "${stop_args[@]}" > "$timer_dir/$timer_key.log" 2>&1 < /dev/null &
	timer_pid=$!
	disown "$timer_pid" 2> /dev/null || true
	heal_epoch=$(( $(date +%s) + duration_seconds ))
	heal_at=$(date -r "$heal_epoch" '+%H:%M:%S' 2> /dev/null || date -d "@$heal_epoch" '+%H:%M:%S')
	cat > "$timer_info" << EOF
root_folder=$root_folder
pid=$timer_pid
heal_at=$heal_at
command=playground ${stop_args[*]}
EOF
	log "⏳ the traffic heals by itself in ${duration}, at ${heal_at} (timer pid ${timer_pid}, log $timer_dir/$timer_key.log)"
	log "   --action stop with the same flags ends it now, playground stop ends it with the environment"
fi
