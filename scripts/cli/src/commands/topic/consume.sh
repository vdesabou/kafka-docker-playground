topic="${args[--topic]}"
verbose="${args[--verbose]}"
max_messages="${args[--max-messages]}"
grep_string="${args[--grep]}"
min_expected_messages="${args[--min-expected-messages]}"
timeout="${args[--timeout]}"
tail="${args[--tail]}"
timestamp_field="${args[--plot-latencies-timestamp-field]}"
key_subject="${args[--key-subject]}"
value_subject="${args[--value-subject]}"
max_characters="${args[--max-characters]}"
open="${args[--open]}"
isolation_level="${args[--isolation-level]}"

# Optimized helpers (reduce repeated external calls and parsing) with caching
declare -A SUBJECT_CACHE
get_subject_info() {
  local subject="$1"
  if [ -n "${SUBJECT_CACHE[$subject]}" ]; then
    echo "${SUBJECT_CACHE[$subject]}"; return 0
  fi
  local json version schema_type out
  json=$(curl $sr_security -s "${sr_url}/subjects/${subject}/versions/latest" 2>/dev/null) || { SUBJECT_CACHE[$subject]=""; echo ""; return 0; }
  version=$(jq -r .version <<< "$json" 2>/dev/null)
  [ "$version" = "null" ] && { SUBJECT_CACHE[$subject]=""; echo ""; return 0; }
  schema_type=$(jq -r '.schemaType // ""' <<< "$json" 2>/dev/null)
  case "$schema_type" in
    JSON) out="json-schema" ;;
    PROTOBUF) out="protobuf" ;;
    AVRO|""|null) out="avro" ;;
    *) out="" ;;
  esac
  SUBJECT_CACHE[$subject]="$out"
  echo "$out"
}

if [[ -n "$key_subject" ]]
then
  original_key_subject=$key_subject
fi

if [[ -n "$value_subject" ]]
then
  original_value_subject=$value_subject
fi

get_environment_used
get_sr_url_and_security

get_connect_image
if version_gt $CP_CONNECT_TAG "7.9.99"
then
    tool_log4j_jvm_arg="-Dlog4j2.configurationFile=file:/etc/kafka/tools-log4j2.yaml"
else
    tool_log4j_jvm_arg="-Dlog4j.configuration=file:/etc/kafka/tools-log4j.properties"
fi

# JVM options of the console consumer, passed in the *_LOG4J_OPTS variables as KAFKA_OPTS and SCHEMA_REGISTRY_OPTS
# can be set by the container (2way-ssl). The JDK 25 of CP 8.3+ warns when a library uses sun.misc.Unsafe or loads
# a native library: allow both, JDK 21 and older refuse to start with these options
tool_jvm_args="$tool_log4j_jvm_arg"
if version_gt $CP_CONNECT_TAG "8.2.99"
then
    tool_jvm_args="$tool_jvm_args --sun-misc-unsafe-memory-access=allow --enable-native-access=ALL-UNNAMED"
fi
tool_env=(env "KAFKA_LOG4J_OPTS=$tool_jvm_args" "SCHEMA_REGISTRY_LOG4J_OPTS=$tool_jvm_args")

if version_gt $CP_CONNECT_TAG "8.1.99"
then
    property_name="--formatter-property"
    consumer_property_name="--command-property"
    consumer_config_name="--command-config"
else
    property_name="--property"
    consumer_property_name="--consumer-property"
    consumer_config_name="--consumer.config"
fi

sr_url_cli="http://schema-registry:8081"
security=""
if [[ "$environment" == cfk* ]]
then
  bootstrap_server="kafka:9071"
  container="connect-0"
  sr_url_cli="http://schemaregistry:8081"
  if [[ "$environment" == "cfk-rbac" ]]
  then
    security="$property_name basic.auth.credentials.source=USER_INFO $property_name schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli $consumer_config_name $cfk_rbac_client_properties"
  fi
elif [[ "$environment" == "kerberos" ]] || [[ "$environment" == "ssl_kerberos" ]]
then
  get_broker_container
  # the GSSAPI client builds the broker principal from the bootstrap host: a short
  # name only becomes the FQDN through Docker's reverse DNS, not podman's
  bootstrap_server="${broker_container}.kerberos-demo.local:9092"
  get_connect_container
  container=$connect_container
    container="client"
    security="$consumer_config_name /etc/kafka/consumer.properties"

    docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
elif [[ "$environment" == *"ssl"* ]]
then
  get_broker_container
  bootstrap_server="$broker_container:9092"
  get_connect_container
  container=$connect_container
    sr_url_cli="https://schema-registry:8081"
    security="$property_name schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks $property_name schema.registry.ssl.truststore.password=confluent $property_name schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks $property_name schema.registry.ssl.keystore.password=confluent $consumer_config_name /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "rbac-sasl-plain" ]]
then
  get_broker_container
  bootstrap_server="$broker_container:9092"
  get_connect_container
  container=$connect_container
    security="$property_name basic.auth.credentials.source=USER_INFO $property_name schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli $consumer_config_name /etc/kafka/secrets/client_without_interceptors.config"
elif [[ "$environment" == "ldap-authorizer-sasl-plain" ]]
then
  get_broker_container
  bootstrap_server="$broker_container:9092"
  get_connect_container
  container=$connect_container
    # the ACLs only allow this group: never commit its offsets, --from-beginning would be ignored on the next consume
    security="--group test-consumer-group $consumer_property_name enable.auto.commit=false $consumer_config_name /service/kafka/users/client.properties"
elif [[ "$environment" == "sasl-plain" ]] || [[ "$environment" == "sasl-scram" ]] || [[ "$environment" == "ldap-sasl-plain" ]]
then
  get_broker_container
  bootstrap_server="$broker_container:9092"
  get_connect_container
  container=$connect_container
    security="$consumer_config_name /tmp/client.properties" 
elif [[ "$environment" == "ccloud" ]]
then
  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

  if [ -f $DELTA_CONFIGS_ENV ]
  then
      source $DELTA_CONFIGS_ENV
  else
      logerror "❌ $DELTA_CONFIGS_ENV has not been generated"
      exit 1
  fi
  if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
  then
      logerror "❌ $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
      exit 1
  fi
else
  get_broker_container
  bootstrap_server="$broker_container:9092"
  get_connect_container
  container=$connect_container
fi

get_topic_message_count() {
  local topic_name="$1"
  playground topic get-number-records -t "$topic_name" --isolation-level "$isolation_level" | tail -1
}

TOPIC_NOT_FOUND_RETRY_SECONDS=60

get_topic_message_count_with_retry() {
  local topic_name="$1"
  local retry_seconds="$2"
  local start_time=""
  local current_time=""
  local elapsed_time=""
  local nb_messages=""

  if [[ -z "$retry_seconds" ]]
  then
    retry_seconds=0
  fi

  start_time=$(date +%s)
  while true
  do
    nb_messages=$(get_topic_message_count "$topic_name")

    if [[ $nb_messages =~ ^[0-9]+$ ]]
    then
      echo "$nb_messages"
      return 0
    fi

    if [[ "$nb_messages" == *"does not exist"* ]]
    then
      current_time=$(date +%s)
      elapsed_time=$((current_time - start_time))
      if [ $elapsed_time -lt $retry_seconds ]
      then
        logwarn "❌ topic $topic_name does not exist, retrying in 1 second (elapsed time: $elapsed_time seconds), waiting max for $retry_seconds seconds" >&2
        sleep 1
        continue
      fi
    fi

    echo "$nb_messages"
    return 0
  done
}

# separates the fields printed by the console consumer: the ascii unit separator never shows up in the data,
# unlike "|" which can be part of a key, a value or a header. Records are displayed with "|"
record_separator=$'\x1f'

# the consumer stops when no record arrives during this time, instead of waiting for a number of records that
# may never come (transaction markers and compacted records use offsets, but are not consumed)
if [[ "$environment" == "ccloud" ]]
then
  idle_timeout_ms=30000
else
  idle_timeout_ms=10000
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
  trap 'rm -rf $tmp_dir' EXIT
else
  log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# formats the records printed by the console consumer, in a single process (a bash loop forked date and awk for
# each record): readable timestamps, labels, base64 decoding, --grep, truncation, latency csv.
# Counts are written to $tmp_dir/consume_counts: records consumed, records matching --grep, records displayed
function format_records() {
  HAS_KEY_SCHEMA_ID="$has_key_schema_id" HAS_VALUE_SCHEMA_ID="$has_value_schema_id" MAX_CHARACTERS="$max_characters" \
  DISPLAY_LIMIT="$display_limit" GREP_STRING="$grep_string" TIMESTAMP_FIELD="$timestamp_field" LATENCY_CSV="$latency_csv" \
  COUNT_FILE="$tmp_dir/consume_counts" PG_LOG_LEVEL="$PG_LOG_LEVEL" perl -MPOSIX=strftime -MMIME::Base64=decode_base64 -MJSON::PP -e '
    use strict;
    use warnings;
    $| = 1;
    my $separator = "\x1f";
    my $has_key_schema_id = $ENV{HAS_KEY_SCHEMA_ID};
    my $has_value_schema_id = $ENV{HAS_VALUE_SCHEMA_ID};
    my $max_characters = $ENV{MAX_CHARACTERS};
    my $display_limit = $ENV{DISPLAY_LIMIT};
    my $grep_string = $ENV{GREP_STRING} // "";
    my $timestamp_field = $ENV{TIMESTAMP_FIELD} // "";
    my ($nb_records, $nb_matched, $nb_displayed) = (0, 0, 0);
    my $decode;
    my $latency_fh;
    if ($timestamp_field ne "") {
      open($latency_fh, ">>", $ENV{LATENCY_CSV}) or die "cannot write $ENV{LATENCY_CSV}: $!";
    }

    sub save_counts {
      if (open(my $fh, ">", $ENV{COUNT_FILE})) { print $fh "$nb_records $nb_matched $nb_displayed\n"; close($fh); }
    }
    $SIG{INT} = $SIG{TERM} = $SIG{PIPE} = sub { save_counts(); exit 0; };

    # payload of a JsonConverter / ByteArrayConverter record, base64 encoded: decoded when it is printable utf-8
    sub decode_payload {
      my $payload = shift;
      $payload =~ s/"//g;
      return undef unless length($payload) > 0 && length($payload) % 4 == 0 && $payload =~ m{^[A-Za-z0-9+/]+={0,2}$};
      my $decoded = decode_base64($payload);
      $decoded =~ tr/\0//d;
      my $check = $decoded;
      return undef unless length($decoded) > 0 && utf8::decode($check) && $check !~ /[\x01-\x08\x0b\x0c\x0e-\x1f]/;
      return $decoded;
    }

    sub display {
      my ($line, $payload_length) = @_;
      if ($max_characters > 0 && $payload_length >= $max_characters) {
        $line = substr($line, 0, $max_characters) . "...<truncated, only showing first $max_characters characters, out of " . length($line) . ">...";
      }
      print "$line\n";
    }

    while (my $line = <STDIN>) {
      chomp $line;
      if ($has_value_schema_id) {
        # a record skipped with --skip-message-on-error leaves its first fields, without new line, before the next
        # record (or at the end of the output): drop them, the error is counted from stderr
        my $record_start = qr/\w+:-?\d+\x1fPartition:\d+\x1fOffset:\d+\x1f/;
        1 while $line =~ s/^$record_start.*?\x1f(?=$record_start)//;
        next if $line =~ /^$record_start/ && $line =~ /\x1f$/;
      }
      my @fields = split /\x1f/, $line, -1;
      if (@fields < 6 || $fields[0] !~ /^\w+(:-?\d+)?$/ || $fields[1] !~ /^Partition:/ || $fields[2] !~ /^Offset:/) {
        # anything else on stdout, for example the next lines of a value containing new lines
        next if $grep_string ne "" && index($line, $grep_string) < 0;
        next if $timestamp_field ne "";
        display($line, length($line));
        next;
      }
      $nb_records++;
      my $index = 3;
      my $headers = $fields[$index++];
      my $key = $fields[$index++];
      my $key_schema_id = $has_key_schema_id ? $fields[$index++] : undef;
      my $value_schema_id = ($has_value_schema_id && $#fields >= $index + 1) ? pop(@fields) : undef;
      my $value = join($separator, @fields[$index .. $#fields]);

      my $timestamp = $fields[0];
      my ($timestamp_ms, $readable_date) = (undef, undef);
      if ($fields[0] =~ /^(\w+):(\d+)$/) {
        $timestamp_ms = $2;
        $readable_date = strftime("%Y-%m-%d %H:%M:%S", localtime(int($timestamp_ms / 1000))) . sprintf(".%03d", $timestamp_ms % 1000);
        $timestamp = "$1:$readable_date";
      }

      if (!defined $decode) {
        $decode = (length($value) < 1000 && defined decode_payload($value)) ? 1 : 0;
        if ($decode && ($ENV{PG_LOG_LEVEL} // "") ne "INFO") {
          printf STDERR "\033[0;35m%s ❗ 🤖 Data is base64 encoded, payload will be decoded\033[0m\n", strftime("%H:%M:%S", localtime);
        }
      }
      if ($decode) {
        my $decoded = decode_payload($value);
        $value = $decoded if defined $decoded;
      }

      my @output = ($timestamp, $fields[1], $fields[2], "Headers:$headers", "Key:$key");
      push @output, "KeySchemaId:$key_schema_id" if defined $key_schema_id;
      push @output, "Value:$value";
      push @output, "ValueSchemaId:$value_schema_id" if defined $value_schema_id;
      my $output = join("|", @output);

      if ($grep_string ne "") {
        next if index($output, $grep_string) < 0;
        $nb_matched++;
      }

      if ($timestamp_field ne "") {
        my $json = eval { JSON::PP->new->allow_nonref->decode($value) };
        if (!defined $json || ref($json) ne "HASH") {
          printf STDERR "\033[0;31m%s 🔥 --plot-latencies-timestamp-field is set but value content is not in json representation\033[0m\n", strftime("%H:%M:%S", localtime);
          save_counts();
          exit 3;
        }
        my $source = $json->{$timestamp_field};
        $source = $source->{long} if ref($source) eq "HASH" && exists $source->{long};
        print $latency_fh ($readable_date // ""), ",", ($timestamp_ms // ""), ",", ($source // ""), "\n";
        next;
      }

      if ($display_limit < 0 || $nb_displayed < $display_limit) {
        display($output, length($value));
        $nb_displayed++;
      }
    }
    close($latency_fh) if $latency_fh;
    save_counts();'
}

# filters the stderr of the console consumer: drops the known noise, and replaces the stack trace of every record
# skipped with --skip-message-on-error by a count. Written to $tmp_dir/consume_errors: number of records skipped,
# first error, its root cause
function filter_consumer_stderr() {
  ERRORS_FILE="$tmp_dir/consume_errors" perl -e '
    use strict;
    use warnings;
    $| = 1;
    my ($nb_skipped, $first_error, $root_cause) = (0, "", "");
    my $in_skipped_trace = 0;
    my $in_timeout_trace = 0;
    sub save_errors {
      if (open(my $fh, ">", $ENV{ERRORS_FILE})) { print $fh "$nb_skipped\n$first_error\n$root_cause\n"; close($fh); }
    }
    $SIG{INT} = $SIG{TERM} = $SIG{PIPE} = sub { save_errors(); exit 0; };
    while (my $line = <STDIN>) {
      next if $line =~ /WARNING:|SLF4J|Processed a total of|Unable to find FetchSessionHandler|Set group\.protocol=consumer to try it out/;
      # end of the consumer with --timeout-ms: no record during the idle timeout
      if ($line =~ /Error processing message, terminating consumer process/) { $in_timeout_trace = 1; next; }
      if ($in_timeout_trace && $line =~ /TimeoutException/) { $in_timeout_trace = 0; next; }
      $in_timeout_trace = 0;
      if ($line =~ /Error processing message, skipping this message/) {
        $nb_skipped++;
        $in_skipped_trace = 1;
        next;
      }
      if ($in_skipped_trace) {
        (my $trimmed = $line) =~ s/^\s+|\s+$//g;
        if ($trimmed eq "" || $trimmed =~ /^at / || $trimmed =~ /^\.\.\. \d+ more/) { next; }
        if ($trimmed =~ /^Caused by: (.*)/) { $root_cause = $1 if $nb_skipped == 1; next; }
        if ($trimmed =~ /^[\w.\$]+(Exception|Error)\b/) { $first_error = $trimmed if $nb_skipped == 1; next; }
        $in_skipped_trace = 0;
      }
      print STDERR $line;
    }
    save_errors();'
}

# arguments of the consumer command, with the secrets masked, as a command line to paste
function printable_command() {
  local arg
  local printable=()
  for arg in "$@"
  do
    if [[ "$arg" == sasl.jaas.config=* ]]
    then
      arg=$(echo "$arg" | sed -E 's/(password=")[^"]*"/\1***"/g')
    elif [[ "$arg" == schema.registry.basic.auth.user.info=* ]]
    then
      arg="${arg%%:*}:***"
    fi
    printable+=("$arg")
  done
  printf '%q ' "${printable[@]}"
}

if [[ -n "$timeout" ]] && [ "$timeout" != "60" ]
then
  if [[ ! -n "$min_expected_messages" ]] || [ "$min_expected_messages" == "0" ]
  then
    logerror "❌ --timeout was provided without specifying --min-expected-messages"
    exit 1
  fi
fi

if [[ ! -n "$topic" ]]
then
    if [[ -n "$min_expected_messages" ]] && [ "$min_expected_messages" != "0" ]
    then
      logerror "--min-expected-messages was provided without specifying --topic"
      exit 1
    fi
    if [[ -n "$key_subject" ]]
    then
      logerror "--key-subject was provided without specifying --topic"
      exit 1
    fi
    if [[ -n "$value_subject" ]]
    then
      logerror "--value-subject was provided without specifying --topic"
      exit 1
    fi
    if [[ -n "$tail" ]]
    then
      logerror "--tail was provided without specifying --topic"
      exit 1
    fi
    if [[ -n "$timestamp_field" ]]
    then
      logerror "--plot-latencies-timestamp-field was provided without specifying --topic"
      exit 1
    fi
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ no topic found !"
        exit 1
    fi
fi

if [[ -n "$timestamp_field" ]]
then
  rm -rf /tmp/latency
  mkdir -p /tmp/latency
  latency_csv="/tmp/latency/latency.csv"
  latency_png="/tmp/latency/latency.png"
fi

items=($topic)
for topic in ${items[@]}
do
  key_subject=""
  value_subject=""
  if [ ! -n "$tail" ]
  then
    if [[ -n "$min_expected_messages" ]] && [ "$min_expected_messages" != "0" ]
    then
      start_time=$(date +%s)
      topic_missing_start_time=""

      while true; do
        nb_messages=$(playground topic get-number-records -t $topic --isolation-level "$isolation_level" | tail -1)

        if [[ ! $nb_messages =~ ^[0-9]+$ ]]
        then
          if [[ "$nb_messages" == *"does not exist"* ]]
          then
            if [[ -z "$topic_missing_start_time" ]]
            then
              topic_missing_start_time=$(date +%s)
            fi

            current_time=$(date +%s)
            topic_missing_elapsed=$((current_time - topic_missing_start_time))
            if [ $topic_missing_elapsed -lt $TOPIC_NOT_FOUND_RETRY_SECONDS ]
            then
              logwarn "❌ topic $topic does not exist, retrying in 1 second (elapsed time: $topic_missing_elapsed seconds), waiting max for $TOPIC_NOT_FOUND_RETRY_SECONDS seconds" >&2
              sleep 1
              continue
            fi

            logwarn "❌ topic $topic does not exist !"
          else
            logwarn "❌ problem while getting number of messages: $nb_messages"
          fi
          exit 1
        fi

        if [ $nb_messages -ge $min_expected_messages ]
        then
          break
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $timeout ]
        then
          logerror "❌ overall timeout of $timeout seconds exceeded. --min-expected-messages is set with $min_expected_messages but topic $topic contains $nb_messages messages"
          exit 1
        fi

        sleep 1
      done
    else
      nb_messages=$(get_topic_message_count_with_retry "$topic" "$TOPIC_NOT_FOUND_RETRY_SECONDS")

      if [[ ! $nb_messages =~ ^[0-9]+$ ]]
      then
        echo $nb_messages | grep "does not exist" > /dev/null 2>&1
        if [ $? == 0 ]
        then
          logwarn "❌ topic $topic does not exist !"
        else
          logwarn "❌ problem while getting number of messages: $nb_messages"
        fi
        # go on with the next topic when all topics are consumed
        continue
      fi
    fi
  fi

  if [[ -n "$open" ]]
  then
    filename="/tmp/dump-${topic}-$(date '+%Y-%m-%d-%H-%M-%S').log"

    log "📄 dumping topic content to $filename"
    # a full dump: no truncation, no log lines, same subjects and isolation level
    dump_args=(--topic "$topic" --max-messages -1 --max-characters 0 --isolation-level "$isolation_level")
    if [[ -n "$original_key_subject" ]]
    then
      dump_args+=(--key-subject "$original_key_subject")
    fi
    if [[ -n "$original_value_subject" ]]
    then
      dump_args+=(--value-subject "$original_value_subject")
    fi
    if playground --output-level ERROR topic consume "${dump_args[@]}" > "$filename"
    then
      playground open --file "${filename}"
    else
      logerror "❌ failed to dump topic $topic"
    fi
    continue
  fi

  if [ -n "$tail" ]
  then
    log "✨ Tailing content of topic $topic"
  elif [[ -n "$max_messages" ]] && [ $max_messages -eq -1 ] && [[ ! -n "$timestamp_field" ]]
  then
    log "✨ --max-messages is set to -1, display full content of topic $topic, it contains $nb_messages messages"
  elif [[ -n "$max_messages" ]] && [ $nb_messages -gt $max_messages ] && [[ ! -n "$timestamp_field" ]]
  then
    log "✨ Display content of topic $topic, it contains $nb_messages messages, but displaying only --max-messages=$max_messages"
  else
    log "✨ Display content of topic $topic, it contains $nb_messages messages"
  fi
  if [ "$isolation_level" == "read_committed" ]
  then
    log "🔒 --isolation-level is set to $isolation_level, only committed messages will be displayed"
  fi

  if [[ -n "$grep_string" ]]
  then
    logwarn "--grep is set so only matched results will be displayed !"
  fi

  if [[ -n "$timestamp_field" ]]
  then
    log "📈 plotting results.."
  fi
  if [[ -n "$original_key_subject" ]]; then
    log "📛 key subject is set with $original_key_subject"
    key_subject=$original_key_subject
  else
    key_subject="${topic}-key"
  fi
  key_type=$(get_subject_info "$key_subject")

  if [ "$key_type" != "" ]
  then
    log "🔮🔰 topic is using $key_type for key"
    playground schema get --subject ${key_subject}
  else
    log "🔮🙅 topic is not using any schema for key"
  fi

  if [[ -n "$original_value_subject" ]]
  then
    log "📛 value subject is set with $original_value_subject"
    value_subject=$original_value_subject
  else
    value_subject="${topic}-value"
  fi

  value_type=$(get_subject_info "$value_subject")

  if [ "$value_type" != "" ]
  then
    log "🔮🔰 topic is using $value_type for value"
    playground schema get --subject ${value_subject}
  else
    log "🔮🙅 topic is not using any schema for value"
  fi

  has_key_schema_id=0
  has_value_schema_id=0
  case "${value_type}" in
    avro|protobuf|json-schema)
      has_value_schema_id=1
      case "${key_type}" in
        avro|protobuf|json-schema)
          has_key_schema_id=1
        ;;
      esac
    ;;
  esac

  # number of records to read, and to display
  display_limit=-1
  if [ ! -n "$tail" ]
  then
    if [[ -n "$timestamp_field" ]] || [ $max_messages -eq -1 ]
    then
      nb_records_to_consume=$nb_messages
    else
      nb_records_to_consume=$max_messages
      display_limit=$max_messages
    fi
    if [[ -n "$min_expected_messages" ]] && [ $min_expected_messages -gt $nb_records_to_consume ]
    then
      nb_records_to_consume=$min_expected_messages
    fi
    if [ $nb_records_to_consume -gt $nb_messages ]
    then
      nb_records_to_consume=$nb_messages
    fi

    if [ $nb_records_to_consume -eq 0 ]
    then
      log "✨ topic $topic is empty"
      if [[ -n "$grep_string" ]]
      then
        logerror "❌ could not find $grep_string in topic $topic"
        exit 1
      fi
      continue
    fi
  fi

  # console consumer command, built once
  consumer_cmd=()
  if [[ "$environment" == "ccloud" ]]
  then
    get_connect_image
    if [ $has_value_schema_id -eq 1 ]
    then
      consumer_cmd=(docker run -i --rm "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" "${tool_env[@]}" "kafka-$value_type-console-consumer" --bootstrap-server "$BOOTSTRAP_SERVERS" "$consumer_property_name" ssl.endpoint.identification.algorithm=https "$consumer_property_name" sasl.mechanism=PLAIN "$consumer_property_name" security.protocol=SASL_SSL "$consumer_property_name" "sasl.jaas.config=$SASL_JAAS_CONFIG" "$property_name" basic.auth.credentials.source=USER_INFO "$property_name" "schema.registry.basic.auth.user.info=$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" "$property_name" "schema.registry.url=$SCHEMA_REGISTRY_URL")
    else
      consumer_cmd=(docker run -i --rm -v "$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta:/tmp/configuration/ccloud.properties" "${CP_CONNECT_IMAGE}:${CP_CONNECT_TAG}" "${tool_env[@]}" kafka-console-consumer --bootstrap-server "$BOOTSTRAP_SERVERS" "$consumer_config_name" /tmp/configuration/ccloud.properties)
    fi
  else
    if [[ "$environment" == cfk* ]]
    then
      consumer_cmd=(kubectl -n confluent exec "$container" --)
    else
      consumer_cmd=(docker exec -e KAFKA_DEBUG= "$container")
    fi
    if [ $has_value_schema_id -eq 1 ]
    then
      consumer_cmd+=("${tool_env[@]}" "kafka-$value_type-console-consumer" --bootstrap-server "$bootstrap_server" "$property_name" "schema.registry.url=$sr_url_cli")
    else
      consumer_cmd+=("${tool_env[@]}" kafka-console-consumer --bootstrap-server "$bootstrap_server")
    fi
  fi

  consumer_cmd+=(--topic "$topic")

  # $security only holds options without spaces
  read -r -a security_args <<< "$security"
  consumer_cmd+=("${security_args[@]}")

  consumer_cmd+=("$property_name" print.timestamp=true "$property_name" print.partition=true "$property_name" print.offset=true "$property_name" print.headers=true "$property_name" headers.separator=, "$property_name" headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer "$property_name" print.key=true "$property_name" "key.separator=$record_separator")
  if [ $has_value_schema_id -eq 1 ]
  then
    consumer_cmd+=("$property_name" print.schema.ids=true "$property_name" "schema.id.separator=$record_separator" --skip-message-on-error)
    if [ $has_key_schema_id -eq 0 ]
    then
      consumer_cmd+=("$property_name" key.deserializer=org.apache.kafka.common.serialization.StringDeserializer)
    fi
  fi
  consumer_cmd+=(--isolation-level "$isolation_level")
  if [ ! -n "$tail" ]
  then
    consumer_cmd+=(--from-beginning --max-messages "$nb_records_to_consume" --timeout-ms "$idle_timeout_ms")
  fi

  if [[ -n "$verbose" ]]
  then
    log "🐞 CLI command used to consume data"
    printable_command "${consumer_cmd[@]}"
    echo
  fi

  rm -f "$tmp_dir/consume_counts" "$tmp_dir/consume_errors" "$tmp_dir/consumer_exit_code"
  # stdout of the consumer to format_records, its stderr to filter_consumer_stderr
  { { "${consumer_cmd[@]}" 2>&1 1>&3 3>&-; echo $? > "$tmp_dir/consumer_exit_code"; } | filter_consumer_stderr >&2 3>&-; } 3>&1 | format_records
  format_exit_code=${PIPESTATUS[1]}

  consumer_exit_code=$(cat "$tmp_dir/consumer_exit_code" 2> /dev/null)
  read -r nb_consumed nb_matched nb_displayed < "$tmp_dir/consume_counts" 2> /dev/null
  nb_consumed=${nb_consumed:-0}
  nb_matched=${nb_matched:-0}
  nb_displayed=${nb_displayed:-0}
  nb_skipped=0
  first_error=""
  root_cause=""
  if [ -f "$tmp_dir/consume_errors" ]
  then
    { read -r nb_skipped; read -r first_error; read -r root_cause; } < "$tmp_dir/consume_errors"
  fi

  if [ "$format_exit_code" == "3" ]
  then
    exit 1
  fi

  if [ $nb_skipped -gt 0 ]
  then
    logwarn "⚠️ $nb_skipped record(s) of topic $topic could not be deserialized and were skipped, first error: $first_error${root_cause:+ (caused by: $root_cause)}"
  fi

  if [ ! -n "$tail" ] && [ "$consumer_exit_code" != "0" ]
  then
    if [[ -n "$min_expected_messages" && "$min_expected_messages" != "0" ]] || [[ -n "$grep_string" ]]
    then
      logerror "❌ the consumer of topic $topic failed with exit code $consumer_exit_code"
      exit 1
    fi
    logwarn "❌ the consumer of topic $topic failed with exit code $consumer_exit_code"
  fi

  if [ $display_limit -ge 0 ] && [ $nb_displayed -lt $nb_consumed ] && [[ ! -n "$grep_string" ]]
  then
    log "✨ $nb_consumed records consumed, only the first $nb_displayed are displayed (--max-messages=$max_messages)"
  fi

  if [[ -n "$min_expected_messages" ]] && [ "$min_expected_messages" != "0" ]
  then
    if [ $nb_consumed -lt $min_expected_messages ]
    then
      skipped_msg=""
      if [ $nb_skipped -gt 0 ]
      then
        skipped_msg=", $nb_skipped could not be deserialized"
      fi
      logerror "❌ --min-expected-messages is set with $min_expected_messages but only $nb_consumed records could be consumed from topic $topic ($nb_messages offsets$skipped_msg)"
      exit 1
    fi
  fi

  if [[ -n "$grep_string" ]]
  then
    if [ $nb_matched -eq 0 ]
    then
      logerror "❌ could not find $grep_string in topic $topic"
      exit 1
    fi
    log "✅ found $grep_string in $nb_matched record(s) of topic $topic"
  fi
done

if [[ -n "$timestamp_field" ]]
then
  log "Plot data using gnuplot, see ${latency_png}"
  docker run --quiet --rm -i -v ${PLAYGROUND_HOST_TMP_DIR}/latency:/work remuslazar/gnuplot -e \
  "
  set grid;
  set datafile separator ',';
  set timefmt \"%Y-%m-%d %H:%M:%S.%s\";
  set format x '%H:%M:%S';
  set term png size 1200,600;
  set output 'latency.png';
  set xdata time;
  set autoscale;
  set xlabel 'Time';
  set ylabel 'Latency in ms';
  plot 'latency.csv' using 1:(\$2-\$3) with points;"

  # open $latency_csv
  if [[ $(type -f open 2>&1) =~ "not found" ]]
  then
    :
  else
    open $latency_png
  fi
fi
