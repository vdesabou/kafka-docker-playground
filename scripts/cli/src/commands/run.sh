DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

test_file="${args[--file]}"
open="${args[--open]}"
environment="${args[--environment]}"
tag="${args[--tag]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"

enable_ksqldb="${args[--enable-ksqldb]}"
enable_rest_proxy="${args[--enable-rest-proxy]}"
enable_c3="${args[--enable-control-center]}"
enable_conduktor="${args[--enable-conduktor]}"
enable_multiple_brokers="${args[--enable-multiple-brokers]}"
enable_multiple_connect_workers="${args[--enable-multiple-connect-workers]}"
enable_jmx_grafana="${args[--enable-jmx-grafana]}"
enable_kcat="${args[--enable-kcat]}"
enable_sql_datagen="${args[--enable-sql-datagen]}"

cluster_type="${args[--cluster-type]}"
cluster_cloud="${args[--cluster-cloud]}"
cluster_region="${args[--cluster-region]}"
cluster_environment="${args[--cluster-environment]}"
cluster_name="${args[--cluster-name]}"
cluster_creds="${args[--cluster-creds]}"
cluster_schema_registry_creds="${args[--cluster-schema-registry-creds]}"

if [[ ! -n "$test_file" ]]
then
  log "--file flag was not provided, please select it now"
  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
      fzf_option_wrap="--preview-window=40%,wrap"
      fzf_option_pointer="--pointer=👉"
      fzf_option_rounded="--border=rounded"
  else
      fzf_option_pointer=""
      fzf_option_rounded=""
  fi

  options=("🔗 Connectors" "🌤️ Confluent Cloud" "🤖 Fully-Managed Connectors" "👷‍♂️ Reproduction Models" "🎏 KSQL" "📝 Schema Registry" "🧲 REST Proxy" "👾 Other Playgrounds" "🌕 All")
  res=$(printf '%s\n' "${options[@]}" | fzf --multi --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🚀" --header="Select a category (ctrl-c or esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)

  case "${res}" in
    "🔗 Connectors")
      test_file=$(playground get-examples-list-with-fzf --connector-only)
    ;;
    "🌤️ Confluent Cloud")
      test_file=$(playground get-examples-list-with-fzf --ccloud-only)
    ;;
    "🤖 Fully-Managed Connectors")
      test_file=$(playground get-examples-list-with-fzf --fully-managed-connector-only)
    ;;
    "👷‍♂️ Reproduction Models")
      test_file=$(playground get-examples-list-with-fzf --repro-only)
    ;;
    "🎏 KSQL")
      test_file=$(playground get-examples-list-with-fzf --ksql-only)
    ;;
    "📝 Schema Registry")
      test_file=$(playground get-examples-list-with-fzf --schema-registry-only)
    ;;
    "🧲 REST Proxy")
      test_file=$(playground get-examples-list-with-fzf --rest-proxy-only)
    ;;
    "👾 Other Playgrounds")
      test_file=$(playground get-examples-list-with-fzf --other-playgrounds-only)
    ;;
    "🌕 All")
      test_file=$(playground get-examples-list-with-fzf)
    ;;
    *)
      logerror "❌ wrong choice: $res"
      exit 1
    ;;
  esac
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

if [[ -n "$environment" ]]
then
  get_connector_paths
  if [ "$connector_paths" == "" ] && [ "$environment" != "plaintext" ]
  then
    logerror "❌ using --environment is only supported with connector examples"
    exit 1
  fi

  if [ "$environment" != "plaintext" ]
  then
    flag_list="$flag_list --environment=$environment"
    export PLAYGROUND_ENVIRONMENT=$environment
  fi
fi

if [[ -n "$connector_tag" ]]
then
  if [ "$connector_tag" == " " ]
  then
    get_connector_paths
    if [ "$connector_paths" == "" ]
    then
        logwarn "❌ skipping as it is not an example with connector, but --connector-tag is set"
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

if [[ -n "$enable_ksqldb" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-ksqldb is not supported with ccloud examples"
    exit 1
  fi
  flag_list="$flag_list --enable-ksqldb"
  export ENABLE_KSQLDB=true
fi

if [[ -n "$enable_rest_proxy" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-rest-proxy is not supported with ccloud examples"
    exit 1
  fi
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
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-multiple-broker is not supported with ccloud examples"
    exit 1
  fi
  flag_list="$flag_list --enable-multiple-broker"
  export ENABLE_KAFKA_NODES=true
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-multiple-connect-workers is not supported with ccloud examples"
    exit 1
  fi
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
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-jmx-grafana"
    exit 1
  fi
  flag_list="$flag_list --enable-jmx-grafana"
  export ENABLE_JMX_GRAFANA=true
fi

if [[ -n "$enable_kcat" ]]
then
  flag_list="$flag_list --enable-kcat"
  export ENABLE_KCAT=true
fi

if [[ -n "$enable_sql_datagen" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-sql-datagen is not supported with ccloud examples"
    exit 1
  fi
  flag_list="$flag_list --enable-sql-datagen"
  export SQL_DATAGEN=true
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
  if [[ $test_file == *"ccloud"* ]]
  then
    log "🚀⛅ Running ccloud example with flags"
  else
    log "🚀 Running example with flags"
  fi
  log "⛳ Flags used are $flag_list"
else
  if [[ $test_file == *"ccloud"* ]]
  then
    log "🚀⛅ Running ccloud example without any flags"
  else
    log "🚀 Running example without any flags"
  fi
fi
set +e
playground container kill-all
set -e
playground state set run.connector_type "$(get_connector_type | tr -d '\n')"
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
function cleanup {
  if [[ -n "$enable_multiple_connect_workers" ]]
  then
    cp /tmp/playground-backup-docker-compose.yml $docker_compose_file
  fi
  rm /tmp/playground-run-command-used
  echo ""
  sleep 3
  set +e
  playground connector status
  connector_type=$(playground state get run.connector_type)
  if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
  then
    playground connector versions
    playground open-docs --only-show-url
  fi
  set -e
}
trap cleanup EXIT

playground generate-fzf-find-files &
generate_connector_versions > /dev/null 2>&1 &
touch /tmp/playground-run-command-used
bash $filename ${other_args[*]}
ret=$?
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
let ELAPSED_TOTAL+=$SECONDS
set +e
# keep those lists up to date
playground generate-connector-plugin-list > /dev/null 2>&1 &
playground generate-kafka-region-list  > /dev/null 2>&1 &
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