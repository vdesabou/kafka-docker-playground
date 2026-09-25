test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

connector_type=$(playground state get run.connector_type)

playground generate-fzf-find-files &
last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))
filename=$(basename $test_file)
last_folder=$(basename $(dirname $test_file))

log "📊 Metrics"
log "🚀 Number of examples ran so far: $(get_cli_metric nb_runs)"
log "👷 Number of repro models created so far: $(get_cli_metric nb_reproduction_models)"

log "🚀 Running example "
echo $last_two_folders/$filename

playground open-docs --only-show-url

get_environment_used
log "🐳 Containers"
if [[ "$environment" == "cfk" ]]
then
    kubectl -n confluent get pods
else
    docker ps -a --filter "label=com.docker.compose.project" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    unhealthy=$(docker ps -a --filter "label=com.docker.compose.project" --format "{{.Names}} ({{.Status}})" | grep -E "Exited|Restarting|Dead|unhealthy" || true)
    if [[ -n "$unhealthy" ]]
    then
        logwarn "💀 some containers are not running or not healthy, check them with 'playground container logs --container <container> --errors':"
        echo "$unhealthy"
    fi
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
then
    playground connector versions | grep -v "applying command to all connectors"
    playground connector open-docs --only-show-url
fi

playground connector status | grep -v "applying command to all connectors"
playground connector show-config | grep -v "applying command to all connectors"
playground connector show-config-parameters --only-show-file-path | grep -v "applying command to all connectors"

playground topic list

check_for_ec2_instance_running