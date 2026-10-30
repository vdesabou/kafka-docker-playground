DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

test_file="${args[--file]}"
open="${args[--open]}"
environment="${args[--environment]}"
tag="${args[--tag]}"
connect_tag="${args[--connect-tag]}"
schema_registry_tag="${args[--schema-registry-tag]}"
ksqldb_tag="${args[--ksqldb-tag]}"
control_center_tag="${args[--control-center-tag]}"
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
benchmark="${args[--benchmark]}"
connect_community_image="${args[--connect-community-image]}"
kafka_community_image="${args[--kafka-community-image]}"
enable_kraft="${args[--enable-kraft]}"
enable_legacy_c3="${args[--enable-legacy-control-center]}"
connect_log_level="${args[--connect-log-level]}"

cluster_type="${args[--cluster-type]}"
cluster_cloud="${args[--cluster-cloud]}"
cluster_region="${args[--cluster-region]}"
cluster_environment="${args[--cluster-environment]}"
cluster_name="${args[--cluster-name]}"
cluster_creds="${args[--cluster-creds]}"
cluster_schema_registry_creds="${args[--cluster-schema-registry-creds]}"
ccloud_service_account="${args[--ccloud-service-account]}"
ccloud_service_account_acls="${args[--ccloud-service-account-acls]}"
ccloud_service_account_id="${args[--ccloud-service-account-id]}"
force_interactive_re_run="${args[--force-interactive-re-run]}"
force_interactive_repro="${args[--force-interactive-repro]}"
run_log_file_flag="${args[--run-log-file]}"
no_run_log_flag="${args[--no-run-log]}"

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
  test_file=${test_file#*@}
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

#
# 🔐 Resolve, from the secrets store, the variables this example needs and that
# are not already exported. Scoped to the example's own list on purpose: no
# blanket 'set -o allexport' that would leak every credential into every
# process for the rest of the session.
#
load_secrets_for_example "$test_file" "${environment:-$PLAYGROUND_ENVIRONMENT}"
if [[ $test_file == *"ccloud"* ]] || [ "${environment:-$PLAYGROUND_ENVIRONMENT}" == "ccloud" ]
then
  ccloud_secrets_loaded=1
fi

#
# 🔐 Pre-flight for non interactive runs. In interactive mode the fzf menu
# already refuses to start with a missing variable; without it the example used
# to fail minutes later, after the whole environment had started. It has to stay
# before the container kill-all below, otherwise a missing variable costs the
# user the environment they already had running.
#
# Skipped in CI, so that an example keeps its own control over its exit code
# (111 = unsupported combination, 107 = known issue).
#
if [ $interactive_mode != 1 ] && [ -z "$GITHUB_RUN_NUMBER" ]
then
  missing_mandatory_env=""
  for mandatory_environment_variable in $(get_mandatory_env_vars "$test_file")
  do
    if [ -z "${!mandatory_environment_variable:-}" ]
    then
      missing_mandatory_env="${missing_mandatory_env} ${mandatory_environment_variable}"
    fi
  done

  if [ -n "$missing_mandatory_env" ]
  then
    logerror "❌ Cannot run $test_file, missing environment variable(s):${missing_mandatory_env}"
    for mandatory_environment_variable in $missing_mandatory_env
    do
      logerror "👉 playground secrets set $mandatory_environment_variable"
    done
    exit 1
  fi
fi

if [[ $test_file == *"ccloud"* ]]
then
  verify_installed "confluent"
fi

# 'playground stop' (below, once the example is really started) relies on the
# previous run.test_file, which is overwritten right after
previous_test_file=$(playground state get run.test_file)
playground state set run.test_file "$test_file"
# until the example is really started (menu validated, flags checked), quitting
# (esc, ctrl-c, an invalid combination) must not leave run.test_file on it
trap 'playground state set run.test_file "$previous_test_file"' EXIT
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
    tag=${tag#*@}
  fi
  array_flag_list+=("--tag=$tag")
  export TAG=$tag
fi

if [[ -n "$connect_tag" ]]
then
  if [[ $connect_tag == *"@"* ]]
  then
    connect_tag=${connect_tag#*@}
  fi
  array_flag_list+=("--connect-tag=$connect_tag")
  export CP_CONNECT_TAG=$connect_tag
fi

if [[ -n "$schema_registry_tag" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --schema-registry-tag is not supported with ccloud examples"
    exit 1
  fi
  schema_registry_tag=${schema_registry_tag#*@}
  array_flag_list+=("--schema-registry-tag=$schema_registry_tag")
  export CP_SCHEMA_REGISTRY_TAG=$schema_registry_tag
fi

if [[ -n "$ksqldb_tag" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --ksqldb-tag is not supported with ccloud examples"
    exit 1
  fi
  ksqldb_tag=${ksqldb_tag#*@}
  array_flag_list+=("--ksqldb-tag=$ksqldb_tag")
  # same version for the CLI
  export CP_KSQL_TAG=$ksqldb_tag
  export CP_KSQL_CLI_TAG=$ksqldb_tag
fi

if [[ -n "$control_center_tag" ]]
then
  array_flag_list+=("--control-center-tag=$control_center_tag")
  export CP_CONTROL_CENTER_TAG=$control_center_tag
fi

if [[ -n "$environment" ]]
then
  if [ -z "${connector_paths:-}" ]; then get_connector_paths; fi
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
    if [ -z "${connector_paths:-}" ]; then get_connector_paths; fi
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
    connector_zip=${connector_zip#*@}
  fi
  array_flag_list+=("--connector-zip=$connector_zip")
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  if [[ $connector_jar == *"@"* ]]
  then
    connector_jar=${connector_jar#*@}
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
  # connect2 and connect3 get the connect configuration of the example in start-environment
  export ENABLE_CONNECT_NODES=true
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
  # rows are injected by this command once the example is done (see sql_datagen_inject), with the benchmark-load.bash of
  # the example: not SQL_DATAGEN, which the examples and reproduction models of the former Java datagen still test
  export ENABLE_SQL_DATAGEN=true

  if [[ $test_file != *"fully-managed"* ]]
  then
    log "📊 automatically enabling Grafana as --enable-sql-datagen is set"
    array_flag_list+=("--enable-jmx-grafana")
    export ENABLE_JMX_GRAFANA=true

    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-sql-datagen ENABLE_SQL_DATAGEN
      force_enable --enable-jmx-grafana ENABLE_JMX_GRAFANA
    fi
  fi
fi

if [[ -n "$benchmark" ]]
then
  array_flag_list+=("--benchmark")
  # playground connector benchmark is run by this command once the example is done
  export ENABLE_BENCHMARK=true

  if [[ -n "$force_interactive_repro" ]]
  then
    force_enable --benchmark ENABLE_BENCHMARK
  fi
fi

if [[ -n "$connect_community_image" ]]
then
  if [[ $test_file == *"fully-managed"* ]]
  then
    logwarn "❌ --connect-community-image is not supported with fully managed connector examples"
    exit 1
  fi
  array_flag_list+=("--connect-community-image")
  export CP_CONNECT_IMAGE=confluentinc/cp-kafka-connect
fi

if [[ -n "$kafka_community_image" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --kafka-community-image is not supported with ccloud examples"
    exit 1
  fi
  array_flag_list+=("--kafka-community-image")
  export CP_KAFKA_IMAGE=confluentinc/cp-kafka
fi

if [[ -n "$enable_kraft" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-kraft is not supported with ccloud examples"
    exit 1
  fi
  array_flag_list+=("--enable-kraft")
  export ENABLE_KRAFT=true
fi

if [[ -n "$enable_legacy_c3" ]]
then
  array_flag_list+=("--enable-legacy-control-center")
  export ENABLE_LEGACY_CONTROL_CENTER=true
fi

if [[ -n "$connect_log_level" ]]
then
  if [[ $test_file == *"fully-managed"* ]]
  then
    logwarn "❌ --connect-log-level is not supported with fully managed connector examples"
    exit 1
  fi
  array_flag_list+=("--connect-log-level=$connect_log_level")
  export PLAYGROUND_CONNECT_LOG_LEVELS="$connect_log_level"
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
  # bootstrap_ccloud_environment forces AWS_/GCP_/AZURE_/AWS_DATABRICKS_CLUSTER_NAME
  # on fully managed examples, which would override the flags
  for prefix in AWS_ GCP_ AZURE_ AWS_DATABRICKS_
  do
    for item in CLUSTER_NAME CLUSTER_CLOUD CLUSTER_REGION CLUSTER_CREDS
    do
      var="${prefix}${item}"
      if [ ! -z "${!var}" ]
      then
        log "🙈 ignoring environment variable $var as one of the flags is set"
        unset "$var"
      fi
    done
  done
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
    cluster_environment=${cluster_environment#*@}
  fi
  if [[ $cluster_environment == *"/"* ]]
  then
    cluster_environment=${cluster_environment//[$' \t']/}
    cluster_environment=${cluster_environment#*/}
  fi
  array_flag_list+=("--cluster-environment $cluster_environment")
  export ENVIRONMENT=$cluster_environment
fi

if [[ -n "$cluster_name" ]]
then
  if [[ $cluster_name == *"@"* ]]
  then
    cluster_name=${cluster_name#*@}
  fi
  if [[ $cluster_name == *"/"* ]]
  then
    cluster_name=${cluster_name//[$' \t']/}
    cluster_name=${cluster_name#*/}
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

if [[ -n "$ccloud_service_account" ]] || [[ -n "$ccloud_service_account_acls" ]] || [[ -n "$ccloud_service_account_id" ]]
then
  if [[ $test_file != *"fully-managed"* ]] && [[ $test_file != *"custom-"* ]]
  then
    logerror "❌ --ccloud-service-account is only supported with fully managed and custom connector examples"
    exit 1
  fi
  array_flag_list+=("--ccloud-service-account")
  # read by playground connector create-or-update
  export PG_CCLOUD_SERVICE_ACCOUNT=true
  if [[ -n "$ccloud_service_account_acls" ]]
  then
    array_flag_list+=("--ccloud-service-account-acls $ccloud_service_account_acls")
    export PG_CCLOUD_SERVICE_ACCOUNT_ACLS=$ccloud_service_account_acls
  fi
  if [[ -n "$ccloud_service_account_id" ]]
  then
    array_flag_list+=("--ccloud-service-account-id $ccloud_service_account_id")
    export PG_CCLOUD_SERVICE_ACCOUNT_ID=$ccloud_service_account_id
  fi

  if [[ -n "$force_interactive_repro" ]]
  then
    force_enable --ccloud-service-account PG_CCLOUD_SERVICE_ACCOUNT
    if [[ -n "$ccloud_service_account_acls" ]]
    then
      force_enable --ccloud-service-account-acls PG_CCLOUD_SERVICE_ACCOUNT_ACLS "$ccloud_service_account_acls"
    fi
  fi
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
  fzf_version=$(get_fzf_version)
  if [[ $terminal_columns -gt 180 ]]
  then
    MAX_LENGTH=$((${terminal_columns}-120))
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
  
  MENU_PROBLEM="❌ The example cannot be executed, check error(s) 👉"
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

  MENU_TAG="$(menu_label "🎯" "CP version (all components)" "--tag")"
  MENU_CONNECT_TAG="$(menu_label "🔗" "CP version (connect only)" "--connect-tag")"
  MENU_SCHEMA_REGISTRY_TAG="$(menu_label "🔰" "CP version (schema registry only)" "--schema-registry-tag")"
  MENU_KSQLDB_TAG="$(menu_label "🎏" "CP version (ksqlDB only)" "--ksqldb-tag")"
  MENU_CONTROL_CENTER_TAG="$(menu_label "💠" "Control Center version" "--control-center-tag")"
  MENU_CONNECTOR_TAG="$(menu_label "🔌" "Connector version" "--connector-tag")"
  MENU_CONNECTOR_ZIP="$(menu_label "🤐" "Connector zip" "--connector-zip")"
  MENU_CONNECTOR_JAR="$(menu_label "🤎" "Connector jar" "--connector-jar")"
  MENU_ENVIRONMENT="$(menu_label "🔐" "Environment" "--environment")"

  readonly MENU_SEPARATOR="--------------------------------------------------"

  MENU_KSQLDB="$(menu_label "🎏" "ksqlDB" "--enable-ksqldb" 4)"
  MENU_C3="$(menu_label "💠" "Control Center" "--enable-control-center" 4)"
  MENU_CONDUKTOR="$(menu_label "🐺" "Conduktor Platform" "--enable-conduktor" 4)"
  MENU_RP="$(menu_label "🧲" "Rest Proxy" "--enable-rest-proxy" 4)"
  MENU_GRAFANA="$(menu_label "📊" "Grafana" "--enable-jmx-grafana" 4)"
  MENU_BROKERS="$(menu_label "🔢" "Multiple brokers" "--enable-multiple-brokers" 4)"
  MENU_CONNECT_WORKERS="$(menu_label "🥉" "Multiple connect workers" "--enable-multiple-connect-workers" 4)"
  MENU_KCAT="$(menu_label "🐈" "kcat" "--enable-kcat" 4)"
  MENU_SQL_DATAGEN="$(menu_label "🌀" "SQL Datagen injection" "--enable-sql-datagen" 4)"
  MENU_BENCHMARK="$(menu_label "🏎️" "Benchmark the connector" "--benchmark" 4)"
  MENU_CCLOUD_SERVICE_ACCOUNT="$(menu_label "👤" "Connector service account" "--ccloud-service-account" 4)"
  MENU_FLINK="$(menu_label "🐹" "Flink" "--enable-flink" 4)"
  MENU_CONNECT_COMMUNITY_IMAGE="$(menu_label "🌱" "Community connect image" "--connect-community-image" 4)"
  MENU_KAFKA_COMMUNITY_IMAGE="$(menu_label "🌿" "Community kafka image" "--kafka-community-image" 4)"
  MENU_KRAFT="$(menu_label "📡" "KRaft (CP 7.4 to 7.9)" "--enable-kraft" 4)"
  MENU_LEGACY_C3="$(menu_label "🧓" "Legacy Control Center (CP < 8)" "--enable-legacy-control-center" 4)"


  readonly MENU_SEPARATOR_FEATURES="--------------------options-----------------------"

  MENU_CLUSTER_TYPE="$(menu_label "🔋" "Cluster type" "--cluster-type")"
  MENU_CLUSTER_CLOUD="$(menu_label "⛅" "Cloud provider" "--cluster-cloud")"
  MENU_CLUSTER_REGION="$(menu_label "🧭" "Cloud region" "--cluster-region")"
  MENU_CLUSTER_ENVIRONMENT="$(menu_label "🌐" "Environment id" "--cluster-environment")"

  MENU_CLUSTER_NAME="$(menu_label "🎰" "Cluster name" "--cluster-name")"
  MENU_CLUSTER_CREDS="$(menu_label "🔒" "Kafka api key & secret" "--cluster-creds")"
  MENU_CLUSTER_SR_CREDS="$(menu_label "🔰" "Schema registry api key & secret" "--cluster-schema-registry-creds")"
  MENU_CCLOUD_SERVICE_ACCOUNT_ACLS="$(menu_label "🚦" "Service account ACLs" "--ccloud-service-account-acls")"
  MENU_CCLOUD_SERVICE_ACCOUNT_ID="$(menu_label "🪪" "Existing service account" "--ccloud-service-account-id")"

  MENU_UNSET_CLUSTER_NAME="❌🎰🎯 Unset cluster name (will also reset cloud region, cluster type and cloud provider)"

  readonly MENU_SEPARATOR_CLOUD="-----------------confluent cloud------------------"
  readonly MENU_SEPARATOR_IMAGES="------------------images & modes------------------"
  MENU_CONNECT_LOG_LEVEL="$(menu_label "🔊" "Connect log level(s)" "--connect-log-level")"
  readonly MENU_SWITCH_EXAMPLE="🔀 Switch to another example in the same folder"
  readonly MENU_REPRO_BOOTSTRAP="🧪 Create a reproduction model from this example"
  readonly MENU_CONFIG="⚙️  CLI preferences (playground config)"
  readonly MENU_SEPARATOR_ACTIONS="---------------------actions----------------------"

  readonly MENU_GO_BACK="🔙 Go back"



  last_two_folders=$(basename $(dirname $(dirname $test_file)))/$(basename $(dirname $test_file))
  example="$last_two_folders/$filename"

  connector_example=0
  if [ -z "${connector_paths:-}" ]; then get_connector_paths; fi
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
  if [[ $test_file == *"connect-debezium-sqlserver"* ]] || [[ $test_file == *"connect-debezium-mysql"* ]] || [[ $test_file == *"connect-debezium-mariadb"* ]] || [[ $test_file == *"connect-jdbc-mariadb"* ]] || [[ $test_file == *"fm-jdbc-mysql"* ]] || [[ $test_file == *"connect-debezium-postgresql"* ]] || [[ $test_file == *"connect-debezium-oracle"* ]] || [[ $test_file == *"connect-cdc-oracle"* ]] || [[ $test_file == *"connect-jdbc-sqlserver"* ]] || [[ $test_file == *"connect-jdbc-mysql"* ]] || [[ $test_file == *"connect-jdbc-postgresql"* ]] || [[ $test_file == *"connect-jdbc-oracle"* ]] || [[ $test_file == *"connect-cdc-xstream"* ]] || [[ $test_file == *"fm-debezium"* ]] || [[ $test_file == *"fm-cdc"* ]]
  then
    sql_datagen=1
  fi

  # playground connector benchmark needs a load: the benchmark-load.bash of a source, or the topic produce of a sink
  benchmark_available=0
  if [ -f "$test_file_directory/benchmark-load.bash" ] || grep -q "playground topic produce" "$test_file"
  then
    benchmark_available=1
  fi

  # environments the example can be run with (empty: it starts its own)
  supported_environments=$(get_example_supported_environments "$test_file")

  # other examples in the same folder (variants of this one)
  sibling_examples=$(find "$test_file_directory" -maxdepth 1 -name "*.sh" ! -name "stop.sh" ! -name "$filename" -exec basename {} \; | sort)

  # Precompute mandatory env var names from the example (once)
  declare -a mandatory_env_vars=()
  while IFS= read -r __mev; do
    [ -n "$__mev" ] && mandatory_env_vars+=("$__mev")
  done < <(get_mandatory_env_vars "$test_file")

  stop=0
  while [ $stop != 1 ]
  do
    has_error=0

    if [[ $test_file == *"ccloud"* ]] || [ "$PLAYGROUND_ENVIRONMENT" == "ccloud" ]
    then
      # environment switched to ccloud in this menu: same variables as above, only
      # once (the menu can unset them) and never on top of --cluster-* flags
      if [[ ! -n "$ccloud_secrets_loaded" ]] && [[ ! -n "$cluster_name" ]] && [[ ! -n "$cluster_type" ]] && [[ ! -n "$cluster_cloud" ]] && [[ ! -n "$cluster_region" ]]
      then
        load_secrets_env_vars $(get_ccloud_env_vars)
        ccloud_secrets_loaded=1
      fi

      if [ ! -z "$CLUSTER_NAME" ] || [[ -n "$cluster_name" ]]
      then
        if [ ! -z "$CLUSTER_NAME" ]
        then
          cluster_name=$CLUSTER_NAME
          export CLUSTER_NAME=$cluster_name
        fi
        #
        # CLUSTER_NAME is set
        #
        ccloud_preview="🎯 ${YELLOW}cluster-name is set, your existing ccloud cluster will be used...${NC}\n\n"
        ccloud_preview="${ccloud_preview}🎰 ${YELLOW}cluster-name=$cluster_name${NC}\n"

        if [ -z $ENVIRONMENT ] 
        then
          ccloud_preview="${ccloud_preview}❌ 🌐${RED}environment is missing!${NC}\n"
          has_error=1
        else
          ccloud_preview="${ccloud_preview}🌐 ${YELLOW}environment=$ENVIRONMENT${NC}\n"
        fi

        if [ -z $CLUSTER_CLOUD ] 
        then
          ccloud_preview="${ccloud_preview}❌  ${RED}⛅ cluster-cloud is missing!${NC}\n"
          has_error=1
        else
          ccloud_preview="${ccloud_preview}⛅ ${YELLOW}cluster-cloud=$CLUSTER_CLOUD${NC}\n"
        fi
        
        if [ -z $CLUSTER_REGION ] 
        then
          ccloud_preview="${ccloud_preview}❌ ${RED}🧭 cluster-region is missing!${NC}\n"
          has_error=1
        else
          ccloud_preview="${ccloud_preview}🧭 ${YELLOW}cluster-region=$CLUSTER_REGION${NC}\n"
        fi

        if [ -z $CLUSTER_CREDS ] 
        then
          ccloud_preview="${ccloud_preview}❌ ${RED}🔒cluster-creds is missing!${NC}\n"
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
          ccloud_preview="${ccloud_preview}⛅ ${CYAN}cluster-cloud is missing, aws will be used${NC}\n"
        else
          if [ ! -z "$CLUSTER_CLOUD" ]
          then
            cluster_cloud=$CLUSTER_CLOUD
          fi
          ccloud_preview="${ccloud_preview}⛅ ${YELLOW}cluster-cloud=$cluster_cloud${NC}\n"
        fi
        
        if [ -z $CLUSTER_REGION ] && [[ ! -n "$cluster_region" ]]
        then
          ccloud_preview="${ccloud_preview}🧭 ${CYAN}cluster-region is missing, default region for provider will be used${NC}\n"
        else
          if [ ! -z "$CLUSTER_REGION" ]
          then
            cluster_region=$CLUSTER_REGION
          fi
          ccloud_preview="${ccloud_preview}🧭 ${YELLOW}cluster-region=$cluster_region${NC}\n"
        fi
      fi
    fi # end of ccloud

    missing_env=""
    declare -a missing_env_list=()

    # generic check (precomputed list)
    for mandatory_environment_variable in "${mandatory_env_vars[@]}"
    do
      if [ ! -v $mandatory_environment_variable ]
      then
        missing_env="${missing_env}❌ ${RED}${mandatory_environment_variable} is missing!${NC}\n"
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
          has_error=1
        fi

        if [ -z "$AWS_ACCESS_KEY_ID" ]
        then
          missing_env="${missing_env}❌ ${RED}AWS_ACCESS_KEY_ID is missing!${NC}\n"
          has_error=1
          missing_env_list+=("AWS_ACCESS_KEY_ID")
        fi

        if [ -z "$AWS_SECRET_ACCESS_KEY" ]
        then
          missing_env="${missing_env}❌ ${RED}AWS_SECRET_ACCESS_KEY is missing!${NC}\n"
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
          has_error=1
        fi

        if [ -z "$GCP_KEYFILE_CONTENT" ]
        then
          missing_env="${missing_env}❌ ${RED}GCP_KEYFILE_CONTENT is missing!${NC}\n"
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

    # known-bad combinations of the selected options
    combination_preview=""
    while IFS='|' read -r combination_level combination_message
    do
      if [ "$combination_level" == "error" ]
      then
        combination_preview="${combination_preview}❌ ${RED}${combination_message}${NC}\n"
        has_error=1
      elif [ "$combination_level" == "warning" ]
      then
        combination_preview="${combination_preview}⚠️  ${YELLOW}${combination_message}${NC}\n"
      fi
    done < <(get_run_flag_combination_problems)

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

    else
      MENU_PROBLEM="❌ The example cannot be executed, check error(s) 👉"
    fi

    oldifs=$IFS
    IFS=$'\n' flag_string="${array_flag_list[*]}"
    IFS=$oldifs

    arm64_support=$(arm64_support)

    if [[ "$arm64_support" == *"❌"* ]]
    then
      has_error=1
      MENU_PROBLEM="❌💻 this example is not working with ARM64 !"
    fi

    #
    # 🍔 build the menu: an entry is only added when it applies to this example
    #
    is_ccloud=0
    if [[ $test_file == *"ccloud"* ]] || [ "$PLAYGROUND_ENVIRONMENT" == "ccloud" ]
    then
      is_ccloud=1
    fi
    # no local connect (versions, profiles...)
    is_fully_managed=0
    if [[ $test_file == *"fully-managed"* ]]
    then
      is_fully_managed=1
    fi

    options=()

    group=()
    if [ $has_error == 0 ]; then group+=("$MENU_LETS_GO"); else group+=("$MENU_PROBLEM"); fi
    group+=("$MENU_OPEN_FILE")
    if [ $docs_available == 1 ]; then group+=("$MENU_OPEN_DOCS"); fi
    add_menu_group "$MENU_SEPARATOR" "${group[@]}"

    group=()
    if [ $is_fully_managed == 0 ]
    then
      group+=("$(menu_value_label "$MENU_TAG" "$(get_menu_flag_value --tag)")")
      group+=("$(menu_value_label "$MENU_CONNECT_TAG" "$(get_menu_flag_value --connect-tag)")")
      # schema registry is in Confluent Cloud for ccloud examples
      if [ $is_ccloud == 0 ]; then group+=("$(menu_value_label "$MENU_SCHEMA_REGISTRY_TAG" "$(get_menu_flag_value --schema-registry-tag)")"); fi
      if [ -n "$ENABLE_KSQLDB" ]; then group+=("$(menu_value_label "$MENU_KSQLDB_TAG" "$(get_menu_flag_value --ksqldb-tag)")"); fi
      # --enable-legacy-control-center implies --enable-control-center
      if [ -n "$ENABLE_CONTROL_CENTER" ] || [[ " ${array_flag_list[*]} " == *" --enable-legacy-control-center "* ]]; then group+=("$(menu_value_label "$MENU_CONTROL_CENTER_TAG" "$(get_menu_flag_value --control-center-tag)")"); fi
      if [ $connector_example == 1 ]
      then
        group+=("$(menu_value_label "$MENU_CONNECTOR_TAG" "$(get_menu_flag_value --connector-tag)")")
        menu_connector_zip=$(get_menu_flag_value --connector-zip)
        group+=("$(menu_value_label "$MENU_CONNECTOR_ZIP" "${menu_connector_zip##*/}")")
        menu_connector_jar=$(get_menu_flag_value --connector-jar)
        group+=("$(menu_value_label "$MENU_CONNECTOR_JAR" "${menu_connector_jar##*/}")")
      fi
      # same rule as the --environment flag, and only if the example lets you choose
      if [ "$connector_paths" != "" ] && [ -n "$supported_environments" ]; then group+=("$(menu_value_label "$MENU_ENVIRONMENT" "$(get_menu_flag_value --environment)")"); fi
    fi
    add_menu_group "$MENU_SEPARATOR" "${group[@]}"

    toggle_group=()
    add_menu_toggle $((1-is_fully_managed)) "$ENABLE_KSQLDB" "$MENU_KSQLDB"
    add_menu_toggle $((1-is_fully_managed)) "$ENABLE_CONTROL_CENTER" "$MENU_C3"
    add_menu_toggle $((1-is_fully_managed)) "$ENABLE_CONDUKTOR" "$MENU_CONDUKTOR"
    add_menu_toggle $((1-is_ccloud)) "$ENABLE_RESTPROXY" "$MENU_RP"
    add_menu_toggle $((1-is_ccloud)) "$ENABLE_JMX_GRAFANA" "$MENU_GRAFANA"
    add_menu_toggle $((1-is_ccloud)) "$ENABLE_KAFKA_NODES" "$MENU_BROKERS"
    add_menu_toggle $((1-is_ccloud)) "$ENABLE_CONNECT_NODES" "$MENU_CONNECT_WORKERS"
    add_menu_toggle $((1-is_fully_managed)) "$ENABLE_KCAT" "$MENU_KCAT"
    add_menu_toggle $sql_datagen "$ENABLE_SQL_DATAGEN" "$MENU_SQL_DATAGEN"
    add_menu_toggle $benchmark_available "$ENABLE_BENCHMARK" "$MENU_BENCHMARK"
    if [[ $test_file == *"fully-managed"* ]] || [[ $test_file == *"custom-"* ]]; then ccloud_service_account_available=1; else ccloud_service_account_available=0; fi
    add_menu_toggle $ccloud_service_account_available "$PG_CCLOUD_SERVICE_ACCOUNT" "$MENU_CCLOUD_SERVICE_ACCOUNT"
    add_menu_toggle $((1-is_fully_managed)) "$ENABLE_FLINK" "$MENU_FLINK"
    add_menu_group "$MENU_SEPARATOR_FEATURES" "${toggle_group[@]}"

    group=()
    if [ $is_ccloud == 1 ]
    then
      group+=("$(menu_value_label "$MENU_CLUSTER_TYPE" "$(get_menu_flag_value --cluster-type)")")
      group+=("$(menu_value_label "$MENU_CLUSTER_CLOUD" "$(get_menu_flag_value --cluster-cloud)")")
      group+=("$(menu_value_label "$MENU_CLUSTER_REGION" "$(get_menu_flag_value --cluster-region)")")
      group+=("$(menu_value_label "$MENU_CLUSTER_ENVIRONMENT" "$(get_menu_flag_value --cluster-environment)")")
      group+=("$(menu_value_label "$MENU_CLUSTER_NAME" "$(get_menu_flag_value --cluster-name)")")
      # never display credentials
      group+=("$(menu_value_label "$MENU_CLUSTER_CREDS" "$([ -n "$(get_menu_flag_value --cluster-creds)" ] && echo set)")")
      group+=("$(menu_value_label "$MENU_CLUSTER_SR_CREDS" "$([ -n "$(get_menu_flag_value --cluster-schema-registry-creds)" ] && echo set)")")
      if [ ! -z "$CLUSTER_NAME" ] || [[ -n "$cluster_name" ]]; then group+=("$MENU_UNSET_CLUSTER_NAME"); fi
      # sub-options of the connector service account toggle
      if [ -n "$PG_CCLOUD_SERVICE_ACCOUNT" ]
      then
        group+=("$(menu_value_label "$MENU_CCLOUD_SERVICE_ACCOUNT_ACLS" "${PG_CCLOUD_SERVICE_ACCOUNT_ACLS:-docs}")")
        group+=("$(menu_value_label "$MENU_CCLOUD_SERVICE_ACCOUNT_ID" "${PG_CCLOUD_SERVICE_ACCOUNT_ID:-new one per connector}")")
      fi
    fi
    add_menu_group "$MENU_SEPARATOR_CLOUD" "${group[@]}"

    toggle_group=()
    is_connect_community_image=""
    if [[ $CP_CONNECT_IMAGE == *"cp-kafka-connect"* ]]; then is_connect_community_image=1; fi
    is_kafka_community_image=""
    if [[ $CP_KAFKA_IMAGE == *"cp-kafka" ]]; then is_kafka_community_image=1; fi
    add_menu_toggle $((1-is_fully_managed)) "$is_connect_community_image" "$MENU_CONNECT_COMMUNITY_IMAGE"
    add_menu_toggle $((1-is_ccloud)) "$is_kafka_community_image" "$MENU_KAFKA_COMMUNITY_IMAGE"
    add_menu_toggle $((1-is_ccloud)) "$ENABLE_KRAFT" "$MENU_KRAFT"
    add_menu_toggle $((1-is_fully_managed)) "$ENABLE_LEGACY_CONTROL_CENTER" "$MENU_LEGACY_C3"
    add_menu_group "$MENU_SEPARATOR_IMAGES" "${toggle_group[@]}"

    group=()
    if [ $is_fully_managed == 0 ]; then group+=("$(menu_value_label "$MENU_CONNECT_LOG_LEVEL" "$(get_menu_flag_value --connect-log-level)")"); fi
    if [ -n "$sibling_examples" ]; then group+=("$MENU_SWITCH_EXAMPLE"); fi
    # not when already creating one
    if [[ ! -n "$force_interactive_repro" ]]; then group+=("$MENU_REPRO_BOOTSTRAP"); fi
    group+=("$MENU_CONFIG")
    add_menu_group "$MENU_SEPARATOR_ACTIONS" "${group[@]}"

    options+=("$MENU_GO_BACK")
    preview="${ccloud_preview}\n${combination_preview}${missing_env}\n${arm64_support}\n🚀 number of examples ran so far: $(get_cli_metric nb_runs)\n\n⛳ flag list:\n$flag_string\n"
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

          if [ -n "$mandatory_environment_variable_value" ]
          then
            set +e
            save_answer=$(printf "yes\nno" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="💾" --header="Save $mandatory_environment_variable for next time? (playground secrets)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
            set -e
            if [ "$save_answer" == "yes" ]
            then
              secret_store_value "$mandatory_environment_variable" "$mandatory_environment_variable_value"
            fi
          fi
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
      trap - EXIT
      playground state set run.test_file "$previous_test_file"
      playground run
      exit $?
    fi

    if [[ $res == *"$MENU_SWITCH_EXAMPLE"* ]]
    then
      set +e
      sibling_example=$(echo "$sibling_examples" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔀" --header="select another example in $(basename "$test_file_directory")" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
      set -e
      if [ -n "$sibling_example" ]
      then
        # same flags, reopening the menu for the selected example
        trap - EXIT
        playground state set run.test_file "$previous_test_file"
        IFS=' ' flag_list="${array_flag_list[*]}"
        playground run -f "$test_file_directory/$sibling_example" --force-interactive-re-run $flag_list
        exit $?
      fi
    fi

    if [[ $res == *"$MENU_REPRO_BOOTSTRAP"* ]]
    then
      trap - EXIT
      playground state set run.test_file "$previous_test_file"
      playground repro bootstrap -f "$test_file"
      exit $?
    fi

    if [[ $res == *"$MENU_CONFIG"* ]]
    then
      interactive_config_menu
    fi

    if [[ $res == *"$MENU_CONNECT_LOG_LEVEL"* ]]
    then
      set +e
      log_level_package=$( (echo "❌ reset connect log level(s)"; get_example_connector_packages "$test_file"; echo "org.apache.kafka.connect.runtime"; echo "org.apache.kafka.clients") | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="📦" --header="select a package, or type one and use <option+enter>" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --bind "alt-enter:print-query")
      set -e
      if [[ "$log_level_package" == "❌"* ]]
      then
        maybe_remove_flag "--connect-log-level"
        unset PLAYGROUND_CONNECT_LOG_LEVELS
      elif [ -n "$log_level_package" ] && [[ ! "$log_level_package" =~ ^[A-Za-z0-9_.$-]+$ ]]
      then
        logwarn "❌ <$log_level_package> is not a valid package name, ignoring it"
      elif [ -n "$log_level_package" ]
      then
        set +e
        log_level=$(printf '%s\n' TRACE DEBUG INFO WARN | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔊" --header="select the log level for $log_level_package" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
        set -e
        if [ -n "$log_level" ]
        then
          # replace the level of the package if it was already set
          connect_log_level=""
          for entry in ${PLAYGROUND_CONNECT_LOG_LEVELS//,/ }
          do
            if [ "${entry%%=*}" != "$log_level_package" ]
            then
              connect_log_level="${connect_log_level:+$connect_log_level,}$entry"
            fi
          done
          connect_log_level="${connect_log_level:+$connect_log_level,}$log_level_package=$log_level"
          maybe_remove_flag "--connect-log-level"
          array_flag_list+=("--connect-log-level=$connect_log_level")
          export PLAYGROUND_CONNECT_LOG_LEVELS="$connect_log_level"
        fi
      fi
    fi

    if [[ $res == *"$MENU_KSQLDB"* ]]
    then
      if [ -z "$ENABLE_KSQLDB" ]
      then
        array_flag_list+=("--enable-ksqldb")
        export ENABLE_KSQLDB=true
        interactive_enable_ksqldb="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-ksqldb"}")
        unset ENABLE_KSQLDB
        interactive_enable_ksqldb=""
      fi
    fi

    if [[ $res == *"$MENU_C3"* ]]
    then
      if [ -z "$ENABLE_CONTROL_CENTER" ]
      then
        array_flag_list+=("--enable-control-center")
        export ENABLE_CONTROL_CENTER=true
        interactive_enable_c3="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-control-center"}")
        unset ENABLE_CONTROL_CENTER
        interactive_enable_c3=""
      fi
    fi

    if [[ $res == *"$MENU_FLINK"* ]]
    then
      if [ -z "$ENABLE_FLINK" ]
      then
        array_flag_list+=("--enable-flink")
        export ENABLE_FLINK=true
        interactive_enable_flink="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-flink"}")
        unset ENABLE_FLINK
        interactive_enable_flink=""
      fi
    fi

    if [[ $res == *"$MENU_RP"* ]]
    then
      if [ -z "$ENABLE_RESTPROXY" ]
      then
        array_flag_list+=("--enable-rest-proxy")
        export ENABLE_RESTPROXY=true
        interactive_enable_rp="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-rest-proxy"}")
        unset ENABLE_RESTPROXY
        interactive_enable_rp=""
      fi
    fi

    if [[ $res == *"$MENU_CONDUKTOR"* ]]
    then
      if [ -z "$ENABLE_CONDUKTOR" ]
      then
        array_flag_list+=("--enable-conduktor")
        export ENABLE_CONDUKTOR=true
        interactive_enable_conduktor="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-conduktor"}")
        unset ENABLE_CONDUKTOR
        interactive_enable_conduktor=""
      fi
    fi

    if [[ $res == *"$MENU_GRAFANA"* ]]
    then
      if [ -z "$ENABLE_JMX_GRAFANA" ]
      then
        array_flag_list+=("--enable-jmx-grafana")
        export ENABLE_JMX_GRAFANA=true
        interactive_enable_grafana="true"

      else
        array_flag_list=("${array_flag_list[@]/"--enable-jmx-grafana"}")
        unset ENABLE_JMX_GRAFANA
        interactive_enable_grafana=""
      fi
    fi

    if [[ $res == *"$MENU_BROKERS"* ]]
    then
      if [ -z "$ENABLE_KAFKA_NODES" ]
      then
        array_flag_list+=("--enable-multiple-brokers")
        export ENABLE_KAFKA_NODES=true
        interactive_enable_broker="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-multiple-brokers"}")
        unset ENABLE_KAFKA_NODES
        interactive_enable_broker=""
      fi
    fi

    if [[ $res == *"$MENU_CONNECT_WORKERS"* ]]
    then
      if [ -z "$ENABLE_CONNECT_NODES" ]
      then
        array_flag_list+=("--enable-multiple-connect-workers")
        export ENABLE_CONNECT_NODES=true
        interactive_enable_connect="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-multiple-connect-workers"}")
        unset ENABLE_CONNECT_NODES
        interactive_enable_connect=""
      fi
    fi

    if [[ $res == *"$MENU_KCAT"* ]]
    then
      if [ -z "$ENABLE_KCAT" ]
      then
        array_flag_list+=("--enable-kcat")
        export ENABLE_KCAT=true
        interactive_enable_kcat="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-kcat"}")
        unset ENABLE_KCAT
        interactive_enable_kcat=""
      fi
    fi

    if [[ $res == *"$MENU_SQL_DATAGEN"* ]]
    then
      if [ -z "$ENABLE_SQL_DATAGEN" ]
      then
        array_flag_list+=("--enable-sql-datagen")
        export ENABLE_SQL_DATAGEN=true
        interactive_enable_sql="true"

        array_flag_list+=("--enable-jmx-grafana")
        export ENABLE_JMX_GRAFANA=true
        interactive_enable_grafana="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-sql-datagen"}")
        unset ENABLE_SQL_DATAGEN
        interactive_enable_sql=""

        if [[ $test_file != *"fully-managed"* ]]
        then
          array_flag_list=("${array_flag_list[@]/"--enable-jmx-grafana"}")
          unset ENABLE_JMX_GRAFANA
          interactive_enable_grafana=""
        fi
      fi
    fi

    if [[ $res == *"$MENU_BENCHMARK"* ]]
    then
      if [ -z "$ENABLE_BENCHMARK" ]
      then
        array_flag_list+=("--benchmark")
        export ENABLE_BENCHMARK=true
        interactive_enable_benchmark="true"
      else
        array_flag_list=("${array_flag_list[@]/"--benchmark"}")
        unset ENABLE_BENCHMARK
        interactive_enable_benchmark=""
      fi
    fi

    if [[ $res == *"$MENU_CCLOUD_SERVICE_ACCOUNT"* ]]
    then
      if [ -z "$PG_CCLOUD_SERVICE_ACCOUNT" ]
      then
        array_flag_list+=("--ccloud-service-account")
        export PG_CCLOUD_SERVICE_ACCOUNT=true
        interactive_enable_ccloud_service_account="true"
      else
        maybe_remove_flag "--ccloud-service-account"
        maybe_remove_flag "--ccloud-service-account-acls"
        maybe_remove_flag "--ccloud-service-account-id"
        unset PG_CCLOUD_SERVICE_ACCOUNT PG_CCLOUD_SERVICE_ACCOUNT_ACLS PG_CCLOUD_SERVICE_ACCOUNT_ID
        interactive_enable_ccloud_service_account=""
      fi
    fi

    if [[ $res == *"$MENU_CCLOUD_SERVICE_ACCOUNT_ACLS"* ]]
    then
      set +e
      ccloud_service_account_acls=$(printf '%s\n' \
        "docs  the ACLs of the documentation, derived from the connector config" \
        "full  every operation on every topic, group and transactional id" \
        "none  no ACL, add them with playground rbac acl create --connector <connector>" \
        | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🚦" --header="select the ACLs of the service accounts" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer | awk '{print $1}')
      set -e
      if [[ -n "$ccloud_service_account_acls" ]]
      then
        maybe_remove_flag "--ccloud-service-account-acls"
        unset PG_CCLOUD_SERVICE_ACCOUNT_ACLS
        # docs is the default
        if [ "$ccloud_service_account_acls" != "docs" ]
        then
          array_flag_list+=("--ccloud-service-account-acls $ccloud_service_account_acls")
          export PG_CCLOUD_SERVICE_ACCOUNT_ACLS=$ccloud_service_account_acls
        fi
      fi
    fi

    if [[ $res == *"$MENU_CCLOUD_SERVICE_ACCOUNT_ID"* ]]
    then
      set +e
      # service accounts of the organization, or type an id
      ccloud_service_account_id=$( { echo "new  create a new service account per connector, with its ACLs"; confluent iam service-account list -o json 2>/dev/null | jq -r '.[] | "\(.id)  \(.name)"'; } \
        | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🪪" --header="select or type the id of the service account used as is by the connectors (no ACL created)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --print-query | tail -n 1 | awk '{print $1}')
      set -e
      if [[ -n "$ccloud_service_account_id" ]]
      then
        maybe_remove_flag "--ccloud-service-account-id"
        unset PG_CCLOUD_SERVICE_ACCOUNT_ID
        if [ "$ccloud_service_account_id" != "new" ]
        then
          array_flag_list+=("--ccloud-service-account-id $ccloud_service_account_id")
          export PG_CCLOUD_SERVICE_ACCOUNT_ID=$ccloud_service_account_id
        fi
      fi
    fi

    if [[ $res == *"$MENU_CONNECT_COMMUNITY_IMAGE"* ]]
    then
      if [ -z "$is_connect_community_image" ]
      then
        array_flag_list+=("--connect-community-image")
        export CP_CONNECT_IMAGE=confluentinc/cp-kafka-connect
        interactive_connect_community_image="true"
      else
        array_flag_list=("${array_flag_list[@]/"--connect-community-image"}")
        unset CP_CONNECT_IMAGE
        interactive_connect_community_image=""
      fi
    fi

    if [[ $res == *"$MENU_KAFKA_COMMUNITY_IMAGE"* ]]
    then
      if [ -z "$is_kafka_community_image" ]
      then
        array_flag_list+=("--kafka-community-image")
        export CP_KAFKA_IMAGE=confluentinc/cp-kafka
        interactive_kafka_community_image="true"
      else
        array_flag_list=("${array_flag_list[@]/"--kafka-community-image"}")
        unset CP_KAFKA_IMAGE
        interactive_kafka_community_image=""
      fi
    fi

    if [[ $res == *"$MENU_KRAFT"* ]]
    then
      if [ -z "$ENABLE_KRAFT" ]
      then
        array_flag_list+=("--enable-kraft")
        export ENABLE_KRAFT=true
        interactive_enable_kraft="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-kraft"}")
        unset ENABLE_KRAFT
        interactive_enable_kraft=""
      fi
    fi

    if [[ $res == *"$MENU_LEGACY_C3"* ]]
    then
      if [ -z "$ENABLE_LEGACY_CONTROL_CENTER" ]
      then
        array_flag_list+=("--enable-legacy-control-center")
        export ENABLE_LEGACY_CONTROL_CENTER=true
        interactive_enable_legacy_c3="true"
      else
        array_flag_list=("${array_flag_list[@]/"--enable-legacy-control-center"}")
        unset ENABLE_LEGACY_CONTROL_CENTER
        interactive_enable_legacy_c3=""
      fi
    fi

    if [[ $res == *"$MENU_ENVIRONMENT"* ]]
    then
      maybe_remove_flag "--environment"

      # only the environments this example supports
      options=($supported_environments)
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
        tag=${tag#*@}
      fi
      if [[ $tag == *" "* ]]
      then
        tag=${tag%% *}
      fi
      array_flag_list+=("--tag=$tag")
      export TAG=$tag
    fi

    if [[ $res == *"$MENU_CONNECT_TAG"* ]]
    then
      maybe_remove_flag "--connect-tag"

      connect_tag=$(playground get-tag-list --connect-only)
      if [[ $connect_tag == *"@"* ]]
      then
        connect_tag=${connect_tag#*@}
      fi
      if [[ $connect_tag == *" "* ]]
      then
        connect_tag=${connect_tag%% *}
      fi
      array_flag_list+=("--connect-tag=$connect_tag")
      export CP_CONNECT_TAG=$connect_tag
    fi

    if [[ $res == *"$MENU_SCHEMA_REGISTRY_TAG"* ]]
    then
      maybe_remove_flag "--schema-registry-tag"
      schema_registry_tag=$(playground get-tag-list)
      schema_registry_tag=${schema_registry_tag#*@}
      schema_registry_tag=${schema_registry_tag%% *}
      if [ -n "$schema_registry_tag" ]
      then
        array_flag_list+=("--schema-registry-tag=$schema_registry_tag")
        export CP_SCHEMA_REGISTRY_TAG=$schema_registry_tag
      else
        unset CP_SCHEMA_REGISTRY_TAG
      fi
    fi

    if [[ $res == *"$MENU_KSQLDB_TAG"* ]]
    then
      maybe_remove_flag "--ksqldb-tag"
      ksqldb_tag=$(playground get-tag-list)
      ksqldb_tag=${ksqldb_tag#*@}
      ksqldb_tag=${ksqldb_tag%% *}
      if [ -n "$ksqldb_tag" ]
      then
        array_flag_list+=("--ksqldb-tag=$ksqldb_tag")
        export CP_KSQL_TAG=$ksqldb_tag
        export CP_KSQL_CLI_TAG=$ksqldb_tag
      else
        unset CP_KSQL_TAG CP_KSQL_CLI_TAG
      fi
    fi

    if [[ $res == *"$MENU_CONTROL_CENTER_TAG"* ]]
    then
      maybe_remove_flag "--control-center-tag"
      if [ -n "$ENABLE_LEGACY_CONTROL_CENTER" ]
      then
        # legacy Control Center: CP versions
        control_center_tag=$(playground get-tag-list)
        control_center_tag=${control_center_tag#*@}
        control_center_tag=${control_center_tag%% *}
      else
        # Control Center Next Gen has its own versions
        set +e
        control_center_tag=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="💠" --header="Enter the Control Center Next Gen version (for example 2.2.0), empty for latest" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_empty_pointer --print-query)
        set -e
      fi
      if [ -n "$control_center_tag" ]
      then
        array_flag_list+=("--control-center-tag=$control_center_tag")
        export CP_CONTROL_CENTER_TAG=$control_center_tag
      else
        unset CP_CONTROL_CENTER_TAG
      fi
    fi

    if [[ $res == *"$MENU_CONNECTOR_TAG"* ]]
    then
      maybe_remove_flag "--connector-zip"
      maybe_remove_flag "--connector-tag"
      # utils.sh refuses CONNECTOR_TAG and CONNECTOR_ZIP together
      unset CONNECTOR_ZIP CONNECTOR_TAG
      connector_tags=""
      if [ -z "${connector_paths:-}" ]; then get_connector_paths; fi
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
      unset CONNECTOR_ZIP CONNECTOR_TAG CONNECTOR_JAR
      cd $test_file_directory
      connector_zip=$(playground get-zip-or-jar-with-fzf --type zip)
      if [[ $connector_zip == *"@"* ]]
      then
        connector_zip=${connector_zip#*@}
      fi
      array_flag_list+=("--connector-zip=$connector_zip")
      export CONNECTOR_ZIP=$connector_zip
    fi

    if [[ $res == *"$MENU_CONNECTOR_JAR"* ]]
    then
      maybe_remove_flag "--connector-zip"
      maybe_remove_flag "--connector-jar"
      unset CONNECTOR_ZIP CONNECTOR_JAR
      cd $test_file_directory
      connector_jar=$(playground get-zip-or-jar-with-fzf --type jar)
      if [[ $connector_jar == *"@"* ]]
      then
        connector_jar=${connector_jar#*@}
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
      export CLUSTER_TYPE=$cluster_type
    fi

    if [[ $res == *"$MENU_CLUSTER_CLOUD"* ]]
    then
      maybe_remove_flag "--cluster-cloud"
      options=(aws gcp azure)
      cluster_cloud=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔋" --header="select a cluster type" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
      array_flag_list+=("--cluster-cloud $cluster_cloud")
      export CLUSTER_CLOUD=$cluster_cloud
    fi

    if [[ $res == *"$MENU_CLUSTER_REGION"* ]]
    then
      maybe_remove_flag "--cluster-region"
      cluster_region=$(playground get-kafka-region-list $cluster_cloud)
      
      if [[ $cluster_region == *"@"* ]]
      then
        cluster_region=${cluster_region#*@}
      fi
      cluster_region=${cluster_region//[$' \t']/}
      cluster_region=${cluster_region#*/}
      array_flag_list+=("--cluster-region $cluster_region")
      export CLUSTER_REGION=$cluster_region
    fi

    if [[ $res == *"$MENU_CLUSTER_ENVIRONMENT"* ]]
    then
      maybe_remove_flag "--cluster-environment"
      cluster_environment=$(playground get-ccloud-environment-list)
      
      if [[ $cluster_environment == *"@"* ]]
      then
        cluster_environment=${cluster_environment#*@}
      fi
      if [[ $cluster_environment == *"/"* ]]
      then
        cluster_environment=${cluster_environment//[$' \t']/}
        cluster_environment=${cluster_environment%%/*}
      fi
      array_flag_list+=("--cluster-environment $cluster_environment")
      export ENVIRONMENT=$cluster_environment
    fi

    if [[ $res == *"$MENU_CLUSTER_NAME"* ]]
    then
      maybe_remove_flag "--cluster-name"
      cluster_name=$(playground get-ccloud-cluster-list)
      
      if [[ $cluster_name == *"@"* ]]
      then
        cluster_name=${cluster_name#*@}
      fi
      if [[ $cluster_name == *"/"* ]]
      then
        cluster_name=${cluster_name//[$' \t']/}
        cluster_name=${cluster_name#*/}
      fi
      array_flag_list+=("--cluster-name $cluster_name")
      export CLUSTER_NAME=$cluster_name
    fi

    if [[ $res == *"$MENU_CLUSTER_CREDS"* ]]
    then
      maybe_remove_flag "--cluster-creds"
      set +e
      cluster_creds=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔐" --header="Enter the Kafka api key and secret to use, it should be separated with colon (example: <API_KEY>:<API_KEY_SECRET>)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_empty_pointer --print-query)
      set -e
      array_flag_list+=("--cluster-creds $cluster_creds")
      export CLUSTER_CREDS=$cluster_creds
    fi

    if [[ $res == *"$MENU_CLUSTER_SR_CREDS"* ]]
    then
      maybe_remove_flag "--cluster-schema-registry-creds"
      set +e
      cluster_schema_registry_creds=$(echo "" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔐" --header="Enter the Schema Registry api key and secret to use, it should be separated with colon (example: <SR_API_KEY>:<SR_API_KEY_SECRET>)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_empty_pointer --print-query)
      set -e
      array_flag_list+=("--cluster-schema-registry-creds $cluster_schema_registry_creds")
      export SCHEMA_REGISTRY_CREDS=$cluster_schema_registry_creds
    fi

    if [[ $res == *"$MENU_UNSET_CLUSTER_NAME"* ]]
    then
      maybe_remove_flag "--cluster-name"
      maybe_remove_flag "--cluster-cloud"
      maybe_remove_flag "--cluster-region"
      maybe_remove_flag "--cluster-type"
      maybe_remove_flag "--cluster-creds"
      maybe_remove_flag "--cluster-schema-registry-creds"
      unset CLUSTER_NAME
      unset CLUSTER_CLOUD
      unset CLUSTER_REGION
      unset CLUSTER_TYPE
      unset CLUSTER_CREDS
      unset SCHEMA_REGISTRY_CREDS
      cluster_name=""
      cluster_cloud=""
      cluster_region=""
      cluster_type=""
      cluster_creds=""
      cluster_schema_registry_creds=""
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

  if [ "$interactive_connect_community_image" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --connect-community-image CP_CONNECT_IMAGE confluentinc/cp-kafka-connect
    fi
  fi

  if [ "$interactive_kafka_community_image" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --kafka-community-image CP_KAFKA_IMAGE confluentinc/cp-kafka
    fi
  fi

  if [ "$interactive_enable_kraft" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-kraft ENABLE_KRAFT
    fi
  fi

  if [ "$interactive_enable_legacy_c3" == "true" ]
  then
    if [[ -n "$force_interactive_repro" ]]
    then
      force_enable --enable-legacy-control-center ENABLE_LEGACY_CONTROL_CENTER
    fi
  fi

  if [ "$interactive_enable_benchmark" == "true" ] && [[ -n "$force_interactive_repro" ]]
  then
    force_enable --benchmark ENABLE_BENCHMARK
  fi

  if [ "$interactive_enable_ccloud_service_account" == "true" ] && [[ -n "$force_interactive_repro" ]]
  then
    force_enable --ccloud-service-account PG_CCLOUD_SERVICE_ACCOUNT
    if [ -n "$PG_CCLOUD_SERVICE_ACCOUNT_ACLS" ]
    then
      force_enable --ccloud-service-account-acls PG_CCLOUD_SERVICE_ACCOUNT_ACLS "$PG_CCLOUD_SERVICE_ACCOUNT_ACLS"
    fi
    if [ -n "$PG_CCLOUD_SERVICE_ACCOUNT_ID" ]
    then
      force_enable --ccloud-service-account-id PG_CCLOUD_SERVICE_ACCOUNT_ID "$PG_CCLOUD_SERVICE_ACCOUNT_ID"
    fi
  fi

  if [ "$interactive_enable_sql" == "true" ]
  then
    if [[ $test_file != *"fully-managed"* ]]
    then
      log "📊 automatically enabling Grafana as --enable-sql-datagen is set"
      if [[ -n "$force_interactive_repro" ]]
      then
        force_enable --enable-sql-datagen ENABLE_SQL_DATAGEN
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

if [[ " ${array_flag_list[*]} " == *" --enable-legacy-control-center "* ]] && [ -z "$ENABLE_CONTROL_CENTER" ]
then
  log "💠 enabling Control Center as --enable-legacy-control-center is set"
  array_flag_list+=("--enable-control-center")
  export ENABLE_CONTROL_CENTER=true
fi

# known-bad combinations: fail now rather than after the running environment is killed
combination_error=0
while IFS='|' read -r combination_level combination_message
do
  if [ "$combination_level" == "error" ]
  then
    logerror "❌ $combination_message"
    combination_error=1
  elif [ "$combination_level" == "warning" ]
  then
    logwarn "⚠️ $combination_message"
  fi
done < <(get_run_flag_combination_problems)
if [ $combination_error == 1 ]
then
  exit 1
fi

#
# 💀 Only now that the example is really started (the interactive menu was not
# cancelled), stop or kill what the previous run left behind
#
set +e
trap - EXIT
# 'playground stop' stops the example recorded in run.test_file
playground state set run.test_file "$previous_test_file"
# resources left by the previous ccloud run (e.g. interrupted before its final connector delete)
maybe_cleanup_ccloud_run_resources
# already done, don't do it again in the 'playground stop' below
export PG_SKIP_CCLOUD_RUN_CLEANUP=1
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
unset PG_SKIP_CCLOUD_RUN_CLEANUP
set -e

IFS=' ' flag_list="${array_flag_list[*]}"
array_declaration=$(declare -p array_flag_list)
encoded_array=$(echo "$array_declaration" | base64)
playground state set run.array_flag_list_base64 "$encoded_array"

# 📄 from now on, the output also goes to a masked run log that can be shared (playground config run-log)
run_log_start
trap 'run_log_finish $?' EXIT

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
if [[ $test_file == *"ccloud"* ]]
then
  # Confluent Cloud resources created by this run are recorded with this id, see maybe_cleanup_ccloud_run_resources
  export PG_CCLOUD_RUN_ID="$(date +%s)"
  playground state set run.ccloud_run_id "$PG_CCLOUD_RUN_ID"
fi
# shell-quoted, so that 'playground history' and eval replay it as is; credentials are not written
history_line="playground run -f $(printf '%q' "$test_file")"
for flag in "${array_flag_list[@]}"
do
  case "$flag" in
    "") ;;
    "--cluster-creds "*|"--cluster-schema-registry-creds "*) history_line+=" ${flag%% *} '<masked>'" ;;
    --*=*) history_line+=" ${flag%%=*}=$(printf '%q' "${flag#*=}")" ;;
    "--"*" "*) history_line+=" ${flag%% *} $(printf '%q' "${flag#* }")" ;;
    *) history_line+=" $(printf '%q' "$flag")" ;;
  esac
done
echo "$history_line" >> "$root_folder/playground-run-history"

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
set +e
ci_result=$(playground get-ci-result 2>&1)
set -e
if [ -n "$ci_result" ]
then
    echo "$ci_result"
fi
# red in CI too: say it now, and compare with the CI failure if the local run fails (not in CI itself)
ci_red=0
if [[ "$ci_result" == *"🔴"* ]] && [ -z "$GITHUB_RUN_NUMBER" ]
then
    ci_red=1
    log "🔴 this example also fails in CI, see why with: playground get-ci-result --logs"
fi
log "####################################################"
log "🚀 Executing $filename in dir $test_file_directory"
log "####################################################"
SECONDS=0
cd $test_file_directory
function cleanup {
  # 💡 Capture the original exit status immediately!
  local original_exit_status=$?
  set +e
  rm /tmp/playground-run-command-used
  echo ""

  if [ -n "$GITHUB_RUN_NUMBER" ]
  then
    # 🧹 fully managed connectors created by this run: deleted now, also when the example failed or was killed by
    # the timeout of run-tests.sh, rather than billed until the cleanup at the end of the nightly
    maybe_cleanup_ccloud_run_resources
  fi

  if [ -z "$GITHUB_RUN_NUMBER" ]
  then
    if [ "$original_exit_status" -ne 0 ]
    then
        run_log_finish "$original_exit_status"
        # 💡 Exit the function (and the script) with the captured status
        exit "$original_exit_status"
    fi
  fi
  sleep 3
  
  connector_type=$(playground state get run.connector_type)

  if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
  then
      # playground connector-plugin display-last-updated
    if [ "$connector_plugin_display_last_updated" == "true" ] && ! pgrep -f "playground connector-plugin display-last-updated" > /dev/null
    then
      if [ -f ${connector_plugin_display_last_updated_file} ]
      then
        cat ${connector_plugin_display_last_updated_file}
      fi
    fi

    playground connector versions
  fi

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

  if [ -z "$GITHUB_RUN_NUMBER" ]
  then
    display_newer_cp_patch_hint
  fi

  playground open-docs --only-show-url

    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
        if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] 
        then
            playground connector sourcecode --only-show-url
        fi
    fi

  if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
  then
    playground connector open-docs --only-show-url
  fi
  run_log_finish "$original_exit_status"
  # 💡 Exit the function (and the script) with the captured status
  exit "$original_exit_status"
}
trap cleanup EXIT
# killed by the timeout of run-tests.sh (or kill): without it, bash 5 dies on SIGTERM without running the EXIT trap
trap 'exit 143' TERM

# background jobs must not inherit stdout/stderr: 'playground run | tee' (run-tests.sh) would wait for them to exit
playground generate-fzf-find-files > /dev/null 2>&1 &
generate_connector_versions > /dev/null 2>&1 &

if [[ $test_file == *"aws"* ]]
then
    playground cloud-resources aws costs-history --no-open > /tmp/aws-costs-history.txt 2>/dev/null &
elif [[ $test_file == *"azure"* ]]
then
    playground cloud-resources azure costs-history --no-open > /tmp/azure-costs-history.txt 2>/dev/null &
fi
set +e

if [ ! -z "$ENABLE_CONTROL_CENTER" ]
then
      if [ -z "$ENABLE_LEGACY_CONTROL_CENTER" ]
      then
        #log "💠⭐ checking if newer control-center next-gen image is available.."
        docker pull confluentinc/cp-enterprise-control-center-next-gen:latest > /dev/null 2>&1
      fi
fi
connector_plugin_display_last_updated=$(playground config get display-last-updated-connector-plugins)
connector_plugin_display_last_updated_days=$(playground config get display-last-updated-connector-plugins-days)
connector_plugin_display_last_updated_days="${connector_plugin_display_last_updated_days:-3}"
connector_plugin_display_last_updated_vendor=$(playground config get display-last-updated-connector-plugins-vendor)
connector_plugin_display_last_updated_vendor="${connector_plugin_display_last_updated_vendor:-confluentinc}"
connector_plugin_display_last_updated_file="/tmp/connector-plugin-display-last-updated-$(date +%Y-%m-%d)-${connector_plugin_display_last_updated_days}-${connector_plugin_display_last_updated_vendor}.txt"
connector_type=$(playground state get run.connector_type)
if [ "$connector_plugin_display_last_updated" == "true" ] && { [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]; }
then
  if [ ! -f ${connector_plugin_display_last_updated_file} ]
  then
    # 'all': every vendor
    connector_plugin_display_last_updated_vendor_flag=()
    if [ "$connector_plugin_display_last_updated_vendor" != "all" ]
    then
      connector_plugin_display_last_updated_vendor_flag=(--vendor "$connector_plugin_display_last_updated_vendor")
    fi
    playground connector-plugin display-last-updated --days "$connector_plugin_display_last_updated_days" "${connector_plugin_display_last_updated_vendor_flag[@]}" > ${connector_plugin_display_last_updated_file} 2>/dev/null &
  fi
fi
set -e
touch /tmp/playground-run-command-used
# a reproduction model created with --enable-sql-datagen forces it with an export line in the script
sql_datagen="$ENABLE_SQL_DATAGEN"
if grep -q '^export ENABLE_SQL_DATAGEN=true' "$filename"
then
  sql_datagen=true
fi
# same for --benchmark
run_benchmark="$ENABLE_BENCHMARK"
benchmark_ret=0
if grep -q '^export ENABLE_BENCHMARK=true' "$filename"
then
  run_benchmark=true
fi
if grep -q '^export SQL_DATAGEN=true' "$filename"
then
  logwarn "⚠️ $filename forces the former Java SQL datagen (export SQL_DATAGEN=true), which is gone: its build and its sql-datagen container fail"
  logwarn "   replace that line with: export ENABLE_SQL_DATAGEN=true (rows are then injected with the benchmark-load.bash of the example)"
fi
set +e
run_log_exec bash $filename
ret=$?
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
let ELAPSED_TOTAL+=$SECONDS
# keep those lists up to date
playground generate-tag-list > /dev/null 2>&1 &
playground generate-connector-plugin-list > /dev/null 2>&1 &
playground generate-kafka-region-list > /dev/null 2>&1 &
if [ "$USER" == "vsaboulin" ]
then
    if [ ! -z $GITHUB_TOKEN ] && [[ "$OSTYPE" == "darwin"* ]]
    then
        playground update-cache-versions > /dev/null 2>&1 &
    fi
fi
set -e
if [ $ret -eq 0 ]
then
  log "####################################################"
  log "✅ RESULT: SUCCESS for $filename ($ELAPSED - $CUMULATED)"
  log "####################################################"
  if [ -n "$sql_datagen" ]
  then
    # SQL_DATAGEN_DURATION (minutes, default 10) and SQL_DATAGEN_SESSIONS (default 5)
    sql_datagen_inject "$test_file" "${SQL_DATAGEN_DURATION:-10}" "${SQL_DATAGEN_SESSIONS:-5}" || ret=$?
  fi
  if [ -n "$run_benchmark" ]
  then
    if [[ "$(playground state get run.environment)" == cfk* ]]
    then
      logwarn "⏭️ --benchmark is ignored: playground connector benchmark is not available with the cfk environment yet"
    else
      # BENCHMARK_ARGS: extra flags for playground connector benchmark, e.g. "--mode steady --duration 5m"
      read -r -a benchmark_args <<< "${BENCHMARK_ARGS:-}"
      log "🏎️ --benchmark is set: running playground connector benchmark ${benchmark_args[*]}"
      playground connector benchmark "${benchmark_args[@]}" || benchmark_ret=$?
      if [ $benchmark_ret -ne 0 ]
      then
        logerror "❌ playground connector benchmark failed, run it again with:"
        echo "playground connector benchmark ${benchmark_args[*]}"
      fi
    fi
  fi
elif [ $ret -eq 111 ]
then
  log "####################################################"
  log "⏭ RESULT: SKIPPED for $filename ($ELAPSED - $CUMULATED)"
  log "####################################################"
  
  exit $ret
else
  logerror "####################################################"
  logerror "🔥 RESULT: FAILURE for $filename ($ELAPSED - $CUMULATED)"
  logerror "####################################################"

  if [[ $test_file != *"fully-managed"* ]]
  then
    log "🧑‍🚒 you can troubleshoot the issue by running:"
    echo "playground container display-error-all"
    log "🧑‍🚒 open full logs with '<playground container logs --open --container <container>', example:"
    echo "playground container logs --open --container connect"
  fi

  # same example red in CI: show the CI failure to tell a local problem from a broken example
  if [ $ci_red -eq 1 ] && [[ ! $(type -f gh 2>&1) =~ "not found" ]]
  then
    maybe_podman=""
    if [ "$(get_container_engine)" == "podman" ]
    then
      maybe_podman="--podman"
    fi
    echo ""
    log "🤖 this example also fails in CI, compare with its latest CI failure:"
    set +e
    playground get-ci-result --logs --max-findings 10 $maybe_podman
    set -e
  fi
  exit $ret
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
    log "📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password)"
  fi

  if [[ $test_file != *"fully-managed"* ]]
  then
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
    log "👀 all the details are in the HTML report above, or run <playground ccloud-costs-history --detailed>"
    display_ccloud_leftovers
  elif [[ $test_file == *"aws"* ]]
  then
    echo ""
    # wait that process with "playground cloud-resources aws costs-history" is finished
    set +e
    while pgrep -f "playground cloud-resources aws costs-history" > /dev/null
    do
      log "⌛ wait for monthly aws costs..."
      sleep 5
    done
    set -e
    if [ -f /tmp/aws-costs-history.txt ]
    then
      log "📅💰 monthly aws costs"
      cat /tmp/aws-costs-history.txt
    fi
    log "👀 all the details are in the HTML report above, or run <playground cloud-resources aws costs-history --detailed>"
  elif [[ $test_file == *"azure"* ]]
  then
    echo ""
    # wait that process with "playground cloud-resources azure costs-history" is finished
    set +e
    while pgrep -f "playground cloud-resources azure costs-history" > /dev/null
    do
      log "⌛ wait for monthly azure costs..."
      sleep 5
    done
    set -e
    if [ -f /tmp/azure-costs-history.txt ]
    then
      log "📅💰 monthly azure costs"
      cat /tmp/azure-costs-history.txt
    fi
    log "👀 all the details are in the HTML report above, or run <playground cloud-resources azure costs-history --detailed>"
  fi
fi

# the example succeeded, but --benchmark did not
if [ $benchmark_ret -ne 0 ]
then
  exit $benchmark_ret
fi
