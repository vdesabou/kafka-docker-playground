converter=${args[--converter]}
dlq=${args[--dlq]}

tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

if [[ ! -n "$converter" ]] && [[ ! -n "$dlq" ]]
then
    logerror "❌ neither --converter or --dlq were provided"
    exit 1
fi

if [[ -n "$dlq" ]]
then
    dlq_file=$tmp_dir/dlq
    echo -e "    \"errors.tolerance\": \"all\"," >> $dlq_file
    echo -e "    \"errors.deadletterqueue.topic.name\": \"dlq\"," >> $dlq_file
    echo -e "    \"errors.deadletterqueue.topic.replication.factor\": \"1\"," >> $dlq_file
    echo -e "    \"errors.deadletterqueue.context.headers.enable\": \"true\"," >> $dlq_file
    echo -e "    \"errors.log.enable\": \"true\"," >> $dlq_file
    echo -e "    \"errors.log.include.messages\": \"true\"," >> $dlq_file
fi

if [[ -n "$converter" ]]
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
            plaintext|sasl-plain|ldap-authorizer-sasl-plain|ldap-sasl-plain|sasl-scram|kerberos|ssl_kerberos)
                echo -e "    \"key.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $converter_file
                echo -e "    \"value.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.url\": \"http://schema-registry:8081\"," >> $converter_file
            ;;
            ccloud)
                if [ -f $root_folder/.ccloud/env.delta ]
                then
                    source $root_folder/.ccloud/env.delta
                else
                    logerror "ERROR: $root_folder/.ccloud/env.delta has not been generated"
                    exit 1
                fi
                echo -e "    \"key.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"key.converter.schema.registry.url\": \"$SCHEMA_REGISTRY_URL\"," >> $converter_file
                echo -e "    \"key.converter.basic.auth.credentials.source\": \"USER_INFO\"," >> $converter_file
                echo -e "    \"key.converter.basic.auth.user.info\": \"\${file:/data:schema.registry.basic.auth.user.info}\"," >> $converter_file
                echo -e "    \"value.converter\": \"$converter_class\"," >> $converter_file
                echo -e "    \"value.converter.schema.registry.url\": \"$SCHEMA_REGISTRY_URL\"," >> $converter_file
                echo -e "    \"value.converter.basic.auth.credentials.source\": \"USER_INFO\"," >> $converter_file
                echo -e "    \"value.converter.basic.auth.user.info\": \"\${file:/data:schema.registry.basic.auth.user.info}\"," >> $converter_file
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
            *)
                return
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
            log "📋 config has been copied to the clipboard (disable with 'playground config set clipboard false')"
        fi
    fi
fi