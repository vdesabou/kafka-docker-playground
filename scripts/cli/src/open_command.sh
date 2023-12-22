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

editor=$(playground config get editor)
if [ "$editor" != "" ]
then
  log "📖 Opening ${test_file} using configured editor $editor"
  $editor ${test_file}
else
  if [[ $(type code 2>&1) =~ "not found" ]]
  then
    logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
    exit 1
  else
    log "📖 Opening ${test_file} with code (default) - you can change editor by using playground config editor <editor>"
    code ${test_file}
  fi
fi