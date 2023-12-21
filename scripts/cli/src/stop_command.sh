test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then 
    logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
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