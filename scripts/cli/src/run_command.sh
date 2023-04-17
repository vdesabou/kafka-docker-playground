DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

test_file="${args[--file]}"
skip_editor="${args[--skip-editor]}"
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

if [[ $test_file == *"@"* ]]
then
  test_file=$(echo "$test_file" | cut -d "@" -f 2)
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
argument_list=""
if [[ -n "$tag" ]]
then
  environment_variables_list="TAG=$tag"
  argument_list="--tag=$tag"
  export TAG=$tag
fi

if [[ -n "$connector_tag" ]]
then
  environment_variables_list="$environment_variables_list CONNECTOR_TAG=$connector_tag"
  argument_list="$argument_list --connector-tag=$connector_tag"
  export CONNECTOR_TAG=$connector_tag
fi

if [[ -n "$connector_zip" ]]
then
  environment_variables_list="$environment_variables_list CONNECTOR_ZIP=$connector_zip"
  argument_list="$argument_list --connector-zip=$connector_zip"
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  environment_variables_list="$environment_variables_list CONNECTOR_JAR=$connector_jar"
  argument_list="$argument_list --connector-jar=$connector_jar"
  export CONNECTOR_JAR=$connector_jar
fi

if [[ -n "$disable_ksqldb" ]]
then
  environment_variables_list="$environment_variables_list DISABLE_KSQLDB=true"
  argument_list="$argument_list --disable-ksqldb"
  export DISABLE_KSQLDB=true
fi

if [[ -n "$disable_c3" ]]
then
  environment_variables_list="$environment_variables_list DISABLE_CONTROL_CENTER=true"
  argument_list="$argument_list --disable-control-center"
  export DISABLE_CONTROL_CENTER=true
fi

if [[ -n "$enable_conduktor" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_CONDUKTOR=true"
  argument_list="$argument_list --enable-conduktor"
  export ENABLE_CONDUKTOR=true
fi

if [[ -n "$enable_multiple_brokers" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_KAFKA_NODES=true"
  argument_list="$argument_list --enable-multiple-broker"
  export ENABLE_KAFKA_NODES=true
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_CONNECT_NODES=true"
  argument_list="$argument_list --enable-multiple-connect-workers"
  export ENABLE_CONNECT_NODES=true
fi

if [[ -n "$enable_jmx_grafana" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_JMX_GRAFANA=true"
  argument_list="$argument_list --enable-jmx-grafana"
  export ENABLE_JMX_GRAFANA=true
fi

if [[ -n "$enable_kcat" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_KCAT=true"
  argument_list="$argument_list --enable-kcat"
  export ENABLE_KCAT=true
fi

if [[ -n "$enable_sr_maven_plugin_app" ]]
then
  environment_variables_list="$environment_variables_list ENABLE_SR_MAVEN_PLUGIN_NODE=true"
  argument_list="$argument_list --enable-sr-maven-plugin-app"
  export ENABLE_SR_MAVEN_PLUGIN_NODE=true
fi

if [[ ! -n "$skip_editor" ]]
then
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
fi

if [ "$environment_variables_list" != "" ]
then
  log "🚀 Running example with $environment_variables_list ?"
else
  log "🚀 Running example with all default values ?"
fi
check_if_continue
echo "playground run -f $test_file $argument_list" > /tmp/playground-run
log "####################################################"
log "🚀 Executing $filename in dir $test_file_directory"
log "####################################################"
SECONDS=0
cd $test_file_directory
trap 'rm /tmp/playground-run-command-used' EXIT
touch /tmp/playground-run-command-used
bash $filename
ret=$?
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
let ELAPSED_TOTAL+=$SECONDS
if [ $ret -eq 0 ]
then
    log "####################################################"
    log "✅ RESULT: SUCCESS for $filename ($ELAPSED - $CUMULATED)"
    log "####################################################"

    playground connector status
else
    logerror "####################################################"
    logerror "🔥 RESULT: FAILURE for $filename ($ELAPSED - $CUMULATED)"
    logerror "####################################################"

    display_docker_container_error_log

    playground connector status
fi