IGNORE_CHECK_FOR_DOCKER_COMPOSE=true

DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
dir1=$(echo ${DIR_CLI%/*})
root_folder=$(echo ${dir1%/*})

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

flag_list=""
if [[ -n "$tag" ]]
then
  flag_list="--tag=$tag"
fi

if [[ -n "$enable_ksqldb" ]]
then
  flag_list="$flag_list --enable-ksqldb"
fi

if [[ -n "$enable_rest_proxy" ]]
then
  flag_list="$flag_list --enable-rest-proxy"
fi

if [[ -n "$enable_c3" ]]
then
  flag_list="$flag_list --enable-control-center"
fi

if [[ -n "$enable_conduktor" ]]
then
  flag_list="$flag_list --enable-conduktor"
fi

if [[ -n "$enable_multiple_brokers" ]]
then
  flag_list="$flag_list --enable-multiple-broker"
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  flag_list="$flag_list --enable-multiple-connect-workers"
fi

if [[ -n "$enable_jmx_grafana" ]]
then
  flag_list="$flag_list --enable-jmx-grafana"
fi

if [[ -n "$enable_kcat" ]]
then
  flag_list="$flag_list --enable-kcat"
fi

if [[ -n "$enable_sr_maven_plugin_app" ]]
then
  flag_list="$flag_list --enable-sr-maven-plugin-app"
fi

if [ "$environment" = "ccloud" ]
then
  test_file="$root_folder/ccloud/environment/start.sh"
else
  test_file="$root_folder/environment/$environment/start.sh"
fi

playground run -f $test_file $flag_list ${other_args[*]}