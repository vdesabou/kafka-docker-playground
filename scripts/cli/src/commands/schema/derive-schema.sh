schema_type="${args[--schema-type]}"
payload="${args[--payload]}"
name="${args[--name]}"
namespace="${args[--namespace]}"
output_file="${args[--output-file]}"
register="${args[--register]}"
subject="${args[--subject]}"
verbose="${args[--verbose]}"

if [[ -n "$register" ]] && [[ ! -n "$subject" ]]
then
    logerror "❌ --register needs --subject"
    exit 1
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

payload_file=$tmp_dir/payload_file

if [ "$payload" = "-" ]
then
    # stdin
    if [ -t 0 ]
    then
        logerror "❌ stdin is empty you probably forgot to set --payload !"
        exit 1
    else
        payload_content=$(cat "$payload")
        echo "$payload_content" > $payload_file
    fi
else
    if [[ $payload == @* ]]
    then
        # this is a payload file
        argument_payload_file=$(echo "$payload" | cut -d "@" -f 2)
        cp $argument_payload_file $payload_file
    elif [ -f "$payload" ]
    then
        cp $payload $payload_file
    else
        payload_content=$payload
        echo "$payload_content" > $payload_file
    fi
fi

if jq -e . >/dev/null 2>&1 <<< "$(head -1 "$payload_file")"
then
    log "💫 payload is one json per line, one json record per line will be used"
elif jq -e . >/dev/null 2>&1 <<< "$(cat "$payload_file")"
then
    log "💫 payload is single json, it will be used as one record"
    jq -c . "$payload_file" > $tmp_dir/minified.json
    cp $tmp_dir/minified.json $payload_file
else
    logerror "❌ payload is not a valid json"
    exit 1
fi

LATEST_TAG=$(grep "export TAG" $root_folder/scripts/utils.sh | head -1 | cut -d "=" -f 2 | cut -d " " -f 1)
if [ -z "$LATEST_TAG" ]
then
    logerror "❌ error while getting default TAG "
    exit 1
fi

cat << EOF > $tmp_dir/pom.xml
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0   
http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>io.confluent.app</groupId>
  <artifactId>my-app</artifactId>
  <version>1</version>
  <pluginRepositories>
    <pluginRepository>
      <id>confluent</id>
      <url>https://packages.confluent.io/maven/</url>
    </pluginRepository>
  </pluginRepositories>
  <build>
    <plugins>
      <plugin>
        <groupId>io.confluent</groupId>
        <artifactId>kafka-schema-registry-maven-plugin</artifactId>
        <version>$LATEST_TAG</version>
        <configuration>
          <messagePath>/usr/src/mymaven/payload_file</messagePath>
          <schemaType>$schema_type</schemaType>
          <outputPath>/usr/src/mymaven/schema_file</outputPath>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF

set +e
log "🔮 Calling derive-schema maven plugin (see https://docs.confluent.io/platform/current/schema-registry/develop/maven-plugin.html#schema-registry-derive-schema)"
docker run -i --rm -v "${tmp_dir}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml io.confluent:kafka-schema-registry-maven-plugin:derive-schema > /tmp/result.log 2>&1
if [ $? != 0 ]
then
    logerror "❌ error while calling derive-schema"
    tail -100 /tmp/result.log
    exit 1
fi

set -e
log "🪄 Schema file generated"

# the maven plugin names everything "Schema": rename the top-level type, set its namespace / package
function rename_schema() {
    local schema="$1"
    case "$schema_type" in
        AVRO)
            echo "$schema" | jq --arg n "$name" --arg ns "$namespace" '(if $n != "" then .name = $n else . end) | (if $ns != "" then .namespace = $ns else . end)'
            ;;
        JSON)
            echo "$schema" | jq --arg n "$name" '(if $n != "" then .title = $n else . end)'
            ;;
        PROTOBUF)
            local out="$schema"
            if [ -n "$name" ]
            then
                out=$(echo "$out" | sed -e "s/^message Schema {/message ${name} {/")
            fi
            if [ -n "$namespace" ]
            then
                out=$(echo "$out" | awk -v pkg="$namespace" '{print} /^syntax = / && !done {print ""; print "package " pkg ";"; done=1}')
            fi
            echo "$out"
            ;;
    esac
}

nb_schemas=$(jq '.schemas | length' $tmp_dir/schema_file)
first_schema=""
for i in $(seq 0 $((nb_schemas-1)))
do
    if [ "$schema_type" == "PROTOBUF" ]
    then
        derived=$(jq -r ".schemas[$i].schema" $tmp_dir/schema_file)
    else
        derived=$(jq ".schemas[$i].schema" $tmp_dir/schema_file)
    fi
    derived=$(rename_schema "$derived")
    [ $i -eq 0 ] && first_schema="$derived"
    echo "$derived"
done
if [ "$nb_schemas" -gt 1 ] && { [[ -n "$output_file" ]] || [[ -n "$register" ]]; }
then
    logwarn "the records gave ${nb_schemas} schemas that can't be merged: only the first one is written / registered"
fi

# hints: values that look like a logical type the plugin can't guess
hints=$(jq -r '
  paths(scalars) as $p | getpath($p) as $v | ($p | map(tostring) | join(".")) as $path |
  if ($v | type) == "string" then
    if ($v | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) then "\($path): \"\($v)\" looks like a date (avro: {\"type\": \"int\", \"logicalType\": \"date\"}, json schema: \"format\": \"date\")"
    elif ($v | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}")) then "\($path): \"\($v)\" looks like a timestamp (avro: {\"type\": \"long\", \"logicalType\": \"timestamp-millis\"}, json schema: \"format\": \"date-time\")"
    elif ($v | test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")) then "\($path): looks like a uuid (avro: {\"type\": \"string\", \"logicalType\": \"uuid\"})"
    elif ($v | test("^-?[0-9]+\\.[0-9]+$")) then "\($path): \"\($v)\" is a number in a string: a decimal? (avro: {\"type\": \"bytes\", \"logicalType\": \"decimal\", \"precision\": …, \"scale\": …})"
    else empty end
  elif ($v | type) == "number" and ($v | tostring | test("^1[0-9]{12}$")) then "\($path): \($v) looks like epoch milliseconds (avro: {\"type\": \"long\", \"logicalType\": \"timestamp-millis\"})"
  else empty end' $payload_file 2> /dev/null | awk -F': ' '!seen[$1]++')
if [ -n "$hints" ]
then
    while read -r hint
    do
        log "💡 $hint"
    done <<< "$hints"
fi

if [[ -n "$output_file" ]]
then
    echo "$first_schema" > "$output_file"
    log "📄 schema written to $output_file"
fi
if [[ -n "$register" ]]
then
    echo "$first_schema" > $tmp_dir/derived_schema
    playground schema register --subject "$subject" --schema "@$tmp_dir/derived_schema"
fi