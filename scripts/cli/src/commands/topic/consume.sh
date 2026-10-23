topic="${args[--topic]}"
verbose="${args[--verbose]}"
max_messages="${args[--max-messages]}"
grep_string="${args[--grep]}"
min_expected_messages="${args[--min-expected-messages]}"
timeout="${args[--timeout]}"
tail="${args[--tail]}"
key_subject="${args[--key-subject]}"
value_subject="${args[--value-subject]}"
max_characters="${args[--max-characters]}"
open="${args[--open]}"
isolation_level="${args[--isolation-level]}"
last="${args[--last]}"
from_timestamp="${args[--from-timestamp]}"
partition="${args[--partition]}"
offset="${args[--offset]}"
json="${args[--json]}"
count="${args[--count]}"
no_decode="${args[--no-decode]}"
print_schema="${args[--print-schema]}"

if [[ -n "$json" ]] || [[ -n "$count" ]]
then
  # stdout only gets the records, one json object per line, or the counts: everything else (logs, schemas,
  # errors) goes to stderr
  exec 4>&1 1>&2
fi

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
# separates the headers: "," can be part of a header value (the stack trace of a dead letter queue record). Displayed
# with "," by format_records. The key of a header is followed by ":" (not configurable): split on the first one
headers_separator=$'\x1d'

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
# each record): readable timestamps, labels, base64 decoding, --grep, truncation, --json.
# With $sort_keep (first or last), the records are sorted by timestamp and only the first or last $display_limit
# are displayed (--from-timestamp, --last: one consumer per partition).
# Counts are written to $tmp_dir/consume_counts: records consumed, records matching --grep, records displayed
function format_records() {
  HAS_KEY_SCHEMA_ID="$has_key_schema_id" HAS_VALUE_SCHEMA_ID="$has_value_schema_id" MAX_CHARACTERS="$max_characters" \
  DISPLAY_LIMIT="$display_limit" GREP_STRING="$grep_string" \
  NO_DECODE="$no_decode" OUTPUT_JSON="$json" SORT_KEEP="$sort_keep" TOPIC="$topic" \
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
    my $output_json = ($ENV{OUTPUT_JSON} // "") ne "";
    my $sort_keep = $ENV{SORT_KEEP} // "";
    my ($nb_records, $nb_matched, $nb_displayed) = (0, 0, 0);
    my $decode = ($ENV{NO_DECODE} // "") ne "" ? 0 : undef;
    my $json_encoder = JSON::PP->new->canonical;
    my $json_decoder = JSON::PP->new->allow_nonref;
    my @sorted_records;

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
      if (!$output_json && $max_characters > 0 && $payload_length >= $max_characters) {
        $line = substr($line, 0, $max_characters) . "...<truncated, only showing first $max_characters characters, out of " . length($line) . ">...";
      }
      print "$line\n";
    }

    my $pending = "";
    while (my $line = <STDIN>) {
      chomp $line;
      # a header or a key containing new lines (the stack trace header of a dead letter queue record) splits a record
      # over several lines: join them until the record has all its fields (at least 5 separators)
      if ($pending ne "") {
        $line = "$pending\n$line";
        $pending = "";
      }
      if ($line =~ /^\w+:-?\d+\x1fPartition:\d+\x1fOffset:\d+\x1f/ && $line !~ /\x1f$/ && ($line =~ tr/\x1f//) < 5) {
        $pending = $line;
        next;
      }
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
        if ($output_json) { print STDERR "$line\n"; next; }
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

      # headers are separated by \x1d (see headers.separator): displayed with ",", and the new lines of a header or a key
      # as \n, so that a record stays on one line
      my $headers_display = $headers;
      $headers_display =~ tr/\x1d/,/;
      $headers_display =~ s/\n/\\n/g;
      (my $key_display = $key) =~ s/\n/\\n/g;
      my @output = ($timestamp, $fields[1], $fields[2], "Headers:$headers_display", "Key:$key_display");
      push @output, "KeySchemaId:$key_schema_id" if defined $key_schema_id;
      push @output, "Value:$value";
      push @output, "ValueSchemaId:$value_schema_id" if defined $value_schema_id;
      my $output = join("|", @output);

      if ($grep_string ne "") {
        next if index($output, $grep_string) < 0;
        $nb_matched++;
      }

      if ($output_json) {
        # key and value are embedded as json when they are valid json, as strings otherwise
        my %headers_map;
        if ($headers ne "NO_HEADERS") {
          for my $header (split /\x1d/, $headers) {
            my ($name, $header_value) = split /:/, $header, 2;
            $headers_map{$name} = $header_value;
          }
        }
        my %record = (
          topic => $ENV{TOPIC},
          partition => ($fields[1] =~ /(\d+)/)[0] + 0,
          offset => ($fields[2] =~ /(\d+)/)[0] + 0,
          timestamp_type => ($fields[0] =~ /^(\w+)/)[0],
          timestamp => defined $timestamp_ms ? $timestamp_ms + 0 : undef,
          date => $readable_date,
          headers => \%headers_map,
          key => ($key eq "null" ? undef : (eval { $json_decoder->decode($key) } // $key)),
          value => ($value eq "null" ? undef : (eval { $json_decoder->decode($value) } // $value)),
        );
        $record{key_schema_id} = $key_schema_id + 0 if defined $key_schema_id && $key_schema_id =~ /^\d+$/;
        $record{value_schema_id} = $value_schema_id + 0 if defined $value_schema_id && $value_schema_id =~ /^\d+$/;
        $output = $json_encoder->encode(\%record);
      }

      if ($sort_keep ne "") {
        push @sorted_records, [$timestamp_ms // 0, ($fields[1] =~ /(\d+)/)[0], ($fields[2] =~ /(\d+)/)[0], $output, length($value)];
        next;
      }

      if ($display_limit < 0 || $nb_displayed < $display_limit) {
        display($output, length($value));
        $nb_displayed++;
      }
    }
    # a record that never got all its fields (output interrupted): shown as it is
    if ($pending ne "" && !$output_json) {
      display($pending, length($pending));
    }
    if ($sort_keep ne "") {
      my @records = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @sorted_records;
      if ($display_limit >= 0 && @records > $display_limit) {
        @records = $sort_keep eq "last" ? @records[-$display_limit .. -1] : @records[0 .. $display_limit - 1];
      }
      for my $record (@records) {
        display($record->[3], $record->[4]);
        $nb_displayed++;
      }
    }
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

# runs the console consumer once per element of consumer_runs (its positioning options), returns the last exit
# code that is not 0
function run_consumers() {
  local exit_code=0
  local consumer_run
  local run_args
  for consumer_run in "${consumer_runs[@]}"
  do
    read -r -a run_args <<< "$consumer_run"
    "${consumer_cmd[@]}" "${run_args[@]}" || exit_code=$?
  done
  return $exit_code
}

# --count: the number alone when one topic is consumed, "<topic> <number>" for all topics
function print_count() {
  if [ ${#items[@]} -eq 1 ]
  then
    echo "$1" >&4
  else
    echo "$topic $1" >&4
  fi
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
    log "✨ --topic flag was not provided, applying command to all topics"
    topic=$(playground get-topic-list --skip-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ no topic found !"
        exit 1
    fi
fi

if [[ -n "$last" ]] && [ "$last" -le 0 ]
then
  logerror "❌ --last must be greater than 0"
  exit 1
fi

from_timestamp_ms=""
if [[ -n "$from_timestamp" ]]
then
  # epoch in ms or seconds, a date (local time, or UTC with a trailing Z), or a duration ago (30s, 10m, 2h, 1d)
  # helpers of the cli can leave set -e on: test the parsing in the if
  if ! from_timestamp_ms=$(perl -MTime::Local=timelocal,timegm -e '
    my $value = shift;
    my $now_ms = int(time * 1000);
    if ($value =~ /^\d{12,}$/) { print $value; exit 0; }
    if ($value =~ /^\d{9,11}$/) { print $value * 1000; exit 0; }
    if ($value =~ /^-?(\d+)\s*(s|m|h|d)$/) { my %unit = (s => 1, m => 60, h => 3600, d => 86400); print $now_ms - $1 * $unit{$2} * 1000; exit 0; }
    if ($value =~ /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?)?\s*(Z)?$/) {
      my @time = ($6 // 0, $5 // 0, $4 // 0, $3, $2 - 1, $1);
      my $seconds = defined $8 ? timegm(@time) : timelocal(@time);
      print $seconds * 1000 + (defined $7 ? substr($7 . "00", 0, 3) : 0);
      exit 0;
    }
    exit 1;' "$from_timestamp") || [ "$from_timestamp_ms" == "" ]
  then
    logerror "❌ --from-timestamp $from_timestamp is not valid: use an epoch (ms or s), a date like \"2026-10-22 10:30:00\" (local time, add Z for UTC), or a duration ago like 10m, 2h, 1d"
    exit 1
  fi
  log "⏱️ --from-timestamp $from_timestamp: records from $(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%d %H:%M:%S", localtime(int($ARGV[0] / 1000)))' "$from_timestamp_ms") ($from_timestamp_ms)"
fi

if [[ -n "$offset" ]] && [[ ! "$offset" =~ ^([0-9]+|earliest|latest)$ ]]
then
  logerror "❌ --offset must be a number, earliest or latest"
  exit 1
fi

if [[ -n "$last" ]] || [[ -n "$from_timestamp" ]] || [[ -n "$partition" && ! -n "$tail" ]]
then
  if ! version_gt "$CP_CONNECT_TAG" "6.9.9"
  then
    logerror "❌ --last, --from-timestamp and --partition require CP 7.0 or later (it is $CP_CONNECT_TAG)"
    exit 1
  fi
  get_offsets_class="kafka.tools.GetOffsetShell"
  if version_gt "$CP_CONNECT_TAG" "7.6.9"
  then
    get_offsets_class="org.apache.kafka.tools.GetOffsetShell"
  fi
fi

# "partition offset" lines of the partitions of $topic, for --time $1: -2 earliest, -1 latest, or a timestamp in ms
# (a partition without any record from that timestamp is not listed). In a subshell: run_kafka_admin_tool sets
# $security, $container and $bootstrap_server for the admin tools
function get_partition_offsets() {
  local partition_args=()
  if [[ -n "$partition" ]]
  then
    partition_args=(--partitions "$partition")
  fi
  (verbose=""; run_kafka_admin_tool kafka-run-class $get_offsets_class --topic "$topic" --time "$1" "${partition_args[@]}" 2>/dev/null) | grep -E ':[0-9]+:-?[0-9]+$' | awk -F: '{print $(NF-1), $NF}' | sort -n
}

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
  elif [[ -n "$last" ]] || [[ -n "$from_timestamp" ]] || [[ -n "$count" ]]
  then
    log "✨ topic $topic contains $nb_messages messages"
  elif [[ -n "$max_messages" ]] && [ $max_messages -eq -1 ]
  then
    log "✨ --max-messages is set to -1, display full content of topic $topic, it contains $nb_messages messages"
  elif [[ -n "$max_messages" ]] && [ $nb_messages -gt $max_messages ]
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
    if [[ -n "$print_schema" ]]
    then
      playground schema get --subject ${key_subject}
    fi
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
    if [[ -n "$print_schema" ]]
    then
      playground schema get --subject ${value_subject}
    fi
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

  # number of records to read and to display, and the positioning options of each console consumer to run:
  # one consumer per partition with --last and --from-timestamp, the records are then sorted by timestamp
  display_limit=-1
  sort_keep=""
  consumer_runs=()
  if [ -n "$tail" ]
  then
    if [[ -n "$partition" ]]
    then
      consumer_runs=("--partition $partition")
    else
      consumer_runs=("")
    fi
  else
    if [[ -n "$count" ]]
    then
      display_limit=0
      nb_records_to_consume=$nb_messages
    elif [[ -n "$last" ]]
    then
      display_limit=$last
      nb_records_to_consume=$last
    elif [ $max_messages -eq -1 ]
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

    if [[ -n "$last" ]] || [[ -n "$from_timestamp" ]]
    then
      earliest_offsets=$(get_partition_offsets -2)
      latest_offsets=$(get_partition_offsets -1)
      if [[ -n "$from_timestamp" ]]
      then
        start_offsets=$(get_partition_offsets "$from_timestamp_ms")
        sort_keep="first"
        log "⏱️ Display records of topic $topic from $from_timestamp${partition:+, partition $partition}"
      else
        sort_keep="last"
        log "⏮️ Display the last $last records of topic $topic${partition:+, partition $partition}"
      fi
      nb_records_per_partition_max=$nb_records_to_consume
      nb_records_to_consume=0
      while read -r partition_number latest_offset
      do
        [ -z "$partition_number" ] && continue
        earliest_offset=$(echo "$earliest_offsets" | awk -v p="$partition_number" '$1 == p {print $2}')
        earliest_offset=${earliest_offset:-0}
        if [[ -n "$last" ]]
        then
          start_offset=$((latest_offset - last))
        else
          # no record from that timestamp in the partition: nothing to read
          start_offset=$(echo "$start_offsets" | awk -v p="$partition_number" '$1 == p {print $2}')
          start_offset=${start_offset:-$latest_offset}
        fi
        if [ $start_offset -lt $earliest_offset ]
        then
          start_offset=$earliest_offset
        fi
        nb_records_in_partition=$((latest_offset - start_offset))
        if [ $nb_records_in_partition -gt $nb_records_per_partition_max ]
        then
          nb_records_in_partition=$nb_records_per_partition_max
        fi
        if [ $nb_records_in_partition -le 0 ]
        then
          continue
        fi
        consumer_runs+=("--partition $partition_number --offset $start_offset --max-messages $nb_records_in_partition --timeout-ms $idle_timeout_ms")
        nb_records_to_consume=$((nb_records_to_consume + nb_records_in_partition))
      done <<< "$latest_offsets"
    elif [[ -n "$partition" ]]
    then
      log "🧭 Display records of topic $topic, partition $partition, from offset ${offset:-earliest}"
      # records left in the partition from that offset, so that the consumer does not wait for the idle timeout
      latest_offset=$(get_partition_offsets -1 | awk '{print $2}')
      case "${offset:-earliest}" in
        earliest)
          start_offset=$(get_partition_offsets -2 | awk '{print $2}')
        ;;
        latest)
          start_offset=$latest_offset
        ;;
        *)
          start_offset=$offset
        ;;
      esac
      if [[ ! "$latest_offset" =~ ^[0-9]+$ ]]
      then
        logerror "❌ partition $partition of topic $topic does not exist"
        exit 1
      fi
      nb_records_in_partition=$((latest_offset - ${start_offset:-0}))
      if [ $nb_records_in_partition -lt $nb_records_to_consume ]
      then
        nb_records_to_consume=$nb_records_in_partition
      fi
      if [ $nb_records_to_consume -lt 0 ]
      then
        nb_records_to_consume=0
      fi
      consumer_runs=("--partition $partition --offset ${offset:-earliest} --max-messages $nb_records_to_consume --timeout-ms $idle_timeout_ms")
    else
      consumer_runs=("--from-beginning --max-messages $nb_records_to_consume --timeout-ms $idle_timeout_ms")
    fi

    if [ $nb_records_to_consume -eq 0 ]
    then
      if [[ -n "$last" ]] || [[ -n "$from_timestamp" ]]
      then
        log "✨ no record to display in topic $topic"
      else
        log "✨ topic $topic is empty"
      fi
      if [[ -n "$grep_string" ]]
      then
        logerror "❌ could not find $grep_string in topic $topic"
        exit 1
      fi
      if [[ -n "$min_expected_messages" ]] && [ "$min_expected_messages" != "0" ]
      then
        logerror "❌ --min-expected-messages is set with $min_expected_messages but no record could be consumed from topic $topic"
        exit 1
      fi
      if [[ -n "$count" ]]
      then
        print_count 0
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

  consumer_cmd+=("$property_name" print.timestamp=true "$property_name" print.partition=true "$property_name" print.offset=true "$property_name" print.headers=true "$property_name" "headers.separator=$headers_separator" "$property_name" headers.deserializer=org.apache.kafka.common.serialization.StringDeserializer "$property_name" print.key=true "$property_name" "key.separator=$record_separator")
  if [ $has_value_schema_id -eq 1 ]
  then
    consumer_cmd+=("$property_name" print.schema.ids=true "$property_name" "schema.id.separator=$record_separator" --skip-message-on-error)
    if [ $has_key_schema_id -eq 0 ]
    then
      consumer_cmd+=("$property_name" key.deserializer=org.apache.kafka.common.serialization.StringDeserializer)
    fi
  fi
  consumer_cmd+=(--isolation-level "$isolation_level")

  if [[ -n "$verbose" ]]
  then
    log "🐞 CLI command used to consume data"
    for consumer_run in "${consumer_runs[@]}"
    do
      read -r -a run_args <<< "$consumer_run"
      printable_command "${consumer_cmd[@]}" "${run_args[@]}"
      echo
    done
  fi

  rm -f "$tmp_dir/consume_counts" "$tmp_dir/consume_errors" "$tmp_dir/consumer_exit_code"
  # stdout of the consumer to format_records, its stderr to filter_consumer_stderr
  if [[ -n "$json" ]]
  then
    { { run_consumers 2>&1 1>&3 3>&-; echo $? > "$tmp_dir/consumer_exit_code"; } | filter_consumer_stderr >&2 3>&-; } 3>&1 | format_records >&4
  else
    { { run_consumers 2>&1 1>&3 3>&-; echo $? > "$tmp_dir/consumer_exit_code"; } | filter_consumer_stderr >&2 3>&-; } 3>&1 | format_records
  fi

  consumer_exit_code=$(cat "$tmp_dir/consumer_exit_code" 2> /dev/null)
  nb_consumed=""
  nb_matched=""
  nb_displayed=""
  if [ -s "$tmp_dir/consume_counts" ]
  then
    read -r nb_consumed nb_matched nb_displayed < "$tmp_dir/consume_counts"
  fi
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

  if [ $display_limit -gt 0 ] && [ $nb_displayed -lt $nb_consumed ] && [[ ! -n "$grep_string" ]] && [[ ! -n "$last" ]]
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

  if [[ -n "$count" ]]
  then
    if [[ -n "$grep_string" ]]
    then
      print_count "$nb_matched"
    else
      print_count "$nb_consumed"
    fi
  fi
done
