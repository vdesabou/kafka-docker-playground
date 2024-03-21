IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

environment="${args[--environment]}"
docker_compose_override_file="${args[--docker-compose-override-file]}"
wait_for_control_center="${args[--wait-for-control-center]}"

if [ "$environment" = "ccloud" ]
then
  test_file="$root_folder/ccloud/environment/start.sh"
else
  test_file="$root_folder/environment/$environment/start.sh"
fi
test_file_directory="$(dirname "${test_file}")"

set +e
playground container kill-all
set -e

if [[ -n "$wait_for_control_center" ]]
then
  export WAIT_FOR_CONTROL_CENTER=1
fi

cd $test_file_directory
if [ -f $docker_compose_override_file ]
then
  $test_file "$docker_compose_override_file"
else
  $test_file
fi