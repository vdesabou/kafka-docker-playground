if [ ! -f /tmp/playground-run ]
then
  logerror "File containing run command /tmp/playground-run does not exist!"
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
filename=$(basename -- "$test_file")
test_file_directory="$(dirname "${test_file}")"
cd ${test_file_directory}

if [ ! -f $test_file_directory/stop.sh ]
then 
  logerror "File stop.sh in directory $test_file_directory does not exist"
  exit 1
fi

log "🛑 Stopping example $filename in dir $test_file_directory"
bash stop.sh