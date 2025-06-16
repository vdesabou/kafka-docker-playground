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
enable_flink="${args[--enable-flink]}"
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
force_interactive_re_run="${args[--force-interactive-re-run]}"
force_interactive_repro="${args[--force-interactive-repro]}"

interactive_mode=0

if [[ -n "$force_interactive_repro" ]]
then
  interactive_mode=1
fi

declare -a array_flag_list=()
if [[ -n "$force_interactive_re_run" ]]
then
  interactive_mode=1
fi

if [[ ! -n "$test_file" ]]
then
  interactive_mode=1
  display_interactive_menu_categories
fi

if [[ $test_file == *"@"* ]]
then
  test_file=$(echo "$test_file" | cut -d "@" -f 2)
fi

if [ ! -f "$test_file" ]
then
  logerror "❌ test_file $test_file does not exist!"
  exit 1
fi

if [[ "$test_file" != /* ]]
then
  test_file="$PWD/$test_file"
fi

if [[ "$test_file" != *".sh" ]]
then
  logerror "❌ test_file $test_file is not a .sh file!"
  exit 1
fi

if [[ $test_file == *"ccloud"* ]]
then
  verify_installed "confluent"
fi

set +e
container_kill_all_before_run=$(playground config get container-kill-all-before-run)
if [ "$container_kill_all_before_run" == "" ]
then
    playground config set container-kill-all-before-run false
fi

if [ "$container_kill_all_before_run" == "true" ] || [ "$container_kill_all_before_run" == "" ]
then
  log "💀 kill all docker containers (disable with 'playground config container-kill-all-before-run false')"
  playground container kill-all
else
  playground stop
fi
set -e

playground state set run.test_file "$test_file"
test_file_directory="$(dirname "${test_file}")"
filename=$(basename -- "$test_file")

docs_available=1
set +e
playground open-docs --only-show-url > /dev/null 2>&1
if [ $? -eq 1 ]
then
  docs_available=0
fi
set -e
if [[ -n "$tag" ]]
then
  if [[ $tag == *"@"* ]]
  then
    tag=$(echo "$tag" | cut -d "@" -f 2)
  fi
  array_flag_list+=("--tag=$tag")
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
    array_flag_list+=("--environment=$environment")
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
            # logwarn "skipping as plugin $owner/$name does not appear to be coming from confluent hub"
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

  array_flag_list+=("--connector-tag=$connector_tag")
  export CONNECTOR_TAG="$connector_tag"
fi

if [[ -n "$connector_zip" ]]
then
  if [[ $connector_zip == *"@"* ]]
  then
    connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
  fi
  array_flag_list+=("--connector-zip=$connector_zip")
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  if [[ $connector_jar == *"@"* ]]
  then
    connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
  fi
  array_flag_list+=("--connector-jar=$connector_jar")
  export CONNECTOR_JAR=$connector_jar
fi

if [[ -n "$enable_ksqldb" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-ksqldb is not supported with ccloud examples"
    exit 1
  fi
  array_flag_list+=("--enable-ksqldb")
  export ENABLE_KSQLDB=true
fi

if [[ -n "$enable_rest_proxy" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-rest-proxy is not supported with ccloud examples"
    exit 1
  fi
  array_flag_list+=("--enable-rest-proxy")
  export ENABLE_RESTPROXY=true
fi

if [[ -n "$enable_c3" ]]
then
  array_flag_list+=("--enable-control-center")
  export ENABLE_CONTROL_CENTER=true
fi

if [[ -n "$enable_flink" ]]
then
  array_flag_list+=("--enable-flink")
  export ENABLE_FLINK=true
fi

if [[ -n "$enable_conduktor" ]]
then
  array_flag_list+=("--enable-conduktor")
  export ENABLE_CONDUKTOR=true
fi

if [[ -n "$enable_multiple_brokers" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-multiple-brokers is not supported with ccloud examples"
    exit 1
  fi
  array_flag_list+=("--enable-multiple-brokers")
  export ENABLE_KAFKA_NODES=true
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-multiple-connect-workers is not supported with ccloud examples"
    exit 1
  fi

  array_flag_list+=("--enable-multiple-connect-workers")
  export ENABLE_CONNECT_NODES=true

  # determining the docker-compose file from from test_file
  docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
  docker_compose_file="${test_file_directory}/${docker_compose_file}"
  if [ -f $docker_compose_file ]
  then
    cp $docker_compose_file /tmp/playground-backup-docker-compose.yml
    yq -i '.services.connect2 = .services.connect' /tmp/playground-backup-docker-compose.yml
    yq -i '.services.connect3 = .services.connect' /tmp/playground-backup-docker-compose.yml
    cp /tmp/playground-backup-docker-compose.yml $docker_compose_file
  fi
fi

if [[ -n "$enable_jmx_grafana" ]]
then
  array_flag_list+=("--enable-jmx-grafana")
  export ENABLE_JMX_GRAFANA=true

  if [[ -n "$force_interactive_repro" ]]
  then
    force_enable --enable-jmx-grafana ENABLE_JMX_GRAFANA
  fi
fi

if [[ -n "$enable_kcat" ]]
then
  array_flag_list+=("--enable-kcat")
  export ENABLE_KCAT=true
fi

if [[ -n "$enable_sql_datagen" ]]
then
  array_flag_list+=("--enable-sql-datagen")
  export SQL_DATAGEN=true

  if [[ $test_file != *"fully-managed"* ]]
  then
    log "📊 automatically enabling Grafana as --enable-sql-datagen is set"
    array_flag_list+=("--enable-jmx-grafana")
    export ENABLE_JMX_GRAFANA=true

    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-sql-datagen SQL_DATAGEN
      force_enable --enable-jmx-grafana ENABLE_JMX_GRAFANA
    fi
  fi
fi

if [[ -n "$cluster_type" ]] || [[ -n "$cluster_cloud" ]] || [[ -n "$cluster_region" ]] || [[ -n "$cluster_environment" ]] || [[ -n "$cluster_name" ]] || [[ -n "$cluster_creds" ]] || [[ -n "$cluster_schema_registry_creds" ]]
then
  playground state set ccloud.suggest_use_previous_example_ccloud "0"
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
else
  playground state set ccloud.suggest_use_previous_example_ccloud "1"
fi

if [[ -n "$cluster_type" ]]
then
  array_flag_list+=("--cluster-type $cluster_type")
  export CLUSTER_TYPE=$cluster_type
elif [ $interactive_mode == 0 ]
then
  if [ -z "$CLUSTER_TYPE" ]
  then
    export CLUSTER_TYPE="basic"
  fi
fi

if [[ -n "$cluster_cloud" ]]
then
  array_flag_list+=("--cluster-cloud $cluster_cloud")
  export CLUSTER_CLOUD=$cluster_cloud
elif [ $interactive_mode == 0 ]
then
  if [ -z "$CLUSTER_CLOUD" ]
  then
    export CLUSTER_CLOUD="aws"
  fi
fi

if [[ -n "$cluster_region" ]]
then
  array_flag_list+=("--cluster-region $cluster_region")
  export CLUSTER_REGION=$cluster_region
elif [ $interactive_mode == 0 ]
then
  if [ -z "$CLUSTER_REGION" ]
  then
    case "${CLUSTER_CLOUD}" in
      aws)
        export CLUSTER_REGION="eu-west-2"
      ;;
      azure)
        export CLUSTER_REGION="westeurope"
      ;;
      gcp)
        export CLUSTER_REGION="europe-west2"
      ;;
    esac
  fi
fi

if [[ -n "$cluster_environment" ]]
then
  if [[ $cluster_environment == *"@"* ]]
  then
    cluster_environment=$(echo "$cluster_environment" | cut -d "@" -f 2)
  fi
  if [[ $cluster_environment == *"/"* ]]
  then
    cluster_environment=$(echo "$cluster_environment" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
  fi
  array_flag_list+=("--cluster-environment $cluster_environment")
  export ENVIRONMENT=$cluster_environment
fi

if [[ -n "$cluster_name" ]]
then
  if [[ $cluster_name == *"@"* ]]
  then
    cluster_name=$(echo "$cluster_name" | cut -d "@" -f 2)
  fi
  if [[ $cluster_name == *"/"* ]]
  then
    cluster_name=$(echo "$cluster_name" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
  fi
  array_flag_list+=("--cluster-name $cluster_name")
  export CLUSTER_NAME=$cluster_name
fi

if [[ -n "$cluster_creds" ]]
then
  array_flag_list+=("--cluster-creds $cluster_creds")
  export CLUSTER_CREDS=$cluster_creds
fi

if [[ -n "$cluster_schema_registry_creds" ]]
then
  array_flag_list+=("--cluster-schema-registry-creds $cluster_schema_registry_creds")
  export SCHEMA_REGISTRY_CREDS=$cluster_schema_registry_creds
fi

if [[ -n "$open" ]]
then
  if [[ $test_file == *"fully-managed"* ]] || [[ $test_file == *"custom-"* ]]
  then
    playground open --file "${test_file}"
  else
    playground open --file "${test_file}" --open-docker-compose
  fi
  check_if_continue
fi

if [ $interactive_mode == 1 ]
then
  terminal_columns=$(tput cols)
  if [[ $terminal_columns -gt 180 ]]
  then
    MAX_LENGTH=$((${terminal_columns}-120))
    fzf_version=$(get_fzf_version)
    if version_gt $fzf_version "0.38"
    then
      fzf_option_wrap="--preview-window=30%,wrap"
      fzf_option_pointer="--pointer=👉"
      fzf_option_empty_pointer=""
      fzf_option_rounded="--border=rounded"
    else
      fzf_option_wrap=""
      fzf_option_pointer=""
      fzf_option_empty_pointer=""
      fzf_option_rounded=""
    fi
  else
    MAX_LENGTH=$((${terminal_columns}-65))
    fzf_version=$(get_fzf_version)
    if version_gt $fzf_version "0.38"
    then
      fzf_option_wrap="--preview-window=20%,wrap"
      fzf_option_pointer="--pointer=👉"
      fzf_option_empty_pointer=""
      fzf_option_rounded="--border=rounded"
    else
      fzf_option_wrap=""
      fzf_option_pointer=""
      fzf_option_empty_pointer=""
      fzf_option_rounded=""
    fi
  fi
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  GREEN='\033[0;32m'
  NC='\033[0m' # No Color

  if [[ -n "$force_interactive_repro" ]]
  then
    MENU_LETS_GO="🚀 Run the reproduction model !" #0
  else
    MENU_LETS_GO="🚀 Run the example !" #0
  fi
  
  MENU_PROBLEM="❌ The example cannot be executed, check error(s) 👉" #1
  if [[ $test_file == *"fully-managed"* ]] || [[ $test_file == *"custom-"* ]]
  then
    MENU_OPEN_FILE="📖 Open the example file in text editor"
  else
    MENU_OPEN_FILE="📖 Open the example files (including docker-compose file) in text editor"
  fi
  set +e
  if [[ $(type -f open 2>&1) =~ "not found" ]]
  then
    MENU_OPEN_DOCS="🌐 Show link to the docs"
  else
    MENU_OPEN_DOCS="🌐 Open the docs in browser"
  fi
  set -e
  # readonly MENU_SEPARATOR="--------------------------------------------------" #4

  MENU_TAG="🎯 CP version $(printf '%*s' $((${MAX_LENGTH}-13-${#MENU_TAG})) ' ') --tag" #5
  MENU_CONNECTOR_TAG="🔗 Connector version $(printf '%*s' $((${MAX_LENGTH}-20-${#MENU_CONNECTOR_TAG})) ' ') --connector-tag"
  MENU_CONNECTOR_ZIP="🤐 Connector zip $(printf '%*s' $((${MAX_LENGTH}-16-${#MENU_CONNECTOR_ZIP})) ' ') --connector-zip"
  MENU_CONNECTOR_JAR="🤎 Connector jar $(printf '%*s' $((${MAX_LENGTH}-16-${#MENU_CONNECTOR_JAR})) ' ') --connector-jar"
  MENU_ENVIRONMENT="🔐 Environment $(printf '%*s' $((${MAX_LENGTH}-14-${#MENU_ENVIRONMENT})) ' ') --environment" 

  readonly MENU_SEPARATOR="--------------------------------------------------" #10

  MENU_ENABLE_KSQLDB="🎏 Enable ksqlDB $(printf '%*s' $((${MAX_LENGTH}-16-${#MENU_ENABLE_KSQLDB})) ' ') --enable-ksqldb" #11
  MENU_ENABLE_C3="💠 Enable Control Center $(printf '%*s' $((${MAX_LENGTH}-24-${#MENU_ENABLE_C3})) ' ') --enable-control-center"
  MENU_ENABLE_CONDUKTOR="🐺 Enable Conduktor Platform $(printf '%*s' $((${MAX_LENGTH}-28-${#MENU_ENABLE_CONDUKTOR})) ' ') --enable-conduktor"
  MENU_ENABLE_RP="🧲 Enable Rest Proxy $(printf '%*s' $((${MAX_LENGTH}-20-${#MENU_ENABLE_RP})) ' ') --enable-rest-proxy" 
  MENU_ENABLE_GRAFANA="📊 Enable Grafana $(printf '%*s' $((${MAX_LENGTH}-17-${#MENU_ENABLE_GRAFANA})) ' ') --enable-jmx-grafana"
  MENU_ENABLE_BROKERS="3️⃣  Enabling multiple brokers $(printf '%*s' $((${MAX_LENGTH}-28-${#MENU_ENABLE_BROKERS})) ' ') --enable-multiple-brokers"
  MENU_ENABLE_CONNECT_WORKERS="🥉 Enabling multiple connect workers $(printf '%*s' $((${MAX_LENGTH}-36-${#MENU_ENABLE_CONNECT_WORKERS})) ' ') --enable-multiple-connect-workers"
  MENU_ENABLE_KCAT="🐈 Enabling kcat $(printf '%*s' $((${MAX_LENGTH}-16-${#MENU_ENABLE_KCAT})) ' ') --enable-kcat"
  MENU_ENABLE_SQL_DATAGEN="🌪️  Enable SQL Datagen injection $(printf '%*s' $((${MAX_LENGTH}-32-${#MENU_ENABLE_SQL_DATAGEN})) ' ') --enable-sql-datagen" #19
  MENU_ENABLE_FLINK="🐿️  Enable Flink $(printf '%*s' $((${MAX_LENGTH}-15-${#MENU_ENABLE_FLINK})) ' ') --enable-flink" #20

  readonly MENU_DISABLE_KSQLDB="❌🎏 Disable ksqlDB" #21
  readonly MENU_DISABLE_C3="❌💠 Disable Control Center"
  readonly MENU_DISABLE_CONDUKTOR="❌🐺 Disable Conduktor Platform"
  readonly MENU_DISABLE_RP="❌🧲 Disable Rest Proxy"
  readonly MENU_DISABLE_GRAFANA="❌📊 Disable Grafana"
  readonly MENU_DISABLE_BROKERS="❌3️⃣ Disabling multiple brokers"
  readonly MENU_DISABLE_CONNECT_WORKERS="❌🥉 Disabling multiple connect workers"
  readonly MENU_DISABLE_KCAT="❌🐈 Disabling kcat"
  readonly MENU_DISABLE_SQL_DATAGEN="❌🌪️ Disable SQL Datagen injection" #29
  readonly MENU_DISABLE_FLINK="❌🐿️ Disable Flink" #30

  readonly MENU_SEPARATOR_FEATURES="--------------------options-----------------------"

  MENU_CLUSTER_TYPE="🔋 Cluster type $(printf '%*s' $((${MAX_LENGTH}-15-${#MENU_CLUSTER_TYPE})) ' ') --cluster-type" #31
  MENU_CLUSTER_CLOUD="🌤  Cloud provider $(printf '%*s' $((${MAX_LENGTH}-17-${#MENU_CLUSTER_CLOUD})) ' ') --cluster-cloud"
  MENU_CLUSTER_REGION="🗺  Cloud region $(printf '%*s' $((${MAX_LENGTH}-15-${#MENU_CLUSTER_REGION})) ' ') --cluster-region"
  MENU_CLUSTER_ENVIRONMENT="🌐 Environment id $(printf '%*s' $((${MAX_LENGTH}-17-${#MENU_CLUSTER_ENVIRONMENT})) ' ') --cluster-environment"

  MENU_CLUSTER_NAME="🎰 Cluster name $(printf '%*s' $((${MAX_LENGTH}-15-${#MENU_CLUSTER_NAME})) ' ') --cluster-name"
  MENU_CLUSTER_CREDS="🔒 Kafka api key & secret $(printf '%*s' $((${MAX_LENGTH}-25-${#MENU_CLUSTER_CREDS})) ' ') --cluster-creds"
  MENU_CLUSTER_SR_CREDS="🔰 Schema registry api key & secret $(printf '%*s' $((${MAX_LENGTH}-35-${#MENU_CLUSTER_SR_CREDS})) ' ') --cluster-schema-registry-creds"

  readonly MENU_SEPARATOR_CLOUD="-----------------confluent cloud------------------" #38

  readonly MENU_GO_BACK="🔙 Go back"

  last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))
  example="$last_two_folders/$filename"

  connector_example=0
  get_connector_paths
  if [ "$connector_paths" != "" ]
  then
    connector_tags=""
    for connector_path in ${connector_paths//,/ }
    do
      full_connector_name=$(basename "$connector_path")
      owner=$(echo "$full_connector_name" | cut -d'-' -f1)
      name=$(echo "$full_connector_name" | cut -d'-' -f2-)

      if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
      then
        # happens when plugin is not coming from confluent hub
        continue
      else
        connector_example=1
      fi
    done
  fi

  sql_datagen=0
  if [[ $test_file == *"connect-debezium-sqlserver"* ]] || [[ $test_file == *"connect-debezium-mysql"* ]] || [[ $test_file == *"connect-debezium-postgresql"* ]] || [[ $test_file == *"connect-debezium-oracle"* ]] || [[ $test_file == *"connect-cdc-oracle"* ]] || [[ $test_file == *"connect-jdbc-sqlserver"* ]] || [[ $test_file == *"connect-jdbc-mysql"* ]] || [[ $test_file == *"connect-jdbc-postgresql"* ]] || [[ $test_file == *"connect-jdbc-oracle"* ]] || [[ $test_file == *"connect-cdc-xstream"* ]] || [[ $test_file == *"fm-debezium"* ]] || [[ $test_file == *"fm-cdc"* ]]
  then
    sql_datagen=1
  fi

  stop=0
  while [ $stop != 1 ]
  do
    has_error=0
    options=("$MENU_LETS_GO" "$MENU_PROBLEM" "$MENU_OPEN_FILE" "$MENU_OPEN_DOCS" "$MENU_SEPARATOR" "$MENU_TAG" "$MENU_CONNECTOR_TAG" "$MENU_CONNECTOR_ZIP" "$MENU_CONNECTOR_JAR" "$MENU_ENVIRONMENT" "$MENU_SEPARATOR" "$MENU_ENABLE_KSQLDB" "$MENU_ENABLE_C3" "$MENU_ENABLE_CONDUKTOR" "$MENU_ENABLE_RP" "$MENU_ENABLE_GRAFANA" "$MENU_ENABLE_BROKERS" "$MENU_ENABLE_CONNECT_WORKERS" "$MENU_ENABLE_KCAT" "$MENU_ENABLE_SQL_DATAGEN" "$MENU_ENABLE_FLINK" "$MENU_DISABLE_KSQLDB" "$MENU_DISABLE_C3" "$MENU_DISABLE_CONDUKTOR" "$MENU_DISABLE_RP" "$MENU_DISABLE_GRAFANA" "$MENU_DISABLE_BROKERS" "$MENU_DISABLE_CONNECT_WORKERS" "$MENU_DISABLE_KCAT" "$MENU_DISABLE_SQL_DATAGEN" "$MENU_DISABLE_FLINK" "$MENU_SEPARATOR_FEATURES" "$MENU_CLUSTER_TYPE" "$MENU_CLUSTER_CLOUD" "$MENU_CLUSTER_REGION" "$MENU_CLUSTER_ENVIRONMENT" "$MENU_CLUSTER_NAME" "$MENU_CLUSTER_CREDS" "$MENU_CLUSTER_SR_CREDS" "$MENU_SEPARATOR_CLOUD" "$MENU_GO_BACK")

    if [[ $test_file == *"ccloud"* ]] || [ "$PLAYGROUND_ENVIRONMENT" == "ccloud" ]
    then
      if [[ $test_file == *"fully-managed"* ]]
      then
        for((i=5;i<19;i++)); do
          unset "options[$i]"
        done

        for((i=20;i<32;i++)); do
          unset "options[$i]"
        done
      fi
      unset 'options[14]'
      unset 'options[15]'
      unset 'options[16]'
      unset 'options[17]'

      unset 'options[24]'
      unset 'options[25]'
      unset 'options[26]'
      unset 'options[27]'

      if [[ -n "$cluster_type" ]] || [[ -n "$cluster_cloud" ]] || [[ -n "$cluster_region" ]] || [[ -n "$cluster_environment" ]] || [[ -n "$cluster_creds" ]] || [[ -n "$cluster_schema_registry_creds" ]]
      then
        if [ ! -z "$CLUSTER_TYPE" ]
        then
          unset CLUSTER_TYPE
        fi
        if [ ! -z "$CLUSTER_CLOUD" ]
        then
          unset CLUSTER_CLOUD
        fi
        if [ ! -z "$CLUSTER_REGION" ]
        then
          unset CLUSTER_REGION
        fi
        if [ ! -z "$ENVIRONMENT" ]
        then
          unset ENVIRONMENT
        fi
        if [ ! -z "$CLUSTER_NAME" ]
        then
          unset CLUSTER_NAME
          cluster_name=""
        fi
        if [ ! -z "$CLUSTER_CREDS" ]
        then
          unset CLUSTER_CREDS
        fi 
        if [ ! -z "$SCHEMA_REGISTRY_CREDS" ]
        then
          unset SCHEMA_REGISTRY_CREDS
        fi
      fi
      if [ ! -z "$CLUSTER_NAME" ] || [[ -n "$cluster_name" ]]
      then
        if [ ! -z "$CLUSTER_NAME" ]
        then
          cluster_name=$CLUSTER_NAME
        fi
        #
        # CLUSTER_NAME is set
        #
        ccloud_preview="🎯 ${YELLOW}cluster-name is set, your existing ccloud cluster will be used...${NC}\n\n"
        ccloud_preview="${ccloud_preview}🎰 ${YELLOW}cluster-name=$cluster_name${NC}\n"

        if [ -z $ENVIRONMENT ] 
        then
          ccloud_preview="${ccloud_preview}❌ 🌐${RED}environment is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
        else
          ccloud_preview="${ccloud_preview}🌐 ${YELLOW}environment=$ENVIRONMENT${NC}\n"
        fi

        if [ -z $CLUSTER_CLOUD ] 
        then
          ccloud_preview="${ccloud_preview}❌  🌤${RED}cluster-cloud is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
        else
          ccloud_preview="${ccloud_preview}🌤 ${YELLOW}cluster-cloud=$CLUSTER_CLOUD${NC}\n"
        fi
        
        if [ -z $CLUSTER_REGION ] 
        then
          ccloud_preview="${ccloud_preview}❌ 🗺${RED}cluster-region is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
        else
          ccloud_preview="${ccloud_preview}🗺  ${YELLOW}cluster-region=$CLUSTER_REGION${NC}\n"
        fi

        if [ -z $CLUSTER_CREDS ] 
        then
          ccloud_preview="${ccloud_preview}❌ 🔒${RED}cluster-creds is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
        fi

        if [ -z $SCHEMA_REGISTRY_CREDS ] 
        then
          ccloud_preview="${ccloud_preview}🔒 ${YELLOW}cluster-schema-registry-creds is missing, new credentials will be created${NC}\n"
        else
          ccloud_preview="${ccloud_preview}🔒 ${YELLOW}cluster-schema-registry-creds are set${NC}\n"
        fi
      else # CLUSTER_NAME is set
        #
        # CLUSTER_NAME is not set
        #
        ccloud_preview="✨ ${YELLOW}cluster-name is not set, a new ccloud cluster will be created...${NC}\n\n"

        if [ -z $ENVIRONMENT ] && [[ ! -n "$cluster_environment" ]]
        then
          ccloud_preview="${ccloud_preview}🌐 ${CYAN}environment is missing, new environment will be created${NC}\n"
        else
          if [ ! -z "$ENVIRONMENT" ]
          then
            cluster_environment=$ENVIRONMENT
          fi
          ccloud_preview="${ccloud_preview}🌐 ${YELLOW}cluster-environment=$cluster_environment${NC}\n"
        fi

        if [ -z $CLUSTER_TYPE ] && [[ ! -n "$cluster_type" ]]
        then
          ccloud_preview="${ccloud_preview}🔋 ${CYAN}cluster-type is missing, basic will be used${NC}\n"
        else
          if [ ! -z "$CLUSTER_TYPE" ]
          then
            cluster_type=$CLUSTER_TYPE
          fi
          ccloud_preview="${ccloud_preview}🔋 ${YELLOW}cluster-type=$cluster_type${NC}\n"
        fi

        if [ -z $CLUSTER_CLOUD ] && [[ ! -n "$cluster_cloud" ]]
        then
          ccloud_preview="${ccloud_preview}🌤  ${CYAN}cluster-cloud is missing, aws will be used${NC}\n"
        else
          if [ ! -z "$CLUSTER_CLOUD" ]
          then
            cluster_cloud=$CLUSTER_CLOUD
          fi
          ccloud_preview="${ccloud_preview}🌤 ${YELLOW}cluster-cloud=$cluster_cloud${NC}\n"
        fi
        
        if [ -z $CLUSTER_REGION ] && [[ ! -n "$cluster_region" ]]
        then
          ccloud_preview="${ccloud_preview}🗺 ${CYAN}cluster-region is missing, default region for provider will be used${NC}\n"
        else
          if [ ! -z "$CLUSTER_REGION" ]
          then
            cluster_region=$CLUSTER_REGION
          fi
          ccloud_preview="${ccloud_preview}🗺  ${YELLOW}cluster-region=$cluster_region${NC}\n"
        fi
      fi
    else # end of ccloud
      unset 'options[32]'
      unset 'options[33]'
      unset 'options[34]'
      unset 'options[35]'
      unset 'options[36]'
      unset 'options[37]'
      unset 'options[38]'
      unset 'options[39]'

      unset 'options[41]'
      unset 'options[42]'
      unset 'options[43]'
      unset 'options[44]'
    fi

    if [ $connector_example == 0 ]
    then
      unset 'options[6]'
      unset 'options[7]'
      unset 'options[8]'
      unset 'options[9]'
    fi

    if [ $docs_available == 0 ]
    then
      unset 'options[3]'
    fi

    if [ $sql_datagen == 0 ]
    then
      unset 'options[19]'
    fi

    if [ ! -z $ENABLE_KSQLDB ]
    then
      unset 'options[11]'
    else
      unset 'options[21]'
    fi
    if [ ! -z $ENABLE_CONTROL_CENTER ]
    then
      unset 'options[12]'
    else
      unset 'options[22]'
    fi
    if [ ! -z $ENABLE_CONDUKTOR ]
    then
      unset 'options[13]'
    else
      unset 'options[23]'
    fi
    if [ ! -z $ENABLE_RESTPROXY ]
    then
      unset 'options[14]'
    else
      unset 'options[24]'
    fi
    if [ ! -z $ENABLE_JMX_GRAFANA ]
    then
      unset 'options[15]'
    else
      unset 'options[25]'
    fi
    if [ ! -z $ENABLE_KAFKA_NODES ]
    then
      unset 'options[16]'
    else
      unset 'options[26]'
    fi
    if [ ! -z $ENABLE_CONNECT_NODES ]
    then
      unset 'options[17]'
    else
      unset 'options[27]'
    fi
    if [ ! -z $ENABLE_KCAT ]
    then
      unset 'options[18]'
    else
      unset 'options[28]'
    fi
    if [ ! -z $SQL_DATAGEN ]
    then
      unset 'options[19]'
    else
      unset 'options[29]'
    fi
    if [ ! -z $ENABLE_FLINK ]
    then
      unset 'options[20]'
    else
      unset 'options[30]'
    fi

    missing_env=""
    declare -a missing_env_list=()

    # generic check
    for mandatory_environment_variable in $(grep "Export it as environment variable or pass it as argument" $test_file | cut -d "\"" -f2 | cut -d " " -f 1)
    do
      if [ ! -v $mandatory_environment_variable ]
      then
        missing_env="${missing_env}❌ ${RED}${mandatory_environment_variable} is missing!${NC}\n"
        unset 'options[0]'
        has_error=1

        missing_env_list+=("$mandatory_environment_variable")
      else
        if [[ $mandatory_environment_variable == *"PASSWORD"* ]] || [[ $mandatory_environment_variable == *"SECRET"* ]] || [[ $mandatory_environment_variable == *"TOKEN"* ]] || [[ $mandatory_environment_variable == *"KEY"* ]]
        then
          missing_env="${missing_env}🔑 ${GREEN}${mandatory_environment_variable} is set${NC}\n"
        else
          missing_env="${missing_env}🔑 ${GREEN}${mandatory_environment_variable}=${!mandatory_environment_variable}${NC}\n"
        fi
      fi
    done

    if [[ $test_file == *"aws"* ]]
    then
      if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
      then
        if [ ! -f "$HOME/.aws/credentials" ]
        then
          missing_env="${missing_env}❌ ${RED}$HOME/.aws/credentials is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
        fi

        if [ -z "$AWS_ACCESS_KEY_ID" ]
        then
          missing_env="${missing_env}❌ ${RED}AWS_ACCESS_KEY_ID is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
          missing_env_list+=("AWS_ACCESS_KEY_ID")
        fi

        if [ -z "$AWS_SECRET_ACCESS_KEY" ]
        then
          missing_env="${missing_env}❌ ${RED}AWS_SECRET_ACCESS_KEY is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
          missing_env_list+=("AWS_SECRET_ACCESS_KEY")
        fi
      fi

      if [ -f "$HOME/.aws/credentials" ]
      then
        missing_env="${missing_env}🔑 ${GREEN}$HOME/.aws/credentials is present${NC}\n"
      fi

      if [ ! -z "$AWS_ACCESS_KEY_ID" ]
      then
        missing_env="${missing_env}🔑 ${GREEN}AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}${NC}\n"
      fi

      if [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
      then
        missing_env="${missing_env}🔑 ${GREEN}AWS_SECRET_ACCESS_KEY is set${NC}\n"
      fi
    fi

    if [[ $test_file == *"gcp"* ]]
    then
      if [ ! -f "$test_file_directory/keyfile.json" ] && [ -z "$GCP_KEYFILE_CONTENT" ]
      then
        if [ ! -f "$test_file_directory/keyfile.json" ]
        then
          missing_env="${missing_env}❌ ${RED}$test_file_directory/keyfile.json is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
        fi

        if [ -z "$GCP_KEYFILE_CONTENT" ]
        then
          missing_env="${missing_env}❌ ${RED}GCP_KEYFILE_CONTENT is missing!${NC}\n"
          unset 'options[0]'
          has_error=1
          missing_env_list+=("GCP_KEYFILE_CONTENT")
        fi
      fi

      if [ -f "$test_file_directory/keyfile.json" ]
      then
        missing_env="${missing_env}🔑 ${GREEN}$test_file_directory/keyfile.json is present${NC}\n"
      fi

      if [ ! -z "$GCP_KEYFILE_CONTENT" ]
      then
        missing_env="${missing_env}🔑 ${GREEN}GCP_KEYFILE_CONTENT is set${NC}\n"
      fi
    fi

    if [ ${#missing_env_list[@]} -gt 0 ]
    then
      oldifs=$IFS
      IFS=$',' missing_env_list_string="${missing_env_list[*]}"
      IFS=$oldifs

      if [ ${#missing_env_list[@]} -eq 1 ]
      then
        MENU_PROBLEM="❌ ${missing_env_list_string} is missing! Click here to fix it"
      else
        MENU_PROBLEM="❌ ${missing_env_list_string} are missing! Click here to fix it"
      fi

      options[1]="$MENU_PROBLEM"
    fi


    if [ $has_error == 0 ]
    then
      unset 'options[1]'
    fi

    oldifs=$IFS
    IFS=$'\n' flag_string="${array_flag_list[*]}"
    IFS=$oldifs

    arm64_support=$(arm64_support)

    if [[ "$arm64_support" == *"❌"* ]]
    then
      unset 'options[0]'
      options[1]="❌🖥️ this example is not working with ARM64 !"
    fi
    preview="${ccloud_preview}\n${missing_env}\n${arm64_support}\n🚀 number of examples ran so far: $(get_cli_metric nb_runs)\n\n⛳ flag list:\n$flag_string\n"
    res=$(printf '%s\n' "${options[@]}" | fzf --multi --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚀" --header="select option(s) for $example (use tab to select more than one)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --preview "echo -e \"$preview\"")

    if [[ $res == *"$MENU_LETS_GO"* ]]
    then
      stop=1
    fi

    if [[ $res == *"$MENU_PROBLEM"* ]]
    then
      for mandatory_environment_variable in ${missing_env_list[*]}
      do
        if [ ! -v $mandatory_environment_variable ]
        then
          set +e
          mandatory_environment_variable_value=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔐" --header="Enter the value for environment variable $mandatory_environment_variable" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_empty_pointer --print-query)
          set -e

          export $mandatory_environment_variable="$mandatory_environment_variable_value"
        fi
      done
    fi

    if [[ $res == *"$MENU_OPEN_FILE"* ]]
    then
      if [[ $test_file == *"fully-managed"* ]] || [[ $test_file == *"custom-"* ]]
      then
        playground open --file "${test_file}"
      else
        playground open --file "${test_file}" --open-docker-compose
      fi
    fi

    if [[ $res == *"$MENU_OPEN_DOCS"* ]]
    then
      if [[ $(type -f open 2>&1) =~ "not found" ]]
      then
        playground open-docs --only-show-url
      else
        playground open-docs
      fi
    fi

    if [[ $res == *"$MENU_GO_BACK"* ]]
    then
      stop=1
      playground run
    fi

    if [[ $res == *"$MENU_ENABLE_KSQLDB"* ]]
    then
      array_flag_list+=("--enable-ksqldb")
      export ENABLE_KSQLDB=true
      interactive_enable_ksqldb="true"
    fi
    if [[ $res == *"$MENU_DISABLE_KSQLDB"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-ksqldb"}")
      unset ENABLE_KSQLDB
      interactive_enable_ksqldb=""
    fi

    if [[ $res == *"$MENU_ENABLE_C3"* ]]
    then
      array_flag_list+=("--enable-control-center")
      export ENABLE_CONTROL_CENTER=true
      interactive_enable_c3="true"
    fi
    if [[ $res == *"$MENU_DISABLE_C3"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-control-center"}")
      unset ENABLE_CONTROL_CENTER
      interactive_enable_c3=""
    fi

    if [[ $res == *"$MENU_ENABLE_FLINK"* ]]
    then
      array_flag_list+=("--enable-flink")
      export ENABLE_FLINK=true
      interactive_enable_flink="true"
    fi
    if [[ $res == *"$MENU_DISABLE_FLINK"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-flink"}")
      unset ENABLE_FLINK
      interactive_enable_flink=""
    fi

    if [[ $res == *"$MENU_ENABLE_RP"* ]]
    then
      array_flag_list+=("--enable-rest-proxy")
      export ENABLE_RESTPROXY=true
      interactive_enable_rp="true"
    fi
    if [[ $res == *"$MENU_DISABLE_RP"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-rest-proxy"}")
      unset ENABLE_RESTPROXY
      interactive_enable_rp=""
    fi

    if [[ $res == *"$MENU_ENABLE_CONDUKTOR"* ]]
    then
      array_flag_list+=("--enable-conduktor")
      export ENABLE_CONDUKTOR=true
      interactive_enable_conduktor="true"
    fi 
    if [[ $res == *"$MENU_DISABLE_CONDUKTOR"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-conduktor"}")
      unset ENABLE_CONDUKTOR
      interactive_enable_conduktor=""
    fi

    if [[ $res == *"$MENU_ENABLE_GRAFANA"* ]]
    then
      array_flag_list+=("--enable-jmx-grafana")
      export ENABLE_JMX_GRAFANA=true
      interactive_enable_grafana="true"

    fi
    if [[ $res == *"$MENU_DISABLE_GRAFANA"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-jmx-grafana"}")
      unset ENABLE_JMX_GRAFANA
      interactive_enable_grafana=""
    fi

    if [[ $res == *"$MENU_ENABLE_BROKERS"* ]]
    then
      array_flag_list+=("--enable-multiple-brokers")
      export ENABLE_KAFKA_NODES=true
      interactive_enable_broker="true"
    fi 
    if [[ $res == *"$MENU_DISABLE_BROKERS"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-multiple-brokers"}")
      unset ENABLE_KAFKA_NODES
      interactive_enable_broker=""
    fi

    if [[ $res == *"$MENU_ENABLE_CONNECT_WORKERS"* ]]
    then
      array_flag_list+=("--enable-multiple-connect-workers")
      export ENABLE_CONNECT_NODES=true
      interactive_enable_connect="true"

      # determining the docker-compose file from from test_file
      docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
      docker_compose_file="${test_file_directory}/${docker_compose_file}"
      if [ -f $docker_compose_file ]
      then
        cp $docker_compose_file /tmp/playground-backup-docker-compose.yml
        yq -i '.services.connect2 = .services.connect' /tmp/playground-backup-docker-compose.yml
        yq -i '.services.connect3 = .services.connect' /tmp/playground-backup-docker-compose.yml
        cp /tmp/playground-backup-docker-compose.yml $docker_compose_file
      fi
    fi

    if [[ $res == *"$MENU_DISABLE_CONNECT_WORKERS"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-multiple-connect-workers"}")
      unset ENABLE_CONNECT_NODES
      interactive_enable_connect=""
      if [ -f /tmp/playground-backup-docker-compose.yml ]
      then
        mv /tmp/playground-backup-docker-compose.yml $docker_compose_file
      fi
    fi

    if [[ $res == *"$MENU_ENABLE_KCAT"* ]]
    then
      array_flag_list+=("--enable-kcat")
      export ENABLE_KCAT=true
      interactive_enable_kcat="true"
    fi 
    if [[ $res == *"$MENU_DISABLE_KCAT"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-kcat"}")
      unset ENABLE_KCAT
      interactive_enable_kcat=""
    fi

    if [[ $res == *"$MENU_ENABLE_SQL_DATAGEN"* ]]
    then
      array_flag_list+=("--enable-sql-datagen")
      export SQL_DATAGEN=true
      interactive_enable_sql="true"

      array_flag_list+=("--enable-jmx-grafana")
      export ENABLE_JMX_GRAFANA=true
      interactive_enable_grafana="true"
    fi
    if [[ $res == *"$MENU_DISABLE_SQL_DATAGEN"* ]]
    then
      array_flag_list=("${array_flag_list[@]/"--enable-sql-datagen"}")
      unset SQL_DATAGEN
      interactive_enable_sql=""

      if [[ $test_file != *"fully-managed"* ]]
      then
        array_flag_list=("${array_flag_list[@]/"--enable-jmx-grafana"}")
        unset ENABLE_JMX_GRAFANA
        interactive_enable_grafana=""
      fi
    fi

    if [[ $res == *"$MENU_ENVIRONMENT"* ]]
    then
      maybe_remove_flag "--environment"

      options=(plaintext ccloud 2way-ssl kerberos ldap-authorizer-sasl-plain ldap-sasl-plain rbac-sasl-plain sasl-plain sasl-scram sasl-ssl ssl_kerberos)
      environment=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔐" --header="select an environment" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
      
      array_flag_list+=("--environment=$environment")
      export PLAYGROUND_ENVIRONMENT=$environment
    fi 

    if [[ $res == *"$MENU_TAG"* ]]
    then
      maybe_remove_flag "--tag"

      tag=$(playground get-tag-list)
      if [[ $tag == *"@"* ]]
      then
        tag=$(echo "$tag" | cut -d "@" -f 2)
      fi
      array_flag_list+=("--tag=$tag")
      export TAG=$tag
    fi

    if [[ $res == *"$MENU_CONNECTOR_TAG"* ]]
    then
      maybe_remove_flag "--connector-zip"
      maybe_remove_flag "--connector-tag"
      connector_tags=""
      for connector_path in ${connector_paths//,/ }
      do
        full_connector_name=$(basename "$connector_path")
        owner=$(echo "$full_connector_name" | cut -d'-' -f1)
        name=$(echo "$full_connector_name" | cut -d'-' -f2-)

        if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
        then
          # happens when plugin is not coming from confluent hub
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
      array_flag_list+=("--connector-tag=$connector_tag")
      export CONNECTOR_TAG="$connector_tag"
    fi

    if [[ $res == *"$MENU_CONNECTOR_ZIP"* ]]
    then
      maybe_remove_flag "--connector-zip"
      maybe_remove_flag "--connector-tag"
      maybe_remove_flag "--connector-jar"
      cd $test_file_directory
      connector_zip=$(playground get-zip-or-jar-with-fzf --type zip)
      if [[ $connector_zip == *"@"* ]]
      then
        connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
      fi
      array_flag_list+=("--connector-zip=$connector_zip")
      export CONNECTOR_ZIP=$connector_zip
    fi

    if [[ $res == *"$MENU_CONNECTOR_JAR"* ]]
    then
      maybe_remove_flag "--connector-zip"
      maybe_remove_flag "--connector-jar"
      cd $test_file_directory
      connector_jar=$(playground get-zip-or-jar-with-fzf --type jar)
      if [[ $connector_jar == *"@"* ]]
      then
        connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
      fi
      array_flag_list+=("--connector-jar=$connector_jar")
      export CONNECTOR_JAR=$connector_jar
    fi

    if [[ $res == *"$MENU_CLUSTER_TYPE"* ]]
    then
      maybe_remove_flag "--cluster-type"
      options=(basic standard dedicated)
      cluster_type=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔋" --header="select a cluster type" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
      array_flag_list+=("--cluster-type $cluster_type")
    fi

    if [[ $res == *"$MENU_CLUSTER_CLOUD"* ]]
    then
      maybe_remove_flag "--cluster-cloud"
      options=(aws gcp azure)
      cluster_cloud=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔋" --header="select a cluster type" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
      array_flag_list+=("--cluster-cloud $cluster_cloud")
    fi

    if [[ $res == *"$MENU_CLUSTER_REGION"* ]]
    then
      maybe_remove_flag "--cluster-region"
      cluster_region=$(playground get-kafka-region-list $cluster_cloud)
      
      if [[ $cluster_region == *"@"* ]]
      then
        cluster_region=$(echo "$cluster_region" | cut -d "@" -f 2)
      fi
      cluster_region=$(echo "$cluster_region" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
      array_flag_list+=("--cluster-region $cluster_region")
    fi

    if [[ $res == *"$MENU_CLUSTER_ENVIRONMENT"* ]]
    then
      maybe_remove_flag "--cluster-environment"
      cluster_environment=$(playground get-ccloud-environment-list)
      
      if [[ $cluster_environment == *"@"* ]]
      then
        cluster_environment=$(echo "$cluster_environment" | cut -d "@" -f 1)
      fi
      if [[ $cluster_environment == *"/"* ]]
      then
        cluster_environment=$(echo "$cluster_environment" | sed 's/[[:blank:]]//g' | cut -d "/" -f 1)
      fi
      array_flag_list+=("--cluster-environment $cluster_environment")
    fi

    if [[ $res == *"$MENU_CLUSTER_NAME"* ]]
    then
      maybe_remove_flag "--cluster-name"
      cluster_name=$(playground get-ccloud-cluster-list)
      
      if [[ $cluster_name == *"@"* ]]
      then
        cluster_name=$(echo "$cluster_name" | cut -d "@" -f 2)
      fi
      if [[ $cluster_name == *"/"* ]]
      then
        cluster_name=$(echo "$cluster_name" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
      fi
      array_flag_list+=("--cluster-name $cluster_name")
    fi

    if [[ $res == *"$MENU_CLUSTER_CREDS"* ]]
    then
      maybe_remove_flag "--cluster-creds"
      set +e
      cluster_creds=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔐" --header="Enter the Kafka api key and secret to use, it should be separated with colon (example: <API_KEY>:<API_KEY_SECRET>)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_empty_pointer --print-query)
      set -e
      array_flag_list+=("--cluster-creds $cluster_creds")
    fi

    if [[ $res == *"$MENU_CLUSTER_SR_CREDS"* ]]
    then
      maybe_remove_flag "--cluster-schema-registry-creds"
      set +e
      cluster_schema_registry_creds=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔐" --header="Enter the Schema Registry api key and secret to use, it should be separated with colon (example: <SR_API_KEY>:<SR_API_KEY_SECRET>)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_empty_pointer --print-query)
      set -e
      array_flag_list+=("--cluster-schema-registry-creds $cluster_schema_registry_creds")
    fi
  done # end while loop stop

  if [ "$interactive_enable_ksqldb" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-ksqldb ENABLE_KSQLDB
    fi
  fi

  if [ "$interactive_enable_rp" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-rest-proxy ENABLE_RESTPROXY
    fi
  fi

  if [ "$interactive_enable_c3" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-control-center ENABLE_CONTROL_CENTER
    fi
  fi

  if [ "$interactive_enable_flink" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-flink ENABLE_FLINK
    fi
  fi

  if [ "$interactive_enable_conduktor" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-conduktor ENABLE_CONDUKTOR
    fi
  fi

  if [ "$interactive_enable_broker" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-multiple-brokers ENABLE_KAFKA_NODES
    fi
  fi

  if [ "$interactive_enable_connect" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-multiple-connect-workers ENABLE_CONNECT_NODES
    fi
  fi

  if [ "$interactive_enable_grafana" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-jmx-grafana ENABLE_JMX_GRAFANA
    fi
  fi

  if [ "$interactive_enable_kcat" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-kcat ENABLE_KCAT
    fi
  fi

  if [ "$interactive_enable_sql" == "true" ]
  then
    if [[ $test_file != *"fully-managed"* ]]
    then
      log "📊 automatically enabling Grafana as --enable-sql-datagen is set"
      if [[ -n "$force_interactive_repro" ]]
      then
        force_enable --enable-sql-datagen SQL_DATAGEN
        force_enable --enable-jmx-grafana ENABLE_JMX_GRAFANA
      fi
    fi
  fi

  if [[ -n "$cluster_type" ]] || [[ -n "$cluster_cloud" ]] || [[ -n "$cluster_region" ]] || [[ -n "$cluster_environment" ]] || [[ -n "$cluster_name" ]] || [[ -n "$cluster_creds" ]] || [[ -n "$cluster_schema_registry_creds" ]]
  then
    playground state set ccloud.suggest_use_previous_example_ccloud "0"

    if [[ -n "$cluster_type" ]]
    then
      export CLUSTER_TYPE=$cluster_type
    fi

    # default
    if [ -z "$CLUSTER_TYPE" ]
    then
      export CLUSTER_TYPE="basic"
    fi

    if [[ -n "$cluster_cloud" ]]
    then
      export CLUSTER_CLOUD=$cluster_cloud
    fi

    # default
    if [ -z "$CLUSTER_CLOUD" ]
    then
      export CLUSTER_CLOUD="aws"
    fi

    if [[ -n "$cluster_region" ]]
    then
      export CLUSTER_REGION=$cluster_region
    fi

    # default
    if [ -z "$CLUSTER_REGION" ]
    then
      case "${CLUSTER_CLOUD}" in
        aws)
          export CLUSTER_REGION="eu-west-2"
        ;;
        azure)
          export CLUSTER_REGION="westeurope"
        ;;
        gcp)
          export CLUSTER_REGION="europe-west2"
        ;;
      esac
    fi

    if [[ -n "$cluster_type" ]]
    then
      export CLUSTER_TYPE=$cluster_type
    fi

    if [[ -n "$cluster_environment" ]]
    then
      export ENVIRONMENT=$cluster_environment
    fi

    if [[ -n "$cluster_name" ]]
    then
      export CLUSTER_NAME=$cluster_name
    fi

    if [[ -n "$cluster_creds" ]]
    then
      export CLUSTER_CREDS=$cluster_creds
    fi

    if [[ -n "$cluster_schema_registry_creds" ]]
    then
      export SCHEMA_REGISTRY_CREDS=$cluster_schema_registry_creds
    fi
  else
    playground state set ccloud.suggest_use_previous_example_ccloud "1"
  fi
fi # end of interactive_mode

IFS=' ' flag_list="${array_flag_list[*]}"
array_declaration=$(declare -p array_flag_list)
encoded_array=$(echo "$array_declaration" | base64)
playground state set run.array_flag_list_base64 "$encoded_array"

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

playground state set run.connector_type "$(get_connector_type | tr -d '\n')"
playground state set run.test_file "$test_file"
echo "" >> "$root_folder/playground-run-history"
echo "playground run -f $test_file $flag_list" >> "$root_folder/playground-run-history"

if [[ "$OSTYPE" == "darwin"* ]]
then
    clipboard=$(playground config get clipboard)
    if [ "$clipboard" == "" ]
    then
        playground config set clipboard true
    fi

    if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
    then
        echo "playground run -f $test_file $flag_list" | pbcopy
        log "📋 command to run again example has been copied to the clipboard (disable with 'playground config clipboard false')"
    fi
fi

increment_cli_metric nb_runs
log "🚀 Number of examples ran so far: $(get_cli_metric nb_runs)"
playground get-ci-result
log "####################################################"
log "🚀 Executing $filename in dir $test_file_directory"
log "####################################################"
SECONDS=0
cd $test_file_directory
function cleanup {
  if [[ -n "$enable_multiple_connect_workers" ]]
  then
    if [ -f /tmp/playground-backup-docker-compose.yml ]
    then
      mv /tmp/playground-backup-docker-compose.yml $docker_compose_file
    fi
  fi
  rm /tmp/playground-run-command-used
  echo ""
  sleep 3
  set +e

  connector_type=$(playground state get run.connector_type)
  
  if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
    if [ "$connector_name" != "" ]
    then
      playground connector status --connector "$connector_name"
    fi
  elif [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
  then
    playground connector status
  fi

  playground open-docs --only-show-url
 
  if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
  then
    playground connector versions
    playground connector open-docs --only-show-url
  fi
  set -e
}
trap cleanup EXIT

playground generate-fzf-find-files &
generate_connector_versions > /dev/null 2>&1 &
touch /tmp/playground-run-command-used
set +e
bash $filename
ret=$?
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
let ELAPSED_TOTAL+=$SECONDS
# keep those lists up to date
playground generate-tag-list > /dev/null 2>&1 &
playground generate-connector-plugin-list > /dev/null 2>&1 &
playground generate-kafka-region-list > /dev/null 2>&1 &
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

  log "🧑‍🚒 you can troubleshoot the issue by running:"
  echo "playground container display-error-all-containers"
  log "🧑‍🚒 open full logs with '<playground container logs --open --container <container>', example:"
  echo "playground container logs --open --container connect"

  exit 1
fi
check_for_ec2_instance_running

if [ ! -z "$ENABLE_JMX_GRAFANA" ]
then
  echo ""
  if [[ $test_file == *"ccloud"* ]]
  then
    log "🛡️ Prometheus is reachable at http://127.0.0.1:9090"
    log "📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password)"
  else
    log "📛 Pyroscope is reachable at http://127.0.0.1:4040"
    log "🛡️ Prometheus is reachable at http://127.0.0.1:9090"
    log "📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password) or JMX metrics are available locally on those ports:"
  fi

  if [ -z "$GITHUB_RUN_NUMBER" ]
  then
    automatically=$(playground config get open-grafana-in-browser.automatically)
    if [ "$automatically" == "" ]
    then
        playground config set open-grafana-in-browser.automatically true
    fi

    browser=$(playground config get open-grafana-in-browser.browser)
    if [ "$browser" == "" ]
    then
        playground config set open-grafana-in-browser.browser ""
    fi

    if [ "$automatically" == "true" ] || [ "$automatically" == "" ]
    then

      if [[ $(type -f open 2>&1) =~ "not found" ]]
      then
        log "🔗 Cannot open browser, use url:"
        echo "http://127.0.0.1:3000"
      else
        if [ "$browser" != "" ]
        then
          log "🤖 automatically (disable with 'playground config open-grafana-in-browser automatically false') open grafana in browser $browser (you can change browser with 'playground config open-grafana-in-browser browser <browser>')"
          log "🤖 Open grafana with browser $browser (login/password is admin/password)"
          open -a "$browser" "http://127.0.0.1:3000"
        else
          log "🤖 automatically (disable with 'playground config open-grafana-in-browser automatically false') open grafana in default browser (you can set browser with 'playground config open-grafana-in-browser browser <browser>')"
          log "🤖 Open grafana (login/password is admin/password)"
          open "http://127.0.0.1:3000"
        fi
      fi
    fi
  fi
fi

if [ -z "$GITHUB_RUN_NUMBER" ]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    echo ""
    # wait that process with "playground ccloud-costs-history" is finished
    set +e
    while pgrep -f "playground ccloud-costs-history" > /dev/null
    do
      log "⌛ wait for monthly ccloud costs..."
      sleep 5
    done
    set -e
    if [ -f /tmp/ccloud-costs-history.txt ]
    then
      log "📅💰 monthly ccloud costs"
      cat /tmp/ccloud-costs-history.txt
    fi
    log "👀 if you want more details, run <playground ccloud-costs-history --detailed>"
  fi
fi