test_file="${args[--file]}"

if [[ -n "$test_file" ]]
then
  if [[ $test_file == *"@"* ]]
  then
    test_file=$(echo "$test_file" | cut -d "@" -f 2)
  fi
else
  test_file=$(playground state get run.test_file)

  if [ ! -f $test_file ]
  then 
      logerror "File $test_file retrieved from $root_folder/playground.ini does not exist!"
      exit 1
  fi
fi

open_file_with_editor "${test_file}"