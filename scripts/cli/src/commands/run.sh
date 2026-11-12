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
client_version="${args[--client-version]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"

# 🧩 the boolean flags of playground run, one line each: read by apply_boolean_flags (flags, ENABLE_* from the shell,
# checks), by the menu (labels, visibility, toggles) and by force_enable_boolean_flags (reproduction models). Adding a
# boolean flag: its line here, plus the flag in bashly.yml.
#
# flag | variable | value | ENABLE_* from the shell is the flag (1/0) | refused on (ccloud, fully_managed, -) |
# hidden in the menu on (ccloud, fully_managed, -, or the name of a 0/1 variable) | menu group | emoji | text
boolean_flags_table='
--enable-ksqldb|ENABLE_KSQLDB|true|1|ccloud|fully_managed|options|🎏|ksqlDB
--enable-control-center|ENABLE_CONTROL_CENTER|true|1|-|fully_managed|options|💠|Control Center
--enable-conduktor|ENABLE_CONDUKTOR|true|1|-|fully_managed|options|🐺|Conduktor Platform
--enable-rest-proxy|ENABLE_RESTPROXY|true|1|ccloud|ccloud|options|🧲|Rest Proxy
--enable-jmx-grafana|ENABLE_JMX_GRAFANA|true|1|-|ccloud|options|📊|Grafana
--enable-multiple-brokers|ENABLE_KAFKA_NODES|true|1|ccloud|ccloud|options|🔢|Multiple brokers
--enable-multiple-connect-workers|ENABLE_CONNECT_NODES|true|1|ccloud|ccloud|options|🥉|Multiple connect workers
--enable-multiple-controllers|ENABLE_CONTROLLER_NODES|true|1|ccloud|ccloud|options|🗳️|Multiple controllers (KRaft or ZooKeeper)
--enable-kcat|ENABLE_KCAT|true|1|ccloud|ccloud|options|🐈|kcat
--enable-sql-datagen|ENABLE_SQL_DATAGEN|true|0|-|sql_datagen|options|🌀|SQL Datagen injection
--benchmark|ENABLE_BENCHMARK|true|0|-|benchmark_available|options|🏎️|Benchmark the connector
--enable-flink|ENABLE_FLINK|true|1|ccloud|ccloud|options|🐹|Flink
--connect-community-image|CP_CONNECT_IMAGE|confluentinc/cp-kafka-connect|0|fully_managed|fully_managed|images|🌱|Community connect image
--kafka-community-image|CP_KAFKA_IMAGE|confluentinc/cp-kafka|0|ccloud|ccloud|images|🌿|Community kafka image
--enable-kraft|ENABLE_KRAFT|true|0|ccloud|ccloud|images|📡|KRaft (CP 7.4 to 7.9)
--enable-legacy-control-center|ENABLE_LEGACY_CONTROL_CENTER|true|1|-|fully_managed|images|🧓|Legacy Control Center (CP < 8)
'
declare -a bf_flag=() bf_variable=() bf_value=() bf_adopt=() bf_refused=() bf_hidden=() bf_group=() bf_emoji=() bf_text=()
# how each flag got enabled: flag, shell, menu or hook (sql-datagen enabling Grafana); empty when disabled
declare -a bf_source=() bf_menu_label=()
nb_boolean_flags=0
while IFS='|' read -r bf_line_flag bf_line_variable bf_line_value bf_line_adopt bf_line_refused bf_line_hidden bf_line_group bf_line_emoji bf_line_text
do
  # bashly indents the body of the command, the lines of the table too
  bf_line_flag="${bf_line_flag//[[:space:]]/}"
  [ -z "$bf_line_flag" ] && continue
  bf_flag[nb_boolean_flags]="$bf_line_flag"
  bf_variable[nb_boolean_flags]="$bf_line_variable"
  bf_value[nb_boolean_flags]="$bf_line_value"
  bf_adopt[nb_boolean_flags]="$bf_line_adopt"
  bf_refused[nb_boolean_flags]="$bf_line_refused"
  bf_hidden[nb_boolean_flags]="$bf_line_hidden"
  bf_group[nb_boolean_flags]="$bf_line_group"
  bf_emoji[nb_boolean_flags]="$bf_line_emoji"
  bf_text[nb_boolean_flags]="$bf_line_text"
  bf_source[nb_boolean_flags]=""
  nb_boolean_flags=$((nb_boolean_flags + 1))
done <<< "$boolean_flags_table"

function boolean_flag_index () {
  local i
  for ((i = 0; i < nb_boolean_flags; i++))
  do
    if [ "${bf_flag[i]}" == "$1" ]
    then
      echo "$i"
      return
    fi
  done
}

# set by the flag, the shell, the menu or a reproduction model: ENABLE_*=<anything>, or the image of the line
function boolean_flag_enabled () {
  local variable="${bf_variable[$1]}"
  local value="${!variable:-}"
  if [ "${bf_value[$1]}" == "true" ]
  then
    [ -n "$value" ]
  else
    [[ "$value" == *"${bf_value[$1]#*/}"* ]]
  fi
}

# the reason the flag can't be used with this example (is_ccloud, is_fully_managed), nothing when it can
function boolean_flag_refusal () {
  case "${bf_refused[$1]}" in
    ccloud) [ $is_ccloud == 1 ] && echo "ccloud examples" ;;
    fully_managed) [ $is_fully_managed == 1 ] && echo "fully managed connector examples" ;;
  esac
  return 0
}

function enable_boolean_flag () {
  array_flag_list+=("${bf_flag[$1]}")
  export "${bf_variable[$1]}=${bf_value[$1]}"
  bf_source[$1]="$2"
}

function disable_boolean_flag () {
  maybe_remove_flag "${bf_flag[$1]}"
  unset "${bf_variable[$1]}"
  bf_source[$1]=""
}

# --enable-sql-datagen: Grafana shows the connector during the injection, only with a local connect. Removed with
# sql-datagen only when sql-datagen added it
function sync_sql_datagen_grafana () {
  local sql_index grafana_index
  sql_index=$(boolean_flag_index --enable-sql-datagen)
  grafana_index=$(boolean_flag_index --enable-jmx-grafana)
  # enabled by the flag or the menu (not by an ENABLE_SQL_DATAGEN exported in the shell, which is not the flag)
  if [ -n "${bf_source[sql_index]}" ]
  then
    if [ $is_fully_managed == 0 ] && ! boolean_flag_enabled $grafana_index
    then
      log "📊 automatically enabling Grafana as --enable-sql-datagen is set"
      enable_boolean_flag $grafana_index hook
    fi
  elif [ "${bf_source[grafana_index]}" == "hook" ]
  then
    disable_boolean_flag $grafana_index
  fi
}

# the flags given, and the ENABLE_* exported in the shell (documented as an alternative to the --enable-* flags): turned
# into their flag, so that the banner, the history, re-run, the clipboard command and the run log record them
function apply_boolean_flags () {
  local i source variable refusal
  for ((i = 0; i < nb_boolean_flags; i++))
  do
    source=""
    variable="${bf_variable[i]}"
    refusal=$(boolean_flag_refusal $i)
    if [[ -n "${args[${bf_flag[i]}]:-}" ]]
    then
      source="flag"
    elif [ "${bf_adopt[i]}" == "1" ] && [[ -n "${!variable:-}" ]] && [ -z "$refusal" ]
    then
      log "🌱 $variable is set in your shell: same as ${bf_flag[i]} (added to the flags of this run)"
      source="shell"
    fi
    if [ -z "$source" ]
    then
      continue
    fi
    if [ -n "$refusal" ]
    then
      logwarn "❌ ${bf_flag[i]} is not supported with $refusal"
      exit 1
    fi
    enable_boolean_flag $i "$source"
  done
  sync_sql_datagen_grafana
}

function create_boolean_flag_menu_labels () {
  local i
  for ((i = 0; i < nb_boolean_flags; i++))
  do
    bf_menu_label[i]="$(menu_label "${bf_emoji[i]}" "${bf_text[i]}" "${bf_flag[i]}" 4)"
  done
}

# the toggles of a menu group ($1), with the entries that apply to this example
function add_boolean_flag_toggles () {
  local i shown current
  for ((i = 0; i < nb_boolean_flags; i++))
  do
    [ "${bf_group[i]}" == "$1" ] || continue
    case "${bf_hidden[i]}" in
      ccloud) shown=$((1 - is_ccloud)) ;;
      fully_managed) shown=$((1 - is_fully_managed)) ;;
      -) shown=1 ;;
      *) shown="${!bf_hidden[i]:-0}" ;;
    esac
    current=""
    if boolean_flag_enabled $i
    then
      current=1
    fi
    add_menu_toggle "$shown" "$current" "${bf_menu_label[i]}"
  done
}

# the toggles picked in the menu ($1): flipped
function toggle_boolean_flags () {
  local i
  for ((i = 0; i < nb_boolean_flags; i++))
  do
    if [[ "$1" == *"${bf_menu_label[i]}"* ]]
    then
      if boolean_flag_enabled $i
      then
        disable_boolean_flag $i
      else
        enable_boolean_flag $i menu
      fi
      if [ "${bf_flag[i]}" == "--enable-sql-datagen" ]
      then
        sync_sql_datagen_grafana
      fi
    fi
  done
}

# a reproduction model keeps the flags given or picked for it (not the ENABLE_* of the shell): export lines in its script
function force_enable_boolean_flags () {
  local i
  if [[ -z "$force_interactive_repro" ]]
  then
    return
  fi
  for ((i = 0; i < nb_boolean_flags; i++))
  do
    case "${bf_source[i]}" in
      flag|menu|hook) force_enable "${bf_flag[i]}" "${bf_variable[i]}" "${bf_value[i]}" ;;
    esac
  done
}

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
if [ -n "$run_log_file_flag" ] && [[ "$run_log_file_flag" != /* ]]
then
  run_log_file_flag="$PWD/$run_log_file_flag"
fi
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

# its folder names (ccloud, fm-…) are tested on this path, not on the absolute one: a clone or a worktree in
# .../my-ccloud-tests/ must not turn every example into a ccloud example
test_file_rel=$(example_relative_path "$test_file")

# --environment has no default: PLAYGROUND_ENVIRONMENT exported in the shell is the fallback (as documented), recorded as
# --environment so that the banner, the history, re-run and the run log show it
if [[ -z "$environment" ]] && [[ -n "$PLAYGROUND_ENVIRONMENT" ]] && [ "$PLAYGROUND_ENVIRONMENT" != "plaintext" ] && [[ $test_file_rel != *"ccloud"* ]]
then
  case "$PLAYGROUND_ENVIRONMENT" in
    ccloud|cfk|cfk-rbac|sasl-ssl|sasl-plain|2way-ssl|sasl-scram|kerberos|ssl_kerberos|ldap-authorizer-sasl-plain|ldap-sasl-plain|rbac-sasl-plain|rbac-oauth|sasl-oauthbearer)
      if [ -z "${connector_paths:-}" ]; then get_connector_paths; fi
      if [ -n "$connector_paths" ]
      then
        log "🌱 PLAYGROUND_ENVIRONMENT=$PLAYGROUND_ENVIRONMENT is set in your shell: same as --environment $PLAYGROUND_ENVIRONMENT (added to the flags of this run)"
        environment="$PLAYGROUND_ENVIRONMENT"
      fi
    ;;
  esac
fi

# what the example runs against, for the checks of the flags below and for the menu:
# - is_ccloud: a Confluent Cloud cluster (ccloud example, or a connector example with --environment ccloud)
# - is_fully_managed / is_custom_connector: the connector runs in Confluent Cloud, no local connect (get_connector_type:
#   fm-* without local connect, including fm-custom-smt-* and the reproduction models of fully managed examples)
is_ccloud=0
if [[ $test_file_rel == *"ccloud"* ]] || [ "${environment:-$PLAYGROUND_ENVIRONMENT}" == "ccloud" ]
then
  is_ccloud=1
fi
example_connector_type=$(get_connector_type | tr -d '\n')
is_fully_managed=0
if [ "$example_connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
  is_fully_managed=1
fi
is_custom_connector=0
if [ "$example_connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
  is_custom_connector=1
fi
is_ccloud_managed=$((is_fully_managed | is_custom_connector))

#
# 🔐 Resolve, from the secrets store, the variables this example needs and that
# are not already exported. Scoped to the example's own list on purpose: no
# blanket 'set -o allexport' that would leak every credential into every
# process for the rest of the session.
#
load_secrets_for_example "$test_file" "${environment:-$PLAYGROUND_ENVIRONMENT}"
if [[ $test_file_rel == *"ccloud"* ]] || [ "${environment:-$PLAYGROUND_ENVIRONMENT}" == "ccloud" ]
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

if [ $is_ccloud == 1 ]
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
  if [ $is_ccloud == 1 ]
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
  if [ $is_ccloud == 1 ]
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

if [[ -n "$client_version" ]]
then
  # the <tab> completion prints <cur>@<version>
  client_version=${client_version#*@}
  array_flag_list+=("--client-version=$client_version")
  # read by the client examples, and by set_kafka_client_tag (utils_function.sh) for the java builds
  export CLIENT_VERSION=$client_version
fi

if [[ -n "$environment" ]]
then
  if [ -z "${connector_paths:-}" ]; then get_connector_paths; fi
  if [ "$connector_paths" == "" ] && [ "$environment" != "plaintext" ]
  then
    logerror "❌ using --environment is only supported with connector examples"
    exit 1
  fi

  # also plaintext: an explicit --environment plaintext wins over PLAYGROUND_ENVIRONMENT exported in the shell
  export PLAYGROUND_ENVIRONMENT=$environment
  if [ "$environment" != "plaintext" ]
  then
    array_flag_list+=("--environment=$environment")
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

apply_boolean_flags

if [[ -n "$connect_log_level" ]]
then
  if [ $is_fully_managed == 1 ]
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
    cluster_environment=${cluster_environment%%/*}
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
  if [ $is_ccloud_managed == 0 ]
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
  if [ $is_ccloud_managed == 1 ]
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
  if [ $is_ccloud_managed == 1 ]
  then
    MENU_OPEN_FILE="📖 Open the example file in text editor"
  else
    MENU_OPEN_FILE="📖 Open the example files (including docker-compose file) in text editor"
  fi
  set +e
  if ! can_open_url
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
  MENU_CLIENT_VERSION="$(menu_label "☕" "Client version (the client the example builds)" "--client-version")"
  MENU_CONNECTOR_TAG="$(menu_label "🔌" "Connector version" "--connector-tag")"
  MENU_CONNECTOR_ZIP="$(menu_label "🤐" "Connector zip" "--connector-zip")"
  MENU_CONNECTOR_JAR="$(menu_label "🤎" "Connector jar" "--connector-jar")"
  MENU_ENVIRONMENT="$(menu_label "🔐" "Environment" "--environment")"

  readonly MENU_SEPARATOR="--------------------------------------------------"

  create_boolean_flag_menu_labels
  MENU_CCLOUD_SERVICE_ACCOUNT="$(menu_label "👤" "Connector service account" "--ccloud-service-account" 4)"


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
  # the load of the example, or another one (BENCHMARK_LOAD_SCRIPT, e.g. benchmark-load-<ticket>.bash of a repro model)
  if [ -n "$(benchmark_load_script "$test_file" 2> /dev/null)" ] || grep -q "playground topic produce" "$test_file"
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

    if [[ $test_file_rel == *"ccloud"* ]] || [ "$PLAYGROUND_ENVIRONMENT" == "ccloud" ]
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

        ccloud_preview="✨ ${YELLOW}cluster-name is not set, a new ccloud cluster will be created...${NC}\n"
        ccloud_preview="${ccloud_preview}🏗️ ${CYAN}tip: 'playground ccloud setup' creates your own clusters once, one per cloud, reused by every example${NC}\n\n"

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
      if [ -z "${!mandatory_environment_variable:-}" ]
      then
        missing_env="${missing_env}❌ ${RED}${mandatory_environment_variable} is missing!${NC}\n"
        has_error=1

        missing_env_list+=("$mandatory_environment_variable")
      else
        if [[ $mandatory_environment_variable == *"PASSWORD"* ]] || [[ $mandatory_environment_variable == *"SECRET"* ]] || [[ $mandatory_environment_variable == *"TOKEN"* ]] || [[ $mandatory_environment_variable == *"KEY"* ]] || [[ $mandatory_environment_variable == *"USER_INFO"* ]] || [[ $mandatory_environment_variable == *"CREDS"* ]]
        then
          missing_env="${missing_env}🔑 ${GREEN}${mandatory_environment_variable} is set${NC}\n"
        else
          missing_env="${missing_env}🔑 ${GREEN}${mandatory_environment_variable}=${!mandatory_environment_variable}${NC}\n"
        fi
      fi
    done

    if [[ $test_file_rel == *"aws"* ]]
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

    if [[ $test_file_rel == *"gcp"* ]]
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
    if [[ $test_file_rel == *"ccloud"* ]] || [ "$PLAYGROUND_ENVIRONMENT" == "ccloud" ]
    then
      is_ccloud=1
    fi
    # no local connect (versions, profiles...): is_fully_managed, computed once with get_connector_type

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
    # only for the examples that build a client: java with the Apache Kafka clients (mvn -Dkafka.client.tag), or the
    # client examples (CLIENT_VERSION)
    if example_uses_client_version "$test_file"; then group+=("$(menu_value_label "$MENU_CLIENT_VERSION" "$(get_menu_flag_value --client-version)")"); fi
    add_menu_group "$MENU_SEPARATOR" "${group[@]}"

    toggle_group=()
    add_boolean_flag_toggles options
    if [ $is_ccloud_managed == 1 ]; then ccloud_service_account_available=1; else ccloud_service_account_available=0; fi
    add_menu_toggle $ccloud_service_account_available "$PG_CCLOUD_SERVICE_ACCOUNT" "$MENU_CCLOUD_SERVICE_ACCOUNT"
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
    add_boolean_flag_toggles images
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
        if [ -z "${!mandatory_environment_variable:-}" ]
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
      if [ $is_ccloud_managed == 1 ]
      then
        playground open --file "${test_file}"
      else
        playground open --file "${test_file}" --open-docker-compose
      fi
    fi

    if [[ $res == *"$MENU_OPEN_DOCS"* ]]
    then
      if ! can_open_url
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
        flag_list_to_args
        playground run -f "$test_file_directory/$sibling_example" --force-interactive-re-run "${flag_args[@]}"
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

    toggle_boolean_flags "$res"

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

    if [[ $res == *"$MENU_ENVIRONMENT"* ]]
    then
      # only the environments this example supports; esc: back to the menu, the previous value kept
      options=($supported_environments)
      set +e
      picked_environment=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔐" --header="select an environment" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
      set -e
      if [ -n "$picked_environment" ]
      then
        maybe_remove_flag "--environment"
        environment="$picked_environment"
        array_flag_list+=("--environment=$environment")
        export PLAYGROUND_ENVIRONMENT=$environment
      fi
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

    if [[ $res == *"$MENU_CLIENT_VERSION"* ]]
    then
      maybe_remove_flag "--client-version"
      set +e
      # the published versions of the client that the example builds, newest first (a version can also be typed)
      client_version=$(get_client_version_with_fzf "" "$test_file")
      set -e
      if [ -n "$client_version" ] && [ -n "$(validate_client_version "$client_version")" ]
      then
        logwarn "❌ --client-version $client_version ignored: $(validate_client_version "$client_version")"
        client_version=""
      fi
      if [ -n "$client_version" ]
      then
        array_flag_list+=("--client-version=$client_version")
        export CLIENT_VERSION=$client_version
      else
        unset CLIENT_VERSION
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
      cd "$test_file_directory"
      set +e
      picked_connector_zip=$(playground get-zip-or-jar-with-fzf --type zip)
      set -e
      picked_connector_zip=${picked_connector_zip#*@}
      if [ -n "$picked_connector_zip" ]
      then
        # --connector-tag and --connector-zip are exclusive; a --connector-jar is applied on top of the zip: kept
        maybe_remove_flag "--connector-zip"
        maybe_remove_flag "--connector-tag"
        unset CONNECTOR_TAG
        connector_zip="$picked_connector_zip"
        array_flag_list+=("--connector-zip=$connector_zip")
        export CONNECTOR_ZIP=$connector_zip
      fi
    fi

    if [[ $res == *"$MENU_CONNECTOR_JAR"* ]]
    then
      cd "$test_file_directory"
      set +e
      picked_connector_jar=$(playground get-zip-or-jar-with-fzf --type jar)
      set -e
      picked_connector_jar=${picked_connector_jar#*@}
      if [ -n "$picked_connector_jar" ]
      then
        # applied on top of the plugin installed with --connector-tag or --connector-zip: those are kept
        maybe_remove_flag "--connector-jar"
        connector_jar="$picked_connector_jar"
        array_flag_list+=("--connector-jar=$connector_jar")
        export CONNECTOR_JAR=$connector_jar
      fi
    fi

    if [[ $res == *"$MENU_CLUSTER_TYPE"* ]]
    then
      options=(basic standard dedicated)
      set +e
      picked_cluster_type=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔋" --header="select a cluster type" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
      set -e
      if [ -n "$picked_cluster_type" ]
      then
        maybe_remove_flag "--cluster-type"
        cluster_type="$picked_cluster_type"
        array_flag_list+=("--cluster-type $cluster_type")
        export CLUSTER_TYPE=$cluster_type
      fi
    fi

    if [[ $res == *"$MENU_CLUSTER_CLOUD"* ]]
    then
      options=(aws gcp azure)
      set +e
      picked_cluster_cloud=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --cycle --prompt="🔋" --header="select a cloud provider" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
      set -e
      if [ -n "$picked_cluster_cloud" ]
      then
        maybe_remove_flag "--cluster-cloud"
        cluster_cloud="$picked_cluster_cloud"
        array_flag_list+=("--cluster-cloud $cluster_cloud")
        export CLUSTER_CLOUD=$cluster_cloud
      fi
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

  force_enable_boolean_flags

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
# PG_RUN_PRINT_FLAGS_AND_EXIT=1 (private): the flags and the variables this run would use, then exit before anything
# is stopped or started (used to compare two versions of this command)
if [ -n "${PG_RUN_PRINT_FLAGS_AND_EXIT:-}" ]
then
  printf 'flag %s\n' "${array_flag_list[@]}" | grep -v '^flag $' | sort
  env | grep -E '^(ENABLE_[A-Z_]+|CP_[A-Z_]+_IMAGE|PLAYGROUND_ENVIRONMENT|PLAYGROUND_CONNECT_LOG_LEVELS|CONNECTOR_(TAG|ZIP|JAR)|TAG|CP_[A-Z_]+_TAG|CLUSTER_[A-Z_]+|PG_CCLOUD_SERVICE_ACCOUNT[A-Z_]*)=' | sed -E 's/^([A-Z_]*(CREDS|SECRET|PASSWORD|KEY)[A-Z_]*)=.*/\1=<masked>/' | sed 's/^/env /' | sort
  exit 0
fi

# resources left by the previous ccloud run (e.g. interrupted before its final connector delete)
maybe_cleanup_ccloud_run_resources
# already done, don't do it again in the 'playground stop' below
export PG_SKIP_CCLOUD_RUN_CLEANUP=1
# false by default: only the containers of the previous example are stopped
container_kill_all_before_run=$(playground config get container-kill-all-before-run)
if [ "$container_kill_all_before_run" == "true" ]
then
  playground container kill-all
  log "🎓 to only stop the playground containers instead: playground config container-kill-all-before-run false"
else
  playground stop
fi
unset PG_SKIP_CCLOUD_RUN_CLEANUP
set -e

# in a subshell: a bare 'IFS=' ' flag_list=…' (two assignments) would keep IFS=' ' for the rest of the run, and every
# 'for x in $list' over a multi-line list (ccloud cleanup of the connectors and topics of the run…) would loop once
flag_list=$(IFS=' '; echo "${array_flag_list[*]}")
array_declaration=$(declare -p array_flag_list)
encoded_array=$(echo "$array_declaration" | base64)
playground state set run.array_flag_list_base64 "$encoded_array"

if [ $is_ccloud == 1 ] && [[ $test_file_rel == *"ccloud"* ]]
then
  environment="ccloud"
elif [ -z "$environment" ]
then
  environment="${PLAYGROUND_ENVIRONMENT:-plaintext}"
fi

# 📄 from now on, the output also goes to a masked run log that can be shared (playground config run-log)
run_log_start
trap 'run_log_finish $?' EXIT

if [ "$flag_list" != "" ]
then
  if [[ $test_file_rel == *"ccloud"* ]]
  then
    log "🚀⛅ Running ccloud example with flags"
  else
    log "🚀 Running example with flags"
  fi
  log "⛳ Flags used are $(mask_creds_in_command "$flag_list")"
else
  if [[ $test_file_rel == *"ccloud"* ]]
  then
    log "🚀⛅ Running ccloud example without any flags"
  else
    log "🚀 Running example without any flags"
  fi
fi

playground state set run.connector_type "$(get_connector_type | tr -d '\n')"
playground state set run.test_file "$test_file"
if [[ $test_file_rel == *"ccloud"* ]]
then
  # Confluent Cloud resources created by this run are recorded with this id, see maybe_cleanup_ccloud_run_resources
  export PG_CCLOUD_RUN_ID="$(date +%s)"
  playground state set run.ccloud_run_id "$PG_CCLOUD_RUN_ID"
fi
# 🏰 what playground history knows about this example, before this run is added to it: number of runs and results
# (any flags), the last run, and the runs of this exact command when the flags differ
function show_previous_runs_of_example {
  local history_file="$root_folder/playground-run-history" summary line
  [ -f "$history_file" ] || return 0
  summary=$(HISTORY_SCRIPT="playground run -f $(printf '%q' "$test_file")" HISTORY_COMMAND="$history_line" awk '
    function duration(s) {
      if (s == "") return ""
      s += 0
      if (s >= 3600) return int(s / 3600) "h" int(s % 3600 / 60) "m"
      if (s >= 60) return int(s / 60) "m" s % 60 "s"
      return s "s"
    }
    function meta(key,    v) {
      if (index(comment, " " key "=") == 0) return ""
      v = substr(comment, index(comment, " " key "=") + length(key) + 2)
      sub(/ .*/, "", v)
      return v
    }
    function icon(r) {
      return r == "SUCCESS" ? "✅" : r == "FAILURE" ? "❌" : r == "SKIPPED" ? "⏭️" : r == "INTERRUPTED" ? "⏹️" : "▫️"
    }
    function describe(    d, r, t) {
      d = meta("date"); r = meta("result"); t = duration(meta("duration"))
      sub(/T/, " ", d)
      t = (d != "" ? substr(d, 1, 16) : "") (r != "" ? " " icon(r) " " r : "") (t != "" ? " in " t : "")
      sub(/^ /, "", t)
      return t != "" ? t : "(before dates and results were recorded)"
    }
    BEGIN { script = ENVIRON["HISTORY_SCRIPT"]; command = ENVIRON["HISTORY_COMMAND"] }
    {
      gsub(/[ \t]+/, " "); sub(/ $/, "")
      line = $0; comment = ""
      i = index($0, " # date=")
      if (i > 0) { line = substr($0, 1, i - 1); comment = " " substr($0, i + 3) }
      # the script alone, or followed by flags (a backslash-quoted space is part of the path)
      if (line != script && index(line, script " ") != 1) next
      runs++
      r = meta("result"); results[r == "" ? "unknown" : r]++
      last = describe(); last_flags = substr(line, length(script) + 2)
      if (r == "SUCCESS" && meta("duration") != "") last_success = duration(meta("duration"))
      if (line == command) { command_runs++; command_last = describe() }
    }
    END {
      if (runs == 0) { print "🆕 first run of this example (nothing in playground history)"; exit }
      counts = ""
      n = split("SUCCESS FAILURE SKIPPED INTERRUPTED unknown", order, " ")
      for (k = 1; k <= n; k++) if (results[order[k]] > 0) counts = counts " " results[order[k]] " " icon(order[k]) (order[k] == "unknown" ? " (result not recorded)" : "")
      print "🏰 ran " runs " time(s) before:" counts " · last run " last (last_flags != "" ? " with " last_flags : " without flags")
      if (command_runs < runs) print "🏰 with these exact flags: " (command_runs > 0 ? command_runs " time(s), last run " command_last : "never")
      if (last_success != "") print "⏱️ last successful run took " last_success
    }' "$history_file")
  while IFS= read -r line
  do
    [ -n "$line" ] && log "$line"
  done <<< "$summary"
  return 0
}
# shell-quoted, so that 'playground history' and eval replay it as is; credentials are not written
history_line="playground run -f $(printf '%q' "$test_file")"
flag_list_to_args
if [ ${#flag_args[@]} -gt 0 ]
then
  history_line+="$(printf ' %q' "${flag_args[@]}")"
fi
history_line=$(mask_creds_in_command "$history_line")
show_previous_runs_of_example
# a trailing comment, ignored by eval: the result and the duration are added when the run ends (record_run_in_history)
history_branch=$(git -C "$root_folder" rev-parse --abbrev-ref HEAD 2> /dev/null)
history_entry="$history_line # date=$(date +%Y-%m-%dT%H:%M:%S)${history_branch:+ branch=$history_branch}"
file_lock "$root_folder/playground-run-history"
echo "$history_entry" >> "$root_folder/playground-run-history"
file_unlock "$root_folder/playground-run-history"

if [[ "$OSTYPE" == "darwin"* ]]
then
    clipboard=$(playground config get clipboard)
    if [ "$clipboard" == "" ]
    then
        playground config set clipboard true
    fi

    if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
    then
        # shell-quoted like the history line, credentials masked
        echo "$history_line" | pbcopy
        log "📋 command to run again example has been copied to the clipboard (disable with 'playground config clipboard false')"
        if [[ "$history_line" == *"'<masked>'"* ]]
        then
          log "🙈 the credentials are masked in it: replace '<masked>', or use 'playground re-run' / 'playground history --run'"
        fi
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
function record_run_in_history {
  local result="FAILURE" history_file="$root_folder/playground-run-history"
  case "$1" in
    0) result="SUCCESS" ;;
    111) result="SKIPPED" ;;
    130|143) result="INTERRUPTED" ;;
  esac
  [ -f "$history_file" ] || return 0
  # locked, and replaced in one mv: a run starting now appends its line in the meantime (lost with 'cat tmp > file')
  file_lock "$history_file"
  # the last line of this run: other runs of this checkout may have been added since
  HISTORY_ENTRY="$history_entry" HISTORY_SUFFIX=" result=$result duration=$SECONDS" awk '
    NR == FNR { if ($0 == ENVIRON["HISTORY_ENTRY"]) last = FNR; next }
    FNR == last { $0 = $0 ENVIRON["HISTORY_SUFFIX"] }
    { print }' "$history_file" "$history_file" > "$history_file.tmp.$$" && mv -f "$history_file.tmp.$$" "$history_file"
  rm -f "$history_file.tmp.$$"
  file_unlock "$history_file"
}
function cleanup {
  # 💡 Capture the original exit status immediately!
  local original_exit_status=$?
  set +e
  record_run_in_history "$original_exit_status"
  rm -f /tmp/playground-run-command-used
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

  if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
  then
    playground connector status
  elif [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
  then
    # without --connector: every connector of the run. In CI, they were just deleted (maybe_cleanup_ccloud_run_resources)
    if [ -z "$GITHUB_RUN_NUMBER" ]
    then
      playground connector status
    fi
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

  # (the documentation of the connector plugin is in the output of 'playground connector versions')

  if [ -z "$GITHUB_RUN_NUMBER" ]
  then
    log "🧭 next steps:"
    if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
    then
      log "   🩺 connector health, lag and errors: playground connector diagnose"
    fi
    if [[ "$(basename "$test_file")" != *repro* ]]
    then
      log "   🐞 reproduction model from it:       playground repro bootstrap -f $test_file -d \"<case> <symptom>\" --no-run"
    fi
    if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
    then
      log "   🔢 with another connector version:   playground run -f $test_file --connector-tag <version>"
    fi
    # the ksqlDB / Flink flags are recorded by start-environment: a fully managed (or custom) connector example doesn't
    # run it, the flags are the ones of the previous local run
    if [ $is_ccloud_managed == 0 ] && [ "$(playground state get flags.ENABLE_KSQLDB 2> /dev/null)" == "1" ]
    then
      log "   🧮 streams, tables and queries:      playground ksqldb list"
      log "   🧮 run ksqlDB statements:            playground ksqldb sql <<< \"SHOW QUERIES;\""
      log "   🔢 with another ksqlDB version:      playground run -f $test_file --ksqldb-tag <version>"
    fi
    if [ $is_ccloud_managed == 0 ] && [ "$(playground state get flags.ENABLE_FLINK 2> /dev/null)" == "1" ]
    then
      log "   🐿️ Flink jobs:                       playground flink list-jobs"
    fi
    log "   🔁 run it again:                     playground re-run"
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
# first run of a clone or worktree: the source code link at the end needs it, and the refresh started after the example
# would not be over by then
if [ ! -f $root_folder/scripts/cli/confluent-hub-plugin-list.txt ]
then
  playground generate-connector-plugin-list > /dev/null 2>&1 &
fi

# only shown for non ccloud examples (the ccloud costs are shown instead)
if [[ $test_file_rel == *"ccloud"* ]]
then
    :
elif [[ $test_file_rel == *"aws"* ]]
then
    playground cloud-resources aws costs-history --no-open > /tmp/aws-costs-history.txt 2>/dev/null &
elif [[ $test_file_rel == *"azure"* ]]
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
sql_datagen_ret=0
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
  log "✅ RESULT: SUCCESS for $filename ($ELAPSED)"
  log "####################################################"
  if [ -n "$sql_datagen" ]
  then
    # SQL_DATAGEN_DURATION (minutes, default 10) and SQL_DATAGEN_SESSIONS (default 5)
    sql_datagen_inject "$test_file" "${SQL_DATAGEN_DURATION:-10}" "${SQL_DATAGEN_SESSIONS:-5}" || sql_datagen_ret=$?
    if [ $sql_datagen_ret -ne 0 ]
    then
      logerror "❌ --enable-sql-datagen: the injection failed (exit code $sql_datagen_ret)"
    fi
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
  log "⏭ RESULT: SKIPPED for $filename ($ELAPSED)"
  log "####################################################"
  
  exit $ret
else
  logerror "####################################################"
  logerror "🔥 RESULT: FAILURE for $filename ($ELAPSED)"
  logerror "####################################################"

  # hints that fit what the example ran: the connector type is recorded before the example runs, the ksqlDB / Flink
  # flags by start-environment
  failed_connector_type=$(playground state get run.connector_type 2> /dev/null)
  log "🧑‍🚒 you can troubleshoot the issue by running:"
  if [ "$failed_connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$failed_connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ] || [ "$failed_connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
  then
    echo "playground connector diagnose          # status, error digest, lag and offsets of the connector(s)"
  fi
  if [ $is_ccloud_managed == 0 ]
  then
    if [ "$(playground state get flags.ENABLE_KSQLDB 2> /dev/null)" == "1" ]
    then
      echo "playground ksqldb list                 # streams, tables and queries: a query in ERROR?"
      echo "playground container logs -c ksqldb-server --errors"
    fi
    if [ "$(playground state get flags.ENABLE_FLINK 2> /dev/null)" == "1" ]
    then
      echo "playground flink list-jobs --state FAILED"
    fi
    echo "playground container display-error-all # errors of every container"
    echo "playground container logs -c connect --errors   # error digest of one container (--open for the full logs)"
  fi

  # a failed fully managed example is when a connector gets left running: the nightly cleanup, your own clusters
  if [ -z "$GITHUB_RUN_NUMBER" ] && [[ $test_file_rel == *"ccloud"* ]]
  then
    display_ccloud_hints || true
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
# the example succeeded: what follows is informational (ec2, grafana, costs…), a failure there must not end the run with
# an error after the SUCCESS banner (and record it as a FAILURE in the history)
set +e
check_for_ec2_instance_running

if [ ! -z "$ENABLE_JMX_GRAFANA" ]
then
  echo ""
  if [[ $test_file_rel == *"ccloud"* ]]
  then
    log "🛡️ Prometheus is reachable at http://127.0.0.1:9090"
    log "📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password)"
  else
    log "📛 Pyroscope is reachable at http://127.0.0.1:4040"
    log "🛡️ Prometheus is reachable at http://127.0.0.1:9090"
    log "📊 Grafana is reachable at http://127.0.0.1:3000 (login/password is admin/password)"
  fi

  if [ $is_fully_managed == 0 ]
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

        if ! can_open_url
        then
            log "🔗 Cannot open browser, use url:"
            echo "http://127.0.0.1:3000"
        else
            if [ "$browser" != "" ]
            then
            log "🤖 automatically (disable with 'playground config open-grafana-in-browser automatically false') open grafana in browser $browser (you can change browser with 'playground config open-grafana-in-browser browser <browser>')"
            log "🤖 Open grafana with browser $browser (login/password is admin/password)"
            open_url "http://127.0.0.1:3000" "$browser"
            else
            log "🤖 automatically (disable with 'playground config open-grafana-in-browser automatically false') open grafana in default browser (you can set browser with 'playground config open-grafana-in-browser browser <browser>')"
            log "🤖 Open grafana (login/password is admin/password)"
            open_url "http://127.0.0.1:3000"
            fi
        fi
        fi
    fi
  fi
fi

if [ -z "$GITHUB_RUN_NUMBER" ]
then
  if [[ $test_file_rel == *"ccloud"* ]]
  then
    echo ""
    # wait that process with "playground cloud-resources ccloud costs-history" is finished
    set +e
    while pgrep -f "playground cloud-resources ccloud costs-history" > /dev/null
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
    log "👀 all the details are in the HTML report above, or run <playground cloud-resources ccloud costs-history --detailed>"
    # best effort: the example already succeeded, a failure to list the leftovers must not change the exit code
    display_ccloud_leftovers || true
    display_ccloud_hints || true
  elif [[ $test_file_rel == *"aws"* ]]
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
  elif [[ $test_file_rel == *"azure"* ]]
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

# the example succeeded, but --enable-sql-datagen or --benchmark did not
if [ $sql_datagen_ret -ne 0 ]
then
  exit $sql_datagen_ret
fi
if [ $benchmark_ret -ne 0 ]
then
  exit $benchmark_ret
fi
