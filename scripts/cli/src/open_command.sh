test_file="${args[--file]}"

if [[ -n "$test_file" ]]
then
  if [[ $test_file == *"@"* ]]
  then
    test_file=$(echo "$test_file" | cut -d "@" -f 2)
  fi
else
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
fi

if config_has_key "editor"
then
  editor=$(config_get "editor")
  log "📖 Opening ${test_file} using configured editor $editor"
  $editor ${test_file}
else
  if [[ $(type code 2>&1) =~ "not found" ]]
  then
    logerror "Could not determine an editor to use as default code is not found - you can change editor by updating config.ini"
    exit 1
  else
    log "📖 Opening ${test_file} with code (default) - you can change editor by updating config.ini"
    code ${test_file}
  fi
fi