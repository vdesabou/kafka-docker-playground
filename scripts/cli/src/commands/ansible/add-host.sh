hosts="${args[host]}"

hosts_file="$root_folder/environment/ansible/hosts.txt"
inventory_file="$root_folder/environment/ansible/inventory/hosts.yml"
docker_command=$(playground state get run.docker_command)
if [ -z "$docker_command" ]
then
  logerror "❌ no docker compose command saved in playground.ini: start the environment with playground start-environment --environment ansible"
  exit 1
fi

eval "host_array=($hosts)"
for host in "${host_array[@]}"
do
  line=$(grep -v "^#" "$hosts_file" | awk -v h="$host" '$1 == h')
  if [ -z "$line" ]
  then
    logerror "❌ $host is not a host of the ansible environment: $(grep -v '^#' "$hosts_file" | awk '{print $1}' | tr '\n' ' ')"
    exit 1
  fi
  read -r _ group jmx_var jmx_port profile <<< "$line"
  if [ "$group" == "kafka_controller" ] && [ "$(yq '.all.vars.kraft_dynamic_quorum_enabled // false' "$inventory_file")" != "true" ]
  then
    logwarn "⚠️ $host: the KRaft quorum is static (controller.quorum.voters): a controller can only join a dynamic quorum, migrate first (playground ansible playbook --playbook confluent.platform.StaticToDynamicQuorumMigration, see other/cp-ansible-day2/static-to-dynamic-quorum.sh)"
  fi
  if docker inspect -f '{{.State.Running}}' "$host" 2> /dev/null | grep -q true
  then
    logwarn "🤷 $host is already running"
  else
    # the saved docker compose command, with the profile of the host: also what playground stop replays
    if [ "$profile" != "-" ] && [[ "$docker_command" != *"--profile $profile "* ]]
    then
      docker_command="${docker_command/ up -d/ --profile $profile up -d}"
      playground state set run.docker_command "$docker_command"
    fi
    log "🖥️ starting host $host (an empty host: the playbook installs Confluent Platform)"
    log "🔧 $docker_command $host"
    bash -c "$docker_command $host" > /tmp/playground-ansible-add-host.log 2>&1 || { tail -5 /tmp/playground-ansible-add-host.log; logerror "❌ could not start $host"; exit 1; }
  fi
  if [ "$jmx_var" != "-" ]
  then
    log "🔧 yq -i '.all.children.${group}.hosts.${host}.${group}_service_environment_overrides = {\"JMX_PORT\": ${jmx_port}, \"${jmx_var}\": ${jmx_port}}' $inventory_file"
    HOST="$host" GROUP="$group" JMX_VAR="$jmx_var" JMX_PORT="$jmx_port" yq -i -P '.all.children[strenv(GROUP)].hosts[strenv(HOST)][strenv(GROUP) + "_service_environment_overrides"] = {"JMX_PORT": (strenv(JMX_PORT) | tonumber), strenv(JMX_VAR): (strenv(JMX_PORT) | tonumber)}' "$inventory_file"
  else
    HOST="$host" GROUP="$group" yq -i -P '.all.children[strenv(GROUP)].hosts[strenv(HOST)] = (.all.children[strenv(GROUP)].hosts[strenv(HOST)] // null)' "$inventory_file"
  fi
  log "📋 $host added to group $group of the inventory"
done
log "🎓 deploy them with: playground ansible playbook --limit $(echo "${host_array[*]}" | tr ' ' ',')"
