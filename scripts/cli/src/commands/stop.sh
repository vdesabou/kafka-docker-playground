environment=$(playground state get run.environment)
test_file=$(playground state get run.test_file)
cfk_port_forward_pids=$(ps -axo pid=,command= | grep -E '[k]ubectl( |.* )port-forward ' | grep 'confluent' | awk '{print $1}')

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi
export flink_connectors=""
filename=$(basename -- "$test_file")
test_file_directory="$(dirname "${test_file}")"

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

log "🛑 Stopping example $filename in dir $test_file_directory"

if [[ "$environment" == "cfk" ]] || [[ -z "$environment" && -n "$cfk_port_forward_pids" ]]
then
    cfk_stop_script="$root_folder/environment/cfk/stop.sh"
    if [ -f "$cfk_stop_script" ]
    then
        bash "$cfk_stop_script"
    fi

    if [[ -n "$cfk_port_forward_pids" ]]
    then
        log "🔀 Stopping CFK port-forward process(es): $(echo "$cfk_port_forward_pids" | tr '\n' ' ' | sed 's/ *$//')"
        echo "$cfk_port_forward_pids" | xargs kill > /dev/null 2>&1 || true
    else
        log "🔀 No CFK port-forward process found"
    fi
    exit 0
fi

docker_command=$(playground state get run.docker_command)
echo "$docker_command" > $tmp_dir/tmp

sed -e "s|up -d|down -v --remove-orphans|g" \
    $tmp_dir/tmp > $tmp_dir/tmp2

sed -e "s|--quiet-pull||g" \
    $tmp_dir/tmp2 > $tmp_dir/playground-command-stop

bash $tmp_dir/playground-command-stop