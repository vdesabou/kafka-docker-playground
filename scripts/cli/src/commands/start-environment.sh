IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

environment="${args[--environment]}"
tag="${args[--tag]}"
enable_ksqldb="${args[--enable-ksqldb]}"
enable_rest_proxy="${args[--enable-rest-proxy]}"
enable_c3="${args[--enable-control-center]}"
enable_conduktor="${args[--enable-conduktor]}"
enable_multiple_brokers="${args[--enable-multiple-brokers]}"
enable_multiple_connect_workers="${args[--enable-multiple-connect-workers]}"
enable_jmx_grafana="${args[--enable-jmx-grafana]}"
enable_kcat="${args[--enable-kcat]}"
enable_sr_maven_plugin_app="${args[--enable-sr-maven-plugin-app]}"
docker_compose_override_file="${args[--docker-compose-override-file]}"

if [ "$environment" = "ccloud" ]
then
  test_file="$root_folder/ccloud/environment/start.sh"
else
  test_file="$root_folder/environment/$environment/start.sh"
fi
test_file_directory="$(dirname "${test_file}")"

flag_list=""
if [[ -n "$tag" ]]
then
  flag_list="--tag=$tag"
  export TAG=$tag
fi

if [[ -n "$enable_ksqldb" ]]
then
  flag_list="$flag_list --enable-ksqldb"
  export ENABLE_KSQLDB=true
fi

if [[ -n "$enable_rest_proxy" ]]
then
  flag_list="$flag_list --enable-rest-proxy"
  export ENABLE_RESTPROXY=true
fi

if [[ -n "$enable_c3" ]]
then
  flag_list="$flag_list --enable-control-center"
  export ENABLE_CONTROL_CENTER=true
fi

if [[ -n "$enable_conduktor" ]]
then
  flag_list="$flag_list --enable-conduktor"
  export ENABLE_CONDUKTOR=true
fi

if [[ -n "$enable_multiple_brokers" ]]
then
  flag_list="$flag_list --enable-multiple-broker"
  export ENABLE_KAFKA_NODES=true
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  flag_list="$flag_list --enable-multiple-connect-workers"
  export ENABLE_CONNECT_NODES=true

  # determining the docker-compose file from from test_file
  docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
  docker_compose_file="${test_file_directory}/${docker_compose_file}"
  cp $docker_compose_file /tmp/playground-backup-docker-compose.yml
  yq -i '.services.connect2 = .services.connect' /tmp/playground-backup-docker-compose.yml
  yq -i '.services.connect3 = .services.connect' /tmp/playground-backup-docker-compose.yml
  cp /tmp/playground-backup-docker-compose.yml $docker_compose_file
fi

if [[ -n "$enable_jmx_grafana" ]]
then
  flag_list="$flag_list --enable-jmx-grafana"
  export ENABLE_JMX_GRAFANA=true
fi

if [[ -n "$enable_kcat" ]]
then
  flag_list="$flag_list --enable-kcat"
  export ENABLE_KCAT=true
fi

if [[ -n "$enable_sr_maven_plugin_app" ]]
then
  flag_list="$flag_list --enable-sr-maven-plugin-app"
  export ENABLE_SR_MAVEN_PLUGIN_NODE=true
fi

set +e
playground container kill-all
set -e

cd $test_file_directory
if [ -f $docker_compose_override_file ]
then
  $test_file "$docker_compose_override_file" ${other_args[*]}
else
  $test_file ${other_args[*]}
fi