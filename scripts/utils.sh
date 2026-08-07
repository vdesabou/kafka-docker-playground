DIR_UTILS="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR_UTILS}/../scripts/cli/src/lib/utils_function.sh

function install_connector_with_retry {
  local install_command="$1"
  local max_retries=${CONNECTOR_INSTALL_MAX_RETRIES:-5}
  local retry_delay_seconds=${CONNECTOR_INSTALL_RETRY_DELAY_SECONDS:-10}
  local attempt=1

  while [ "$attempt" -le "$max_retries" ]
  do
    set +e
    eval "$install_command" > /tmp/result.log 2>&1
    local status=$?
    set -e

    if [ "$status" -eq 0 ]
    then
      return 0
    fi

    if grep -Eiq "java\.net\.ConnectException|Connection refused" /tmp/result.log
    then
      if [ "$attempt" -lt "$max_retries" ]
      then
        logwarn "Transient connection error while installing connector (attempt $attempt/$max_retries), retrying in ${retry_delay_seconds}s"
        sleep "$retry_delay_seconds"
      fi
    else
      return "$status"
    fi

    attempt=$((attempt+1))
  done

  return 1
}

function run_solace_cli_script_with_retry {
  local script_name="$1"
  local description="$2"
  local output_file="${3:-/tmp/solace-cli-${script_name}.log}"
  local max_wait=${SOLACE_CLI_MAX_WAIT:-300}
  local attempt_timeout=${SOLACE_CLI_ATTEMPT_TIMEOUT:-60}
  local cur_wait=0

  log "⌛ Waiting up to $max_wait seconds for Solace CLI to be ready for ${description}"
  while true
  do
    set +e
    timeout "$attempt_timeout" playground container exec --container solace --command "bash -c \"/usr/sw/loads/currentload/bin/cli -A -s cliscripts/${script_name}\"" > "$output_file" 2>&1 < /dev/null
    local ret=$?
    set -e

    if [ "$ret" -eq 0 ]
    then
      log "Solace CLI is ready for ${description}"
      return 0
    fi

    if [ "$ret" -eq 124 ]
    then
      logwarn "Solace CLI did not respond within ${attempt_timeout}s for ${description}, retrying... (${cur_wait}/${max_wait}s)"
    fi

    sleep 10
    cur_wait=$((cur_wait + 10))
    if [ "$cur_wait" -gt "$max_wait" ]
    then
      logerror "Solace CLI is not ready for ${description} after ${max_wait} seconds"
      cat "$output_file"
      exit 1
    fi
  done
}

function cleanup-workaround-file {
  rm -f /tmp/without-cli-workaround > /dev/null 2>&1
}

# Errors that mean "the external system briefly misbehaved", not "this config is wrong".
# Kept deliberately narrow: anything not listed here fails on the first attempt, so a real
# misconfiguration or a genuine connector bug is never retried into a green run.
#
# INVALID_SESSION_ID is included: Salesforce reuses one session across identical
# username-password logins by the same user, so a concurrent logout elsewhere can
# invalidate the session validation is holding. Retrying re-authenticates.
SALESFORCE_TRANSIENT_CREATE_ERRORS="${SALESFORCE_TRANSIENT_CREATE_ERRORS:-\
Exception encountered while calling salesforce|\
Read timed out|Connection reset|Connection refused|\
502 Bad Gateway|503 Service Unavailable|504 Gateway|\
SERVER_UNAVAILABLE|Server Unavailable|UNABLE_TO_LOCK_ROW|\
INVALID_SESSION_ID}"

# The same idea for the sfdx CLI steps (login, record create, Apex). These run before and
# around the connector, and a blip in any of them aborts the test just as hard.
#
# "Could not retrieve the username after successful auth code exchange" is observed in CI:
# sfpowerkit:auth:login failed with it, and the identical login with the identical
# credentials succeeded 15 seconds later in the same test's teardown - so it is transient.
SALESFORCE_TRANSIENT_SFDX_ERRORS="${SALESFORCE_TRANSIENT_SFDX_ERRORS:-\
Could not retrieve the username after successful auth code exchange|\
Session expired or invalid|INVALID_SESSION_ID|Bad_OAuth_Token|\
Read timed out|Connection reset|Connection refused|ETIMEDOUT|ECONNRESET|EAI_AGAIN|\
socket hang up|502 Bad Gateway|503 Service Unavailable|504 Gateway|\
SERVER_UNAVAILABLE|Server Unavailable|UNABLE_TO_LOCK_ROW}"

# Errors that must NEVER be retried, checked before the transient lists above.
#
# REQUEST_LIMIT_EXCEEDED is the org's 24h API request cap. Retrying spends more of the
# very budget that is exhausted, and when it hits, every test fails at once - which looks
# exactly like a session bug unless it is called out explicitly.
#
# DUPLICATES_DETECTED and the *_REQUIRED_FIELD / INVALID_FIELD family are deterministic:
# the same request will fail the same way however many times it is sent.
SALESFORCE_FATAL_ERRORS="${SALESFORCE_FATAL_ERRORS:-\
REQUEST_LIMIT_EXCEEDED|TotalRequests Limit exceeded|\
DUPLICATES_DETECTED|REQUIRED_FIELD_MISSING|INVALID_FIELD|\
INSUFFICIENT_ACCESS|INVALID_LOGIN}"

# Retries consumed so far by this test. Reset per test process, since each test runs in
# its own shell - so the budget below is genuinely per test, not per connector.
SALESFORCE_CREATE_RETRIES_USED=0

# Create a connector, retrying only when validation failed for a transient reason.
#
# Connector validation calls out to Salesforce (token endpoint, /services/data/,
# describeSObject). A single blip there aborts the whole test even though nothing is
# wrong with the connector or the test. Observed in CI: validation got HTTP 404 from
# /services/data/ one second after a successful JWT auth, twice, then the identical
# commit passed - so the failure is intermittent and upstream.
#
# Usage is identical to `playground connector create-or-update --connector X << EOF`:
#
#   salesforce_create_connector_with_retry salesforce-cdc-source << EOF
#   { ... }
#   EOF
#
# The retry budget is per TEST, not per connector: SALESFORCE_CREATE_MAX_RETRIES retries
# are shared across every connector a test creates, so a test that creates three
# connectors cannot spend three retries on each of them. First attempts are never
# counted against the budget.
#
# The body is read from stdin once and replayed on each attempt.
function salesforce_create_connector_with_retry() {
  local connector="$1"
  local max_retries="${SALESFORCE_CREATE_MAX_RETRIES:-3}"
  local delay="${SALESFORCE_CREATE_RETRY_DELAY:-15}"
  local body attempt=1 rc out had_errexit=0

  # Remember whether the caller had errexit on, so it can be restored exactly. Setting
  # it unconditionally would turn it on for callers that deliberately had it off - the
  # cleanup traps run under set +e.
  case $- in
    *e*) had_errexit=1 ;;
  esac

  body="$(cat)"

  while true
  do
    set +e
    out="$(printf '%s\n' "$body" | playground connector create-or-update --connector "$connector" 2>&1)"
    rc=$?
    if [ $had_errexit -eq 1 ]
    then
      set -e
    fi
    echo "$out"

    if [ $rc -eq 0 ]
    then
      if [ $attempt -gt 1 ]
      then
        log "✅ $connector created on attempt $attempt"
      fi
      return 0
    fi

    if echo "$out" | grep -qE "$SALESFORCE_FATAL_ERRORS"
    then
      logerror "❌ $connector creation hit a limit or a deterministic rejection that retrying cannot fix, not retrying"
      return $rc
    fi

    if ! echo "$out" | grep -qE "$SALESFORCE_TRANSIENT_CREATE_ERRORS"
    then
      logerror "❌ $connector creation failed for a non-transient reason, not retrying"
      return $rc
    fi

    if [ "$SALESFORCE_CREATE_RETRIES_USED" -ge "$max_retries" ]
    then
      logerror "❌ $connector hit a transient error but this test has already used its $max_retries retry(ies)"
      return $rc
    fi

    SALESFORCE_CREATE_RETRIES_USED=$((SALESFORCE_CREATE_RETRIES_USED + 1))
    logwarn "⚠️ transient error creating $connector, retrying in ${delay}s (retry $SALESFORCE_CREATE_RETRIES_USED/$max_retries for this test)"
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

# Run an sfdx command in the sfdx-cli container, retrying only on a transient failure.
#
# Every sfdx step in these tests runs under `set -e`, so a single blip in a login, a record
# create or an Apex run aborts the test even though nothing is wrong with the connector.
# Only connector creation was retried before this; the steps around it were not.
#
# Usage mirrors the call it replaces:
#
#   salesforce_sfdx_with_retry "sfdx sfpowerkit:auth:login -u \"$USER\" ..."
#
# and for the commands that pipe Apex in on stdin:
#
#   salesforce_sfdx_with_retry --stdin "sfdx apex run --target-org \"$USER\"" << EOF
#   Database.delete(...);
#   EOF
#
# The retry budget is shared with salesforce_create_connector_with_retry, so
# SALESFORCE_CREATE_MAX_RETRIES is the ceiling for the whole test, not per step.
function salesforce_sfdx_with_retry() {
  local use_stdin=0

  if [ "$1" == "--stdin" ]
  then
    use_stdin=1
    shift
  fi

  local sfdx_command="$1"
  local label="${2:-$(echo "$sfdx_command" | awk '{print $1" "$2}')}"
  local max_retries="${SALESFORCE_CREATE_MAX_RETRIES:-3}"
  local delay="${SALESFORCE_CREATE_RETRY_DELAY:-15}"
  local body="" attempt=1 rc out had_errexit=0

  # As in salesforce_create_connector_with_retry: restore the caller's errexit exactly,
  # because the cleanup traps deliberately run with it off.
  case $- in
    *e*) had_errexit=1 ;;
  esac

  if [ $use_stdin -eq 1 ]
  then
    body="$(cat)"
  fi

  while true
  do
    set +e
    if [ $use_stdin -eq 1 ]
    then
      out="$(printf '%s\n' "$body" | playground container exec --container sfdx-cli --command "$sfdx_command" --shell sh 2>&1)"
    else
      out="$(playground container exec --container sfdx-cli --command "$sfdx_command" --shell sh 2>&1)"
    fi
    rc=$?
    if [ $had_errexit -eq 1 ]
    then
      set -e
    fi
    echo "$out"

    if [ $rc -eq 0 ]
    then
      if [ $attempt -gt 1 ]
      then
        log "✅ $label succeeded on attempt $attempt"
      fi
      return 0
    fi

    if echo "$out" | grep -qE "$SALESFORCE_FATAL_ERRORS"
    then
      logerror "❌ $label hit a limit or a deterministic rejection that retrying cannot fix, not retrying"
      return $rc
    fi

    if ! echo "$out" | grep -qE "$SALESFORCE_TRANSIENT_SFDX_ERRORS"
    then
      logerror "❌ $label failed for a non-transient reason, not retrying"
      return $rc
    fi

    if [ "$SALESFORCE_CREATE_RETRIES_USED" -ge "$max_retries" ]
    then
      logerror "❌ $label hit a transient error but this test has already used its $max_retries retry(ies)"
      return $rc
    fi

    SALESFORCE_CREATE_RETRIES_USED=$((SALESFORCE_CREATE_RETRIES_USED + 1))
    logwarn "⚠️ transient error during $label, retrying in ${delay}s (retry $SALESFORCE_CREATE_RETRIES_USED/$max_retries for this test)"
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

# Re-authenticate the sfdx CLI for one account. Pass "" for the primary account or
# "_ACCOUNT2" for the second.
#
# Cleanup needs this. A connector on the username-password SOAP grant ends its session with
# logout() during validation, and Salesforce reuses one session across identical logins by
# the same user - so it also kills the session the sfdx CLI is holding. By the time the EXIT
# trap runs, `sfdx apex run` fails with "Session expired or invalid" and the test's records
# are never deleted. Retrying cannot help: re-running the command does not re-authenticate.
#
# Observed locally on CP 8.3.0: salesforce-bulkapi-source and
# salesforce-bulkapi-sink-with-bulkapi-source each burned all three retries on the cleanup
# Apex and still left their Lead behind. The five tests whose connectors use JWT were
# unaffected. Re-authenticating restores what KDP commit 478e93a5 removed.
function salesforce_sfdx_relogin() {
  local suffix="${1:-}"
  local uv="SALESFORCE_USERNAME${suffix}" pv="SALESFORCE_PASSWORD${suffix}"
  local tv="SALESFORCE_SECURITY_TOKEN${suffix}" iv="SALESFORCE_INSTANCE${suffix}"
  local u="${!uv}" p="${!pv}" t="${!tv}" i="${!iv:-https://login.salesforce.com}"

  if [ -z "$u" ] || [ -z "$p" ] || [ -z "$t" ]
  then
    logwarn "⚠️ cannot re-authenticate sfdx for account '${suffix:-primary}', credentials not set"
    return 1
  fi

  log "🔑 Re-authenticating sfdx for $u before cleanup"
  salesforce_sfdx_with_retry "sfdx sfpowerkit:auth:login -u \"$u\" -p \"$p\" -r \"$i\" -s \"$t\""
}

# Assert a topic is empty, and fail the test if it is not.
#
# `playground topic consume --min-expected-messages 0` does NOT assert anything: with 0 the
# CLI skips its count check entirely and only warns when the topic is missing. The sink
# tests used it for error-responses, so a partial failure (one good record plus N errored
# ones) satisfied "success-responses >= 1" and the errors were never looked at.
function salesforce_assert_topic_empty() {
  local topic="$1"
  local nb_messages=""

  nb_messages=$(playground topic get-number-records -t "$topic" 2>/dev/null | tail -1)

  # A topic that was never created means the connector produced no errors at all.
  if [[ ! "$nb_messages" =~ ^[0-9]+$ ]]
  then
    log "✅ topic $topic contains no records (topic was never created)"
    return 0
  fi

  if [ "$nb_messages" -gt 0 ]
  then
    logerror "❌ topic $topic should be empty but contains $nb_messages message(s)"
    playground topic consume --topic "$topic" --max-messages -1 || true
    return 1
  fi

  log "✅ topic $topic is empty, as expected"
}

function salesforce_ensure_jwt_keystore() {
  local target_dir="${1:-$PWD}"
  local keystore_path="$target_dir/salesforce-confluent.keystore.jks"

  if [ ! -f "$keystore_path" ]
  then
    # Keep stdout clean for command substitution callers; logs still go to stderr.
    (cd "$target_dir" && get_3rdparty_file "salesforce-confluent.keystore.jks") >&2
  fi

  if [ ! -f "$keystore_path" ]
  then
    logerror "❌ $keystore_path is missing. Check README !"
    exit 1
  fi

  echo "$keystore_path"
}

function salesforce_get_jwt_keystore_base64() {
  local target_dir="${1:-$PWD}"
  local keystore_path=""

  keystore_path=$(salesforce_ensure_jwt_keystore "$target_dir")
  base64 < "$keystore_path" | tr -d '\n'
}

if [ ! -f /tmp/playground-run-command-used ]
then
  # fm examples not working without using CLI #5635
  if [ ! -f /tmp/without-cli-workaround ]
  then
    trap cleanup-workaround-file EXIT
    test_file="$PWD/$0"
    filename=$(basename $test_file)
    if [[ "$filename" != "playground-command"* ]]
    then
      playground state set run.test_file "$test_file"
      playground state set run.connector_type "$(get_connector_type | tr -d '\n')"
      touch /tmp/without-cli-workaround
    fi
  fi
fi

if [ -z "$FLINK_TAG" ]
then
    # FLINK_TAG is not set, use default:
    export FLINK_TAG=latest
fi

# Setting up TAG environment variable
#
if [ -z "$TAG" ]
then
    # TAG is not set, use default:
    export TAG=8.3.0 # default tag
    # to handle ubi8 images
    export TAG_BASE="$TAG"
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ] && [ -z "$DOCKER_COMPOSE_FILE_UPDATE_VERSION" ]
      then
        log "💫 Using default CP version $TAG"
        log "🎓 Use --tag option to specify different version, see https://kafka-docker-playground.io/#/how-to-use?id=🎯-for-confluent-platform-cp"
      fi
    fi
    export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL=""
    export CONNECT_USER="appuser"

    if [ -z "$CP_ZOOKEEPER_IMAGE" ]
    then
      export CP_ZOOKEEPER_IMAGE=confluentinc/cp-zookeeper
    fi

    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      export CP_KAFKA_IMAGE=confluentinc/cp-server
    fi

    if [ -z "$CP_CONNECT_IMAGE" ]
    then
      export CP_CONNECT_IMAGE=confluentinc/cp-server-connect-base
    fi

    if [ -z "$CP_SCHEMA_REGISTRY_IMAGE" ]
    then
      export CP_SCHEMA_REGISTRY_IMAGE=confluentinc/cp-schema-registry
    fi

    if [ -z "$CP_CONTROL_CENTER_IMAGE" ]
    then
      if [ ! -z "$ENABLE_LEGACY_CONTROL_CENTER" ]
      then
        log "💠👨‍🦳 ENABLE_LEGACY_CONTROL_CENTER is set, using legacy Control Center"
        export CP_CONTROL_CENTER_IMAGE=confluentinc/cp-enterprise-control-center
      else
        log "💠⭐ Using CP Control Center Next Gen"
        export CP_CONTROL_CENTER_IMAGE=confluentinc/cp-enterprise-control-center-next-gen
      fi
    fi

    if [ -z "$CP_REST_PROXY_IMAGE" ]
    then
      export CP_REST_PROXY_IMAGE=confluentinc/cp-kafka-rest
    fi

    if [ -z "$CP_KSQL_IMAGE" ]
    then
      export CP_KSQL_IMAGE=confluentinc/cp-ksqldb-server
    fi

    if [ -z "$CP_KSQL_CLI_IMAGE" ]
    then
      export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksqldb-server
    fi

    if [ -z "$CP_ZOOKEEPER_TAG" ]
    then
      export CP_ZOOKEEPER_TAG="$TAG"
    fi

    if [ -z "$CP_KAFKA_TAG" ]
    then
      export CP_KAFKA_TAG="$TAG"
    fi

    if [ -z "$CP_CONNECT_TAG" ]
    then
      export CP_CONNECT_TAG="$TAG"
    fi

    if [ -z "$CP_SCHEMA_REGISTRY_TAG" ]
    then
      export CP_SCHEMA_REGISTRY_TAG="$TAG"
    fi

    if [ -z "$CP_CONTROL_CENTER_TAG" ]
    then
      if [ ! -z "$ENABLE_LEGACY_CONTROL_CENTER" ]
      then
        export CP_CONTROL_CENTER_TAG="$TAG"
      else
        export CP_CONTROL_CENTER_TAG=latest
      fi
    fi

    if [ -z "$CP_REST_PROXY_TAG" ]
    then
      export CP_REST_PROXY_TAG="$TAG"
    fi

    if [ -z "$CP_KSQL_TAG" ]
    then
      export CP_KSQL_TAG="$TAG"
    fi

    if [ -z "$CP_KSQL_CLI_TAG" ]
    then
      export CP_KSQL_CLI_TAG="$TAG"
    fi
    set_kafka_client_tag
    maybe_create_image
else
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
      then
        log "🚀 Using specified CP version $TAG"
      fi
    fi

    if [ -z "$CP_ZOOKEEPER_IMAGE" ]
    then
      export CP_ZOOKEEPER_IMAGE=confluentinc/cp-zookeeper
    fi
    if [ -z "$CP_SCHEMA_REGISTRY_IMAGE" ]
    then
      export CP_SCHEMA_REGISTRY_IMAGE=confluentinc/cp-schema-registry
    fi
    if [ -z "$CP_REST_PROXY_IMAGE" ]
    then
      export CP_REST_PROXY_IMAGE=confluentinc/cp-kafka-rest
    fi

    if [ -z "$CP_CONTROL_CENTER_IMAGE" ]
    then
      if [ ! -z "$ENABLE_LEGACY_CONTROL_CENTER" ]
      then
        log "💠👨‍🦳 ENABLE_LEGACY_CONTROL_CENTER is set, using legacy Control Center"
        export CP_CONTROL_CENTER_IMAGE=confluentinc/cp-enterprise-control-center
      else
        log "💠⭐ Using CP Control Center Next Gen"
        export CP_CONTROL_CENTER_IMAGE=confluentinc/cp-enterprise-control-center-next-gen
      fi
    fi

    if [ -z "$CP_ZOOKEEPER_TAG" ]
    then
      export CP_ZOOKEEPER_TAG="$TAG"
    fi

    if [ -z "$CP_KAFKA_TAG" ]
    then
      export CP_KAFKA_TAG="$TAG"
    fi

    if [ -z "$CP_CONNECT_TAG" ]
    then
      export CP_CONNECT_TAG="$TAG"
    fi

    if [ -z "$CP_SCHEMA_REGISTRY_TAG" ]
    then
      export CP_SCHEMA_REGISTRY_TAG="$TAG"
    fi

    if [ -z "$CP_CONTROL_CENTER_TAG" ]
    then
      if [ ! -z "$ENABLE_LEGACY_CONTROL_CENTER" ]
      then
        export CP_CONTROL_CENTER_TAG="$TAG"
      else
        export CP_CONTROL_CENTER_TAG=latest
      fi
    fi

    if [ -z "$CP_REST_PROXY_TAG" ]
    then
      export CP_REST_PROXY_TAG="$TAG"
    fi

    if [ -z "$CP_KSQL_TAG" ]
    then
      export CP_KSQL_TAG="$TAG"
    fi
    # to handle ubi8 images
    export TAG_BASE=$(echo $TAG | cut -d "-" -f1)
    first_version=${TAG_BASE}
    second_version=5.2.99
    if version_gt $first_version $second_version; then
        if [ "$first_version" = "5.3.6" ]
        then
          if [ -z "$CP_KAFKA_IMAGE" ]
          then
            logwarn "Workaround for 5.3.6 image broker, using custom image vdesabou/cp-server !"
            export CP_KAFKA_IMAGE=vdesabou/cp-server
          fi
        else
          if [ -z "$CP_KAFKA_IMAGE" ]
          then
            export CP_KAFKA_IMAGE=confluentinc/cp-server
          fi
        fi
    else
      if [ -z "$CP_KAFKA_IMAGE" ]
      then
        export CP_KAFKA_IMAGE=confluentinc/cp-enterprise-kafka
      fi
    fi
    second_version=5.4.99
    if version_gt $first_version $second_version; then
      if [ -z "$CP_KSQL_IMAGE" ]
      then
        export CP_KSQL_IMAGE=confluentinc/cp-ksqldb-server
      fi
      if version_gt $first_version 8.0.99
      then
        if [ -z "$CP_KSQL_CLI_IMAGE" ]
        then
            export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksqldb-server
        fi
      else
        if [ -z "$CP_KSQL_CLI_IMAGE" ]
        then
            export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksqldb-cli
        fi
      fi
      if [ -z "$CP_KSQL_CLI_TAG" ]
      then
        export CP_KSQL_CLI_TAG=${TAG_BASE}
      fi
    else
      if [ -z "$CP_KSQL_IMAGE" ]
      then
        export CP_KSQL_IMAGE=confluentinc/cp-ksql-server
      fi
      if [ -z "$CP_KSQL_CLI_IMAGE" ]
      then
        export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksql-cli
      fi
      if [ -z "$CP_KSQL_CLI_TAG" ]
      then
        export CP_KSQL_CLI_TAG=${TAG_BASE}
      fi
    fi
    second_version=5.2.99
    if version_gt $first_version $second_version; then
        if [ "$first_version" == "5.3.6" ]
        then
          logwarn "Workaround for ST-6539, using custom image vdesabou/cp-server-connect-base !"
          export CP_CONNECT_IMAGE=vdesabou/cp-server-connect-base
        else
          if [ -z "$CP_CONNECT_IMAGE" ]
          then
            export CP_CONNECT_IMAGE=confluentinc/cp-server-connect-base
          fi
        fi
    else
        if [ -z "$CP_CONNECT_IMAGE" ]
        then
          export CP_CONNECT_IMAGE=confluentinc/cp-kafka-connect-base
        fi
    fi
    second_version=5.3.99
    if version_gt $first_version $second_version; then
        export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL=""
    else
        if [ -z "$LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL" ]
        then
          log "👴 Legacy config for client connecting to HTTPS SR is set, see https://docs.confluent.io/platform/current/schema-registry/security/index.html#additional-configurations-for-https"
          export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL="-Djavax.net.ssl.trustStore=/etc/kafka/secrets/kafka.connect.truststore.jks -Djavax.net.ssl.trustStorePassword=confluent -Djavax.net.ssl.keyStore=/etc/kafka/secrets/kafka.connect.keystore.jks -Djavax.net.ssl.keyStorePassword=confluent"
        fi
    fi
    set_kafka_client_tag
    maybe_create_image
fi

# Setting grafana agent based  
if [ -z "$ENABLE_JMX_GRAFANA" ]
then
  # defaulting to empty variable since this is default in kafka-run-class.sh & avoid warning
  export GRAFANA_AGENT_ZK=""
  export GRAFANA_AGENT_BROKER=""
  export GRAFANA_AGENT_CONNECT=""
  export GRAFANA_AGENT_PRODUCER=""
  export GRAFANA_AGENT_CONSUMER=""
  export GRAFANA_AGENT_SR=""
  export GRAFANA_AGENT_KSQLDB=""
  export GRAFANA_FLINK=""
else
  export GRAFANA_AGENT_ZK="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=1234:/usr/share/jmx_exporter/zookeeper.yml"
  export GRAFANA_AGENT_BROKER="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=1234:/usr/share/jmx_exporter/kafka_broker.yml"
  export GRAFANA_AGENT_CONNECT="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=1234:/usr/share/jmx_exporter/kafka_connect.yml"
  export GRAFANA_AGENT_PRODUCER="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=1234:/usr/share/jmx_exporter/kafka-producer.yml"
  export GRAFANA_AGENT_CONSUMER="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=1234:/usr/share/jmx_exporter/kafka-consumer.yml"
  export GRAFANA_AGENT_SR="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=1234:/usr/share/jmx_exporter/confluent_schemaregistry.yml"
  export GRAFANA_AGENT_KSQLDB="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=1234:/usr/share/jmx_exporter/confluent_ksql.yml"
  export GRAFANA_FLINK="metrics.reporter.prom.factory.class: org.apache.flink.metrics.prometheus.PrometheusReporterFactory
        metrics.reporter.prom.port: 9090"
fi

if [ ! -z "$CONNECTOR_TAG" ] && [ ! -z "$CONNECTOR_ZIP" ]
then
  logerror "CONNECTOR_TAG and CONNECTOR_ZIP are both set, they cannot be used at same time!"
  exit 1
fi

###
#  CONNECTOR_TAG is set
###
if [ ! -z "$CONNECTOR_TAG" ]
then
  if [[ $0 == *"environment"* ]]
  then
    # log "DEBUG: start.sh from environment folder. Skipping..."
    if [ -z "$CP_CONNECT_TAG" ]
    then
      export CP_CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"stop.sh"* ]]
  then
    if [ -z "$CP_CONNECT_TAG" ]
    then
      export CP_CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"run-tests"* ]]
  then
    :
  else
    if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
    then
      log "🎯 CONNECTOR_TAG (--connector-tag option) is set with version $CONNECTOR_TAG"
    fi
    # determining the connector from current path
    docker_compose_file=""
    if [ ! -z "$DOCKER_COMPOSE_FILE_UPDATE_VERSION" ]
    then
      docker_compose_file=$DOCKER_COMPOSE_FILE_UPDATE_VERSION
    elif [ -f "$PWD/$0" ]
    then
      docker_compose_file=$(grep "start-environment" "$PWD/$0" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
    fi
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
      if [ "$connector_paths" == "" ]
      then
        # not a connector test
        if [ -z "$CP_CONNECT_TAG" ]
        then
          export CP_CONNECT_TAG="$TAG"
        fi
      else
        ###
        #  Loop on all connectors in CONNECT_PLUGIN_PATH and install latest version from Confluent Hub (except for JDBC and replicator)
        ###
        first_loop=true
        i=0
        my_array_connector_tag=($(echo $CONNECTOR_TAG | tr "," "\n"))
        for connector_path in ${connector_paths//,/ }
        do
          connector_path=$(echo "$connector_path" | cut -d "/" -f 5)
          owner=$(echo "$connector_path" | cut -d "-" -f 1)
          name=$(echo "$connector_path" | cut -d "-" -f 2-)

          CONNECTOR_VERSION="${my_array_connector_tag[$i]}"
          if [ "$CONNECTOR_VERSION" = "" ]
          then
            logwarn "CONNECTOR_TAG (--connector-tag option) was not set for element $i, setting it to latest"
            CONNECTOR_VERSION="latest"
          fi
          export CP_CONNECT_TAG="$TAG"

          if [ "$first_loop" = true ]
          then
            if [[ "$OSTYPE" == "darwin"* ]]
            then
              rm -rf ${DIR_UTILS}/../confluent-hub
            else
              log "Using sudo to remove ${DIR_UTILS}/../confluent-hub"
              sudo rm -rf ${DIR_UTILS}/../confluent-hub
            fi
            mkdir -p ${DIR_UTILS}/../confluent-hub
          fi
          log "🎱 Installing connector $owner/$name:$CONNECTOR_VERSION"
          install_command="docker run -u0 -i --rm -v ${DIR_UTILS}/../confluent-hub:/usr/share/confluent-hub-components ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} bash -c \"confluent-hub install --no-prompt $owner/$name:$CONNECTOR_VERSION && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components\""
          if ! install_connector_with_retry "$install_command"
          then
              logerror "❌ failed to install connector $owner/$name:$CONNECTOR_VERSION"
              tail -500 /tmp/result.log
              exit 1
          else
            grep "Download" /tmp/result.log
          fi

          #   log "🤎 Listing jar files"
          #   cd ${DIR_UTILS}/../confluent-hub/$owner-$name/lib > /dev/null 2>&1
          #   ls -1 | sort
          #   cd - > /dev/null 2>&1

          if [ "$first_loop" = true ]
          then
            first_loop=false
            ###
            #  CONNECTOR_JAR is set (and also CONNECTOR_TAG)
            ###
            if [ ! -z "$CONNECTOR_JAR" ]
            then
              if [ ! -f "$CONNECTOR_JAR" ]
              then
                logerror "☕ jar file specified by CONNECTOR_JAR (--connector-jar option) $CONNECTOR_JAR does not exist!"
                exit 1
              fi
              if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
              then
                log "🎯☕ CONNECTOR_JAR (--connector-jar option) is set with $CONNECTOR_JAR"
              fi
              connector_jar_name=$(basename ${CONNECTOR_JAR})
              current_jar_path="${DIR_UTILS}/../confluent-hub/$connector_path/lib/$name-$CONNECTOR_TAG.jar"
              set +e
              ls $current_jar_path
              if [ $? -ne 0 ]
              then
                logwarn "$connector_path/lib/$name-$CONNECTOR_TAG.jar does not exist, the jar name to replace could not be found automatically"
                array=($(ls ${DIR_UTILS}/../confluent-hub/$connector_path/lib | grep $CONNECTOR_TAG))
                choosejar "${array[@]}"
                current_jar_path="${DIR_UTILS}/../confluent-hub/$connector_path/lib/$jar"
              fi
              set -e
              log "🔮 Replacing $name-$CONNECTOR_TAG.jar by $connector_jar_name"
              cp $CONNECTOR_JAR $current_jar_path
            fi
          fi
          ((i=i+1))
        done
      fi
    else
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ] && [ "$0" != "/tmp/playground-command" ] && [ "$0" != "/tmp/playground-command-debugging" ] && [ "$0" != "/tmp/playground-command-zazkia" ]
      then
        logerror "📁 Could not determine docker-compose override file from $PWD/$0 !"
        logerror "👉 Please check you're running a connector example !"
        logerror "🎓 Check the related documentation https://kafka-docker-playground.io/#/how-it-works?id=🐳-docker-override"
        exit 1
      else
        if [ -z "$CP_CONNECT_TAG" ]
        then
          export CP_CONNECT_TAG="$TAG"
        fi
      fi
    fi
  fi
else
  ###
  #  CONNECTOR_TAG is not set
  ###
  if [[ $0 == *"environment"* ]]
  then
    if [ -z "$CP_CONNECT_TAG" ]
    then
      export CP_CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"stop.sh"* ]]
  then
    if [ -z "$CP_CONNECT_TAG" ]
    then
      export CP_CONNECT_TAG="$TAG"
    fi
    CONNECTOR_TAG=$version
    :
  elif [[ $0 == *"run-tests"* ]]
  then
    :
  else
    docker_compose_file=""
    if [ ! -z "$DOCKER_COMPOSE_FILE_UPDATE_VERSION" ]
    then
      docker_compose_file=$DOCKER_COMPOSE_FILE_UPDATE_VERSION
    elif [ -f "$PWD/$0" ]
    then
      docker_compose_file=$(grep "start-environment" "$PWD/$0" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
    fi
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
      if [ "$connector_paths" == "" ]
      then
        # not a connector test
        if [ -z "$CP_CONNECT_TAG" ]
        then
          export CP_CONNECT_TAG="$TAG"
        fi
      else
        ###
        #  Loop on all connectors in CONNECT_PLUGIN_PATH and install latest version from Confluent Hub (except for JDBC and replicator)
        ###
        first_loop=true
        if [[ "$OSTYPE" == "darwin"* ]]
        then
          rm -rf ${DIR_UTILS}/../confluent-hub
        else
          log "Using sudo to remove ${DIR_UTILS}/../confluent-hub"
          sudo rm -rf ${DIR_UTILS}/../confluent-hub
        fi
        mkdir -p ${DIR_UTILS}/../confluent-hub

        for connector_path in ${connector_paths//,/ }
        do
          connector_path=$(echo "$connector_path" | cut -d "/" -f 5)
          owner=$(echo "$connector_path" | cut -d "-" -f 1)
          name=$(echo "$connector_path" | cut -d "-" -f 2-)

          if [ "$name" == "" ]
          then
            # can happen for filestream
            if [ -z "$CP_CONNECT_TAG" ]
            then
              export CP_CONNECT_TAG="$TAG"
            fi
          else
            if [ -z "$CP_CONNECT_TAG" ]
            then
              export CP_CONNECT_TAG="$TAG"
            fi

            ###
            #  CONNECTOR_ZIP is set
            ###
            if [ ! -z "$CONNECTOR_ZIP" ] && [ "$first_loop" = true ]
            then
              if [ ! -f "$CONNECTOR_ZIP" ]
              then
                logerror "CONNECTOR_ZIP $CONNECTOR_ZIP does not exist!"
                exit 1
              fi
              log "🎯🤐 CONNECTOR_ZIP (--connector-zip option) is set with $CONNECTOR_ZIP"
              connector_zip_name=$(basename ${CONNECTOR_ZIP})
              cp $CONNECTOR_ZIP /tmp/

              log "🎱 Installing connector from zip $connector_zip_name"
              install_command="docker run -u0 -i --rm -v ${DIR_UTILS}/../confluent-hub:/usr/share/confluent-hub-components -v /tmp:/tmp ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} bash -c \"confluent-hub install --no-prompt /tmp/${connector_zip_name} && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components\""
              if ! install_connector_with_retry "$install_command"
              then
                  logerror "❌ failed to install connector from zip $connector_zip_name"
                  tail -500 /tmp/result.log
                  exit 1
              else
                grep "Installing" /tmp/result.log
              fi
              first_loop=false
              continue
            fi

            version_to_get_from_hub="latest"
            if [ "$name" = "kafka-connect-replicator" ]
            then
              if [ -z "$REPLICATOR_TAG" ]
              then
                version_to_get_from_hub="$TAG"
              else
                version_to_get_from_hub="$REPLICATOR_TAG"
                log "🌍 REPLICATOR_TAG is set with $REPLICATOR_TAG"
              fi
            fi
            if [ "$name" = "kafka-connect-jdbc" ]
            then
              if ! version_gt $TAG_BASE "5.9.0"; then
                # for version less than 6.0.0, use JDBC with same version
                # see https://github.com/vdesabou/kafka-docker-playground/issues/221
                version_to_get_from_hub="$TAG_BASE"
              fi

              if [ "$TAG_BASE" = "5.0.2" ] || [ "$TAG_BASE" = "5.0.3" ]
              then
                version_to_get_from_hub="5.0.1"
              fi
            fi

            log "🎱 Installing connector $owner/$name:$version_to_get_from_hub"
            install_command="docker run -u0 -i --rm -v ${DIR_UTILS}/../confluent-hub:/usr/share/confluent-hub-components ${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG} bash -c \"confluent-hub install --no-prompt $owner/$name:$version_to_get_from_hub && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components\""
            if ! install_connector_with_retry "$install_command"
            then
                logerror "❌ failed to install connector $owner/$name:$version_to_get_from_hub"
                tail -500 /tmp/result.log
                exit 1
            else
              grep "Download" /tmp/result.log
            fi
            # log "🤎 Listing jar files"
            # cd ${DIR_UTILS}/../confluent-hub/$owner-$name/lib > /dev/null 2>&1
            # ls -1 | sort
            # cd - > /dev/null 2>&1

            # For large connectors (many bundled jars), the install container can exit 0
            # before the bind-mounted files are actually visible on the host. Wait for
            # manifest.json to appear before reading it.
            manifest_wait_path="${DIR_UTILS}/../confluent-hub/${connector_path}/manifest.json"
            manifest_wait_attempts=0
            while [ ! -f "$manifest_wait_path" ] && [ "$manifest_wait_attempts" -lt 30 ]
            do
              sleep 2
              manifest_wait_attempts=$((manifest_wait_attempts+1))
            done
            if [ ! -f "$manifest_wait_path" ]
            then
              logerror "❌ $manifest_wait_path did not appear within 60s after confluent-hub install reported success"
              exit 1
            fi

            version=$(cat ${DIR_UTILS}/../confluent-hub/${connector_path}/manifest.json | jq -r '.version')
            release_date=$(cat ${DIR_UTILS}/../confluent-hub/${connector_path}/manifest.json | jq -r '.release_date')
            documentation_url=$(cat ${DIR_UTILS}/../confluent-hub/${connector_path}/manifest.json | jq -r '.documentation_url')

            ###
            #  CONNECTOR_JAR is set
            ###
            if [ ! -z "$CONNECTOR_JAR" ] && [ "$first_loop" = true ]
            then
              if [ ! -f "$CONNECTOR_JAR" ]
              then
                logerror "☕ CONNECTOR_JAR $CONNECTOR_JAR does not exist!"
                exit 1
              fi
              log "🎯☕ CONNECTOR_JAR (--connector-jar option) is set with $CONNECTOR_JAR"
              connector_jar_name=$(basename ${CONNECTOR_JAR})
              current_jar_path="${DIR_UTILS}/../confluent-hub/$connector_path/lib/$name-$version.jar"
              set +e
              ls $current_jar_path
              if [ $? -ne 0 ]
              then
                logwarn "☕ $connector_path/lib/$name-$version.jar does not exist, the jar name to replace could not be found automatically"
                array=($(ls ${DIR_UTILS}/../confluent-hub/$connector_path/lib | grep $version))
                choosejar "${array[@]}"
                current_jar_path="${DIR_UTILS}/../confluent-hub/$connector_path/lib/$jar"
              fi
              set -e
              log "🔮 Replacing $name-$version.jar by $connector_jar_name"
              cp $CONNECTOR_JAR $current_jar_path
            ###
            #  Neither CONNECTOR_ZIP or CONNECTOR_JAR are set
            ###
            else
              if [ -z "$CP_CONNECT_TAG" ]
              then
                export CP_CONNECT_TAG="$TAG"
              fi
              if [ "$first_loop" = true ]
              then
                log "💫 Using connector:"
                log "    🔗 Plugin: $owner/$name:$version"
                log "    📅 Release date: $release_date"
                log "    🌐 Documentation: $documentation_url"

                # echo "💫 🔗 $owner/$name:$version 📅 $release_date 🌐 $documentation_url" > /tmp/connector_info
                log "🎓 To specify different version, check the documentation https://kafka-docker-playground.io/#/how-to-use?id=🔗-for-connectors"
                CONNECTOR_TAG=$version
              fi
            fi
            first_loop=false
          fi
        done
      fi
    else
      if [ -z "$CP_CONNECT_TAG" ]
      then
        export CP_CONNECT_TAG="$TAG"
      fi
    fi
  fi
  if [ -z "$CP_CONNECT_TAG" ]
  then
    export CP_CONNECT_TAG="$TAG"
  fi
fi

determine_kraft_mode
get_ccs_or_ce_specifics