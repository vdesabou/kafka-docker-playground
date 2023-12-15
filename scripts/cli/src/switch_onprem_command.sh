if [ -f /tmp/switch-playground-command ]
then
    log "💺 Switch back to onprem environment"
    mv /tmp/switch-playground-command /tmp/playground-command
else
    logwarn "/tmp/switch-playground-command was not found, switch-ccloud was probably not executed before"
fi

if [ -f /tmp/switch-playground-run ]
then
    mv /tmp/switch-playground-run /tmp/playground-run
else
    logwarn "/tmp/switch-playground-run was not found, switch-ccloud was probably not executed before"
fi

if [ ! -f /tmp/playground-run ]
then
  logerror "File containing re-run command /tmp/playground-run does not exist!"
  logerror "Make sure to use <playground run> command !"
  exit 1
fi

test_file=$(cat /tmp/playground-run | awk '{ print $4}')

if [ ! -f $test_file ]
then 
logerror "File $test_file retrieved from /tmp/playground-run does not exist!"
logerror "Make sure to use <playground run> command !"
exit 1
fi

last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))
filename=$(basename $test_file)
last_folder=$(basename $(dirname $test_file))

log "🚀 Running example "
echo $last_two_folders/$filename