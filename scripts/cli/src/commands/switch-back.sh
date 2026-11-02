environment_before_switch=$(playground state get run.environment_before_switch)
if [ "$environment_before_switch" == "" ]
then
    logerror "switch-ccloud was probably not executed before"
    exit 1
fi
connector_type_before_switch=$(playground state get run.connector_type_before_switch)

if [ "$connector_type_before_switch" != "" ]
then
    log "💺 Switch back to previous environment ($environment_before_switch) with $connector_type_before_switch connector"
else
    log "💺 Switch back to previous environment ($environment_before_switch)"
fi

playground state set run.environment "$environment_before_switch"
playground state del run.environment_before_switch
playground state set run.connector_type "$connector_type_before_switch"
playground state del run.connector_type_before_switch

# nothing is started or stopped: the CLI simply talks to the containers of the last example again
test_file=$(playground state get run.test_file)
if [ -n "$test_file" ]
then
    log "💡 last example: ${test_file#"$root_folder/"}"
fi