test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

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

if [[ $filename == "fully-managed"* ]]
then
    playground ccloud-connector status | grep -v "applying command to all connectors"
    playground ccloud-connector show-config | grep -v "applying command to all connectors"
    playground ccloud-connector show-config-parameters --only-show-file-path | grep -v "applying command to all connectors"
fi

if [[ $last_folder == "connect"* ]]
then
    playground connector versions | grep -v "applying command to all connectors"
    playground connector status | grep -v "applying command to all connectors"
    playground connector show-config | grep -v "applying command to all connectors"
    playground connector show-config-parameters --only-show-file-path | grep -v "applying command to all connectors"
fi

playground topic list