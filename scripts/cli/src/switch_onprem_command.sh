log "💺 Switch back to onprem environment"
set +e
playground state get run.environment_before_switch > /dev/null 2>&1
if [ $? -ne 0 ]
then
    logerror "switch-ccloud was probably not executed before"
    exit 1
fi
set -e

playground state set run.environment "$(playground state get run.environment_before_switch)"
playground state del run.environment_before_switch

test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
    exit 1
fi

last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))
filename=$(basename $test_file)
last_folder=$(basename $(dirname $test_file))

log "🚀 Running example "
echo $last_two_folders/$filename