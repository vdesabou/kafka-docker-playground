test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi
filename=$(basename -- "$test_file")
test_file_directory="$(dirname "${test_file}")"

log "🛑 Stopping example $filename in dir $test_file_directory"
docker_command=$(playground state get run.docker_command)
echo "$docker_command" > /tmp/tmp

sed -e "s|up -d|down -v --remove-orphans|g" \
    /tmp/tmp > /tmp/playground-command-stop

bash /tmp/playground-command-stop