converter=${args[--converter]}
dlq=${args[--dlq]}

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
if [ -z "$PG_VERBOSE_MODE" ]
then
    trap 'rm -rf $tmp_dir' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# $1: schema registry host (default schema-registry)
function plaintext_schema_registry_snippet () {
    local sr_host="${1:-schema-registry}"
    echo -e "    \"key.converter\": \"$converter_class\"," >> $converter_file
    echo -e "    \"key.converter.schema.registry.url\": \"http://$sr_host:8081\"," >> $converter_file
    echo -e "    \"value.converter\": \"$converter_class\"," >> $converter_file
    echo -e "    \"value.converter.schema.registry.url\": \"http://$sr_host:8081\"," >> $converter_file
}

if [[ ! -n "$converter" ]] && [[ ! -n "$dlq" ]]
then
    logerror "❌ neither --converter or --dlq were provided"
    exit 1
fi

connector_type=$(playground state get run.connector_type)
if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    # fully managed connectors have no converters: the format is input.data.format (sink) / output.data.format (source)
    if [[ -n "$dlq" ]]
    then
        dlq_file=$tmp_dir/dlq
        echo -e "    \"errors.tolerance\": \"all\"," >> $dlq_file
        log "💀 fully managed sink connectors send the records that fail to their dead letter queue topic dlq-<lcc id>, created for you (errors.tolerance all)"
    fi
    if [[ -n "$converter" ]]
    then
        case "${converter}" in
            avro) data_format="AVRO" ;;
            json-schema) data_format="JSON_SR" ;;
            protobuf) data_format="PROTOBUF" ;;
            json|json-schema-enabled) data_format="JSON" ;;
            string) data_format="STRING" ;;
            bytearray) data_format="BYTES" ;;
        esac
        converter_file=$tmp_dir/converter
        echo -e "    \"input.data.format\": \"$data_format\"," >> $converter_file
        echo -e "    \"output.data.format\": \"$data_format\"," >> $converter_file
        log "☁️ fully managed connector: keep input.data.format for a sink, output.data.format for a source (the schema registry of the environment is used for AVRO, JSON_SR and PROTOBUF)"
        if [ "$converter" == "json-schema-enabled" ]
        then
            logwarn "⚠️ fully managed connectors have no JSON with an embedded schema: use JSON_SR (--converter json-schema) for a schema"
        fi
    fi
elif [[ -n "$dlq" ]]
then
    dlq_file=$tmp_dir/dlq
    echo -e "    \"errors.tolerance\": \"all\"," >> $dlq_file
    echo -e "    \"errors.deadletterqueue.topic.name\": \"dlq\"," >> $dlq_file
    echo -e "    \"errors.deadletterqueue.topic.replication.factor\": \"1\"," >> $dlq_file
    echo -e "    \"errors.deadletterqueue.context.headers.enable\": \"true\"," >> $dlq_file
    echo -e "    \"errors.log.enable\": \"true\"," >> $dlq_file
    echo -e "    \"errors.log.include.messages\": \"true\"," >> $dlq_file
fi

if [[ -n "$converter" ]] && [ "$connector_type" != "$CONNECTOR_TYPE_FULLY_MANAGED" ]
then
    converter_file=$tmp_dir/converter
    case "${converter}" in
        string)
            echo -e "    \"key.converter\": \"org.apache.kafka.connect.storage.StringConverter\"," >> $converter_file
            echo -e "    \"value.converter\": \"org.apache.kafka.connect.storage.StringConverter\"," >> $converter_file
        ;;
        bytearray)
            echo -e "    \"key.converter\": \"org.apache.kafka.connect.converters.ByteArrayConverter\"," >> $converter_file
            echo -e "    \"value.converter\": \"org.apache.kafka.connect.converters.ByteArrayConverter\"," >> $converter_file
        ;;
        json)
            echo -e "    \"key.converter\": \"org.apache.kafka.connect.json.JsonConverter\"," >> $converter_file
            echo -e "    \"key.converter.schemas.enable\": \"false\"," >> $converter_file
            echo -e "    \"value.converter\": \"org.apache.kafka.connect.json.JsonConverter\"," >> $converter_file
            echo -e "    \"value.converter.schemas.enable\": \"false\"," >> $converter_file
        ;;
        json-schema-enabled)
            echo -e "    \"key.converter\": \"org.apache.kafka.connect.json.JsonConverter\"," >> $converter_file
            echo -e "    \"value.converter\": \"org.apache.kafka.connect.json.JsonConverter\"," >> $converter_file
        ;;
        avro|json-schema|protobuf)

            case "${converter}" in
                avro)
                    converter_class="io.confluent.connect.avro.AvroConverter"
                ;;
                json-schema)
                    converter_class="io.confluent.connect.json.JsonSchemaConverter"
                ;;
                protobuf)
                    converter_class="io.confluent.connect.protobuf.ProtobufConverter"
                ;;
            esac
            
            environment=$(playground state get run.environment_before_switch)
            if [ "$environment" = "" ]
            then
                environment=$(playground state get run.environment)
            fi

            if [ "$environment" = "" ]
            then
                environment="plaintext"
            fi

            case "${environment}" in
            plaintext|sasl-plain|ldap-authorizer-sasl-plain|ldap-sasl-plain|sasl-scram|sasl-oauthbearer|kerberos|ssl_kerberos)
                plaintext_schema_registry_snippet
            ;;
            ccloud)
                if [ -f $root_folder/.ccloud/env.delta ]
                then
                    source $root_folder/.ccloud/env.delta
                else
                    logerror "❌ $root_folder/.ccloud/env.delta has not been generated"
                    exit 1
                fi
                echo -e "    \"key.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.url\": \"$SCHEMA_REGISTRY_URL\"," >> $converter_file
                echo -e "    \"key.converter.basic.auth.credentials.source\": \"USER_INFO\"," >> $converter_file
                echo -e "    \"key.converter.basic.auth.user.info\": \"\${file:/datacloud:schema.registry.basic.auth.user.info}\"," >> $converter_file
                echo -e "    \"value.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.url\": \"$SCHEMA_REGISTRY_URL\"," >> $converter_file
                echo -e "    \"value.converter.basic.auth.credentials.source\": \"USER_INFO\"," >> $converter_file
                echo -e "    \"value.converter.basic.auth.user.info\": \"\${file:/datacloud:schema.registry.basic.auth.user.info}\"," >> $converter_file
                ;;

            sasl-ssl|2way-ssl)
                echo -e "    \"key.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.url\": \"https://schema-registry:8081\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.ssl.truststore.location\": \"/etc/kafka/secrets/kafka.connect.truststore.jks\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.ssl.truststore.password\": \"confluent\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.ssl.keystore.location\": \"/etc/kafka/secrets/kafka.connect.keystore.jks\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.ssl.keystore.password\": \"confluent\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.ssl.key.password\": \"confluent\"," >> $converter_file
                echo -e "    \"value.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.url\": \"https://schema-registry:8081\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.ssl.truststore.location\": \"/etc/kafka/secrets/kafka.connect.truststore.jks\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.ssl.truststore.password\": \"confluent\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.ssl.keystore.location\": \"/etc/kafka/secrets/kafka.connect.keystore.jks\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.ssl.keystore.password\": \"confluent\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.ssl.key.password\": \"confluent\"," >> $converter_file
                ;;

            rbac-sasl-plain)
                echo -e "    \"key.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $converter_file
                echo -e "    \"key.converter.basic.auth.credentials.source\": \"USER_INFO\"," >> $converter_file
                echo -e "    \"key.converter.basic.auth.user.info\": \"connectorSA:connectorSA\"," >> $converter_file
                echo -e "    \"value.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $converter_file
                echo -e "    \"value.converter.basic.auth.credentials.source\": \"USER_INFO\"," >> $converter_file
                echo -e "    \"value.converter.basic.auth.user.info\": \"connectorSA:connectorSA\"," >> $converter_file
                ;;
            rbac-oauth)
                # 'playground connector create-or-update' adds the bearer.auth.* keys itself on rbac-oauth
                for converter_prefix in key.converter value.converter
                do
                    echo -e "    \"$converter_prefix\": \"$converter_class\"," >> $converter_file
                    echo -e "    \"$converter_prefix.schema.registry.url\": \"http://schema-registry:8081\"," >> $converter_file
                    echo -e "    \"$converter_prefix.bearer.auth.credentials.source\": \"OAUTHBEARER\"," >> $converter_file
                    echo -e "    \"$converter_prefix.bearer.auth.issuer.endpoint.url\": \"http://keycloak:8080/realms/kafka/protocol/openid-connect/token\"," >> $converter_file
                    echo -e "    \"$converter_prefix.bearer.auth.client.id\": \"connector\"," >> $converter_file
                    echo -e "    \"$converter_prefix.bearer.auth.client.secret\": \"connector-secret\"," >> $converter_file
                done
                ;;
            mdc*)
                # one schema registry per cluster: schema-registry-us / schema-registry-europe
                sr_cluster="${PLAYGROUND_CLUSTER:-$(playground state get run.cluster 2> /dev/null)}"
                if [[ "$sr_cluster" != "europe" ]]
                then
                    [[ "$sr_cluster" != "us" ]] && log "🌍 $environment: showing the schema registry of cluster us (set PLAYGROUND_CLUSTER=europe for the other one)"
                    sr_cluster="us"
                fi
                plaintext_schema_registry_snippet "schema-registry-$sr_cluster"
            ;;
            *)
                # cfk...: the plaintext schema registry url ('connector create-or-update' rewrites it on cfk)
                logwarn "⚠️ no specific converter snippet for environment $environment, showing the plaintext one"
                plaintext_schema_registry_snippet
            ;;
            esac
        ;;
    esac
fi

clipboard_file=$tmp_dir/clipboard
if [ -f "$dlq_file" ]
then
    log "💀 add this for getting dead letter queue"
    cat $dlq_file

    cat $dlq_file >> $clipboard_file
fi

if [ -f "$converter_file" ]
then
    log "🔌 converter config for $converter"
    cat $converter_file

    cat $converter_file >> $clipboard_file
fi

if [[ "$OSTYPE" == "darwin"* ]]
then
    clipboard=$(playground config get clipboard)
    if [ "$clipboard" == "" ]
    then
        playground config set clipboard true
    fi

    if [ -f "$clipboard_file" ]
    then
        if [ "$clipboard" == "true" ] || [ "$clipboard" == "" ]
        then
            cat $clipboard_file | pbcopy
            log "📋 config has been copied to the clipboard (disable with 'playground config clipboard false')"
        fi
    fi
fi
