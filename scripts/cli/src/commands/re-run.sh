test_file=$(playground state get run.test_file)

if [ ! -f $test_file ]
then
  logerror "❌ file $test_file retrieved from $root_folder/playground.ini does not exist!"
  exit 1
fi

playground run -f "$test_file" --force-interactive-re-run