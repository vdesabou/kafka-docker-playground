schema_type="${args[--schema-type]}"
payload="${args[--payload]}"
verbose="${args[--verbose]}"

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
docker run -i --rm -v "${tmp_dir}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$root_folder/scripts/settings.xml:/tmp/settings.xml" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml io.confluent:kafka-schema-registry-maven-plugin:derive-schema > /tmp/result.log 2>&1
if [ $? != 0 ]
then
    logerror "❌ error while calling derive-schema"
    tail -500 /tmp/result.log
    exit 1
fi

set -e
log "🪄 Schema file generated"
cat $tmp_dir/schema_file | jq -r '.schemas[]|del(.messagesMatched)|.schema'