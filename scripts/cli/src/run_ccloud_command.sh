DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

test_file="${args[--file]}"
open="${args[--open]}"
tag="${args[--tag]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"
enable_c3="${args[--enable-control-center]}"
enable_conduktor="${args[--enable-conduktor]}"
enable_kcat="${args[--enable-kcat]}"

cluster_type="${args[--cluster-type]}"
cluster_cloud="${args[--cluster-cloud]}"
cluster_region="${args[--cluster-region]}"
cluster_environment="${args[--cluster-environment]}"
cluster_name="${args[--cluster-name]}"
cluster_creds="${args[--cluster-creds]}"
cluster_schema_registry_creds="${args[--cluster-schema-registry-creds]}"

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
filename=$(basename -- "$test_file")

flag_list=""
if [[ -n "$tag" ]]
then
  flag_list="--tag=$tag"
  export TAG=$tag
fi

if [[ -n "$connector_tag" ]]
then
  if [ "$connector_tag" == " " ]
  then
    # determining the docker-compose file from from test_file
    docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
    test_file_directory="$(dirname "${test_file}")"
    docker_compose_file="${test_file_directory}/${docker_compose_file}"

    if [ "${docker_compose_file}" != "" ] && [ ! -f "${docker_compose_file}" ]
    then
        logwarn "❌ skipping as docker-compose override file could not be detemined"
        exit 1
    fi

    connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
    if [ "$connector_paths" == "" ]
    then
        logwarn "❌ skipping as it is not an example with connector"
        exit 1
    else
        connector_tags=""
        for connector_path in ${connector_paths//,/ }
        do
          full_connector_name=$(basename "$connector_path")
          owner=$(echo "$full_connector_name" | cut -d'-' -f1)
          name=$(echo "$full_connector_name" | cut -d'-' -f2-)

          if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
          then
            # happens when plugin is not coming from confluent hub
            logwarn "skipping as plugin $owner/$name does not appear to be coming from confluent hub"
            continue
          fi

          ret=$(choose_connector_tag "$owner/$name")
          connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
          
          if [ -z "$connector_tags" ]; then
            connector_tags="$connector_tag"
          else
            connector_tags="$connector_tags,$connector_tag"
          fi
        done

        connector_tag="$connector_tags"
    fi
  fi

  flag_list="$flag_list --connector-tag=$connector_tag"
  export CONNECTOR_TAG="$connector_tag"
fi

if [[ -n "$connector_zip" ]]
then
  if [[ $connector_zip == *"@"* ]]
  then
    connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
  fi
  flag_list="$flag_list --connector-zip=$connector_zip"
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  if [[ $connector_jar == *"@"* ]]
  then
    connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
  fi
  flag_list="$flag_list --connector-jar=$connector_jar"
  export CONNECTOR_JAR=$connector_jar
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

if [[ -n "$enable_kcat" ]]
then
  flag_list="$flag_list --enable-kcat"
  export ENABLE_KCAT=true
fi

if [[ -n "$cluster_region" ]]
then
  if [[ $cluster_region == *"@"* ]]
  then
    cluster_region=$(echo "$cluster_region" | cut -d "@" -f 2)
  fi
  cluster_region=$(echo "$cluster_region" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
fi

if [[ -n "$cluster_type" ]] || [[ -n "$cluster_cloud" ]] || [[ -n "$cluster_region" ]] || [[ -n "$cluster_environment" ]] || [[ -n "$cluster_name" ]] || [[ -n "$cluster_creds" ]] || [[ -n "$cluster_schema_registry_creds" ]]
then
  if [ ! -z "$CLUSTER_TYPE" ]
  then
    log "🙈 ignoring environment variable CLUSTER_TYPE as one of the flags is set"
    unset CLUSTER_TYPE
  fi
  if [ ! -z "$CLUSTER_CLOUD" ]
  then
    log "🙈 ignoring environment variable CLUSTER_CLOUD as one of the flags is set"
    unset CLUSTER_CLOUD
  fi
  if [ ! -z "$CLUSTER_REGION" ]
  then
    log "🙈 ignoring environment variable CLUSTER_REGION as one of the flags is set"
    unset CLUSTER_REGION
  fi
  if [ ! -z "$ENVIRONMENT" ]
  then
    log "🙈 ignoring environment variable ENVIRONMENT as one of the flags is set"
    unset ENVIRONMENT
  fi
  if [ ! -z "$CLUSTER_NAME" ]
  then
    log "🙈 ignoring environment variable CLUSTER_NAME as one of the flags is set"
    unset CLUSTER_NAME
  fi
  if [ ! -z "$CLUSTER_CREDS" ]
  then
    log "🙈 ignoring environment variable CLUSTER_CREDS as one of the flags is set"
    unset CLUSTER_CREDS
  fi 
  if [ ! -z "$SCHEMA_REGISTRY_CREDS" ]
  then
    log "🙈 ignoring environment variable SCHEMA_REGISTRY_CREDS as one of the flags is set"
    unset SCHEMA_REGISTRY_CREDS
  fi 
fi

if [[ -n "$cluster_type" ]]
then
  flag_list="$flag_list --cluster-type $cluster_type"
  export CLUSTER_TYPE=$cluster_type
else
  if [ -z "$CLUSTER_TYPE" ]
  then
    export CLUSTER_TYPE="basic"
  fi
fi

if [[ -n "$cluster_cloud" ]]
then
  flag_list="$flag_list --cluster-cloud $cluster_cloud"
  export CLUSTER_CLOUD=$cluster_cloud
else
  if [ -z "$CLUSTER_CLOUD" ]
  then
    export CLUSTER_CLOUD="aws"
  fi
fi

if [[ -n "$cluster_region" ]]
then
  flag_list="$flag_list --cluster-region $cluster_region"
  export CLUSTER_REGION=$cluster_region
else
  if [ -z "$CLUSTER_REGION" ]
  then
    export CLUSTER_REGION="eu-west-2"
  fi
fi

if [[ -n "$cluster_environment" ]]
then
  flag_list="$flag_list --cluster-environment $cluster_environment"
  export ENVIRONMENT=$cluster_environment
fi

if [[ -n "$cluster_name" ]]
then
  flag_list="$flag_list --cluster-name $cluster_name"
  export CLUSTER_NAME=$cluster_name
fi

if [[ -n "$cluster_creds" ]]
then
  flag_list="$flag_list --cluster-creds $cluster_creds"
  export CLUSTER_CREDS=$cluster_creds
fi

if [[ -n "$cluster_schema_registry_creds" ]]
then
  flag_list="$flag_list --cluster-schema-registry-creds $cluster_schema_registry_creds"
  export SCHEMA_REGISTRY_CREDS=$cluster_schema_registry_creds
fi

if [[ -n "$open" ]]
then
  editor=$(playground config get editor)
  if [ "$editor" != "" ]
  then
    log "📖 Opening ${test_file} using configured editor $editor"
    $editor ${test_file}
    check_if_continue
  else
      if [[ $(type code 2>&1) =~ "not found" ]]
      then
          logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
          exit 1
      else
          log "📖 Opening ${test_file} with code (default) - you can change editor by using playground config editor <editor>"
          code ${test_file}
          check_if_continue
      fi
  fi
fi

if [ "$flag_list" != "" ]
then
  log "🚀⛅ Running ccloud example with flags"
  log "⛳ Flags used are $flag_list"
else
  log "🚀⛅ Running ccloud example without any flags"
fi
set +e
playground container kill-all
set -e
playground state set run.test_file "$test_file"
playground state set run.run_command "playground run -f $test_file $flag_list ${other_args[*]}"
echo "" >> "$root_folder/playground-run-history"
echo "playground run -f $test_file $flag_list ${other_args[*]}" >> "$root_folder/playground-run-history"

increment_cli_metric nb_runs
log "🚀 Number of examples ran so far: $(get_cli_metric nb_runs)"

log "####################################################"
log "🚀 Executing $filename in dir $test_file_directory"
log "####################################################"
SECONDS=0
cd $test_file_directory
trap 'rm /tmp/playground-run-command-used;echo "";sleep 3;set +e;playground connector status;playground fully-managed-connector status;playground connector versions' EXIT
touch /tmp/playground-run-command-used
playground generate-fzf-find-files &
bash $filename ${other_args[*]}
ret=$?
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
let ELAPSED_TOTAL+=$SECONDS
set +e
set -e
if [ $ret -eq 0 ]
then
    log "####################################################"
    log "✅ RESULT: SUCCESS for $filename ($ELAPSED - $CUMULATED)"
    log "####################################################"
else
    logerror "####################################################"
    logerror "🔥 RESULT: FAILURE for $filename ($ELAPSED - $CUMULATED)"
    logerror "####################################################"

    display_docker_container_error_log
fi