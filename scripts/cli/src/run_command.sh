DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

test_file="${args[--file]}"
tag="${args[--tag]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"
connector_jar="${args[--connector-jar]}"
disable_ksqldb="${args[--disable-ksqldb]}"
disable_c3="${args[--disable-control-center]}"
enable_conduktor="${args[--enable-conduktor]}"
enable_multiple_brokers="${args[--enable-multiple-brokers]}"
enable_multiple_connect_workers="${args[--enable-multiple-connect-workers]}"
enable_jmx_grafana="${args[--enable-jmx-grafana]}"
enable_kcat="${args[--enable-kcat]}"
enable_sr_maven_plugin_app="${args[--enable-sr-maven-plugin-app]}"

if [ "$test_file" = "" ]
then
  logerror "ERROR: test_file is not provided as argument!"
  exit 1
fi

if [ ! -f "$test_file" ]
then
  logerror "ERROR: test_file $test_file does not exist!"
  exit 1
fi

if [[ "$test_file" != *".sh" ]]
then
  logerror "ERROR: test_file $test_file is not a .sh file!"
  exit 1
fi

test_file_directory="$(dirname "${test_file}")"

# determining the docker-compose file from from test_file
docker_compose_file=$(grep "environment" "$test_file" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | tail -n1 | xargs)

if [ "${docker_compose_file}" != "" ] && [ ! -f "${test_file_directory}/${docker_compose_file}" ]
then
  docker_compose_file=""
  logwarn "📁 Could not determine docker-compose override file from $test_file !"
fi

filename=$(basename -- "$test_file")
extension="${filename##*.}"

base1="${test_file_directory##*/}" # connect-cdc-oracle12-source
dir1="${test_file_directory%/*}" #connect
dir2="${dir1##*/}/$base1" # connect/connect-cdc-oracle12-source
final_dir=$(echo $dir2 | tr '/' '-') # connect-connect-cdc-oracle12-source

environment_variables_list=""
if [[ -n "$tag" ]]
then
  environment_variables_list="TAG=$tag"
  export TAG=$tag
fi

if [[ -n "$connector_tag" ]]
then
  environment_variables_list="$environment_variables_list CONNECTOR_TAG=$connector_tag"
  export CONNECTOR_TAG=$connector_tag
fi

if [[ -n "$connector_zip" ]]
then
  environment_variables_list="$environment_variables_list CONNECTOR_ZIP=$connector_zip"
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  environment_variables_list="$environment_variables_list CONNECTOR_JAR=$connector_jar"
  export CONNECTOR_JAR=$connector_jar
fi

if [[ -n "$disable_ksqldb" ]]
then
  environment_variables_list="$environment_variables_list DISABLE_KSQLDB=true"
  export DISABLE_KSQLDB=true
fi

if [[ -n "$disable_c3" ]]
then
  environment_variables_list="$environment_variables_list DISABLE_CONTROL_CENTER=true"
  export DISABLE_CONTROL_CENTER=true
fi

if [[ -n "$enable_conduktor" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_CONDUKTOR=true"
  export ENABLE_CONDUKTOR=true
fi

if [[ -n "$enable_multiple_brokers" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_KAFKA_NODES=true"
  export ENABLE_KAFKA_NODES=true
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_CONNECT_NODES=true"
  export ENABLE_CONNECT_NODES=true
fi

if [[ -n "$enable_jmx_grafana" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_JMX_GRAFANA=true"
  export ENABLE_JMX_GRAFANA=true
fi

if [[ -n "$enable_kcat" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_KCAT=true"
  export ENABLE_KCAT=true
fi

if [[ -n "$enable_sr_maven_plugin_app" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_SR_MAVEN_PLUGIN_NODE=true"
  export ENABLE_SR_MAVEN_PLUGIN_NODE=true
fi

if [ ! -z $EDITOR ]
then
  log "📖 Opening ${test_file} using EDITOR environment variable"
  $EDITOR ${test_file}
else
  if [[ $(type code 2>&1) =~ "not found" ]]
  then
    logerror "Could not determine an editor to use, you can set EDITOR environment variable with your preferred choice"
    exit 1
  else
    log "📖 Opening ${test_file} with code (you can change editor by setting EDITOR environment variable)"
    code ${test_file}
  fi
fi

if [ "$environment_variables_list" != "" ]
then
  log "🚀 Running example with $environment_variables_list ?"
else
  log "🚀 Running example with all default values ?"
fi
really_check_if_continue
cd $test_file_directory
./$filename
