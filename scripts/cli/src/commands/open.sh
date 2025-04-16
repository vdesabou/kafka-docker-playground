test_file="${args[--file]}"
wait="${args[--wait]}"
open_docker_compose="${args[--open-docker-compose]}"

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

do_wait=""
if [[ -n "$wait" ]]
then
  do_wait="wait"
fi

if [[ -n "$open_docker_compose" ]]
then
  # determining the docker-compose file from from test_file
  docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
  test_file_directory="$(dirname "${test_file}")"
  docker_compose_file="${test_file_directory}/${docker_compose_file}"
  if [ ! -f $docker_compose_file ]
  then
    logwarn "--open-docker-compose is set but docker compose file could not be retrieved from $test_file"
  else
    open_file_with_editor "${docker_compose_file}"
  fi

fi

open_file_with_editor "${test_file}" "${do_wait}"