converter=${args[--converter]}
dlq=${args[--dlq]}

if [[ -n "$dlq" ]]
then
    log "💀 add this for getting dead letter queue"
    echo -e "    \"errors.tolerance\": \"all\","
    echo -e "    \"errors.deadletterqueue.topic.name\": \"dlq\","
    echo -e "    \"errors.deadletterqueue.topic.replication.factor\": \"1\","
    echo -e "    \"errors.deadletterqueue.context.headers.enable\": \"true\","
    echo -e "    \"errors.log.enable\": \"true\","
    echo -e "    \"errors.log.include.messages\": \"true\","
fi

if [[ -n "$converter" ]]
then
    log "🔌 converter config for $converter"
    case "${converter}" in
        string)
            echo -e "    \"key.converter\": \"org.apache.kafka.connect.storage.StringConverter\","
            echo -e "    \"value.converter\": \"org.apache.kafka.connect.storage.StringConverter\","
        ;;
        bytearray)
            echo -e "    \"key.converter\": \"org.apache.kafka.connect.converters.ByteArrayConverter\","
            echo -e "    \"value.converter\": \"org.apache.kafka.connect.converters.ByteArrayConverter\","
        ;;
        json)
            echo -e "    \"key.converter\": \"org.apache.kafka.connect.json.JsonConverter\","
            echo -e "    \"key.converter.schemas.enable\": \"false\","
            echo -e "    \"value.converter\": \"org.apache.kafka.connect.json.JsonConverter\","
            echo -e "    \"value.converter.schemas.enable\": \"false\","
        ;;
        json-schema-enabled)
            echo -e "    \"key.converter\": \"org.apache.kafka.connect.json.JsonConverter\","
            echo -e "    \"value.converter\": \"org.apache.kafka.connect.json.JsonConverter\","
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
                echo -e "    \"key.converter\": \"$converter_class\","
                echo -e "    \"key.converter.schema.registry.url\": \"http://schema-registry:8081\","
                echo -e "    \"value.converter\": \"$converter_class\","
                echo -e "    \"value.converter.schema.registry.url\": \"http://schema-registry:8081\","
            ;;
            ccloud)
                if [ -f $root_folder/.ccloud/env.delta ]
                then
                    source $root_folder/.ccloud/env.delta
                else
                    logerror "ERROR: $root_folder/.ccloud/env.delta has not been generated"
                    exit 1
                fi
                echo -e "    \"key.converter\": \"$converter_class\","
                echo -e "    \"key.converter.schema.registry.url\": \"$SCHEMA_REGISTRY_URL\","
                echo -e "    \"key.converter.basic.auth.credentials.source\": \"USER_INFO\","
                echo -e "    \"key.converter.basic.auth.user.info\": \"\${file:/data:schema.registry.basic.auth.user.info}\","
                echo -e "    \"value.converter\": \"$converter_class\","
                echo -e "    \"value.converter.schema.registry.url\": \"$SCHEMA_REGISTRY_URL\","
                echo -e "    \"value.converter.basic.auth.credentials.source\": \"USER_INFO\","
                echo -e "    \"value.converter.basic.auth.user.info\": \"\${file:/data:schema.registry.basic.auth.user.info}\","
                ;;

            sasl-ssl|2way-ssl)
                echo -e "    \"key.converter\": \"$converter_class\","
                echo -e "    \"key.converter.schema.registry.url\": \"https://schema-registry:8081\","
                echo -e "    \"key.converter.schema.registry.ssl.truststore.location\": \"/etc/kafka/secrets/kafka.connect.truststore.jks\","
                echo -e "    \"key.converter.schema.registry.ssl.truststore.password\": \"confluent\","
                echo -e "    \"key.converter.schema.registry.ssl.keystore.location\": \"/etc/kafka/secrets/kafka.connect.keystore.jks\","
                echo -e "    \"key.converter.schema.registry.ssl.keystore.password\": \"confluent\","
                echo -e "    \"key.converter.schema.registry.ssl.key.password\": \"confluent\","
                echo -e "    \"value.converter\": \"$converter_class\","
                echo -e "    \"value.converter.schema.registry.url\": \"https://schema-registry:8081\","
                echo -e "    \"value.converter.schema.registry.ssl.truststore.location\": \"/etc/kafka/secrets/kafka.connect.truststore.jks\","
                echo -e "    \"value.converter.schema.registry.ssl.truststore.password\": \"confluent\","
                echo -e "    \"value.converter.schema.registry.ssl.keystore.location\": \"/etc/kafka/secrets/kafka.connect.keystore.jks\","
                echo -e "    \"value.converter.schema.registry.ssl.keystore.password\": \"confluent\","
                echo -e "    \"value.converter.schema.registry.ssl.key.password\": \"confluent\","
                ;;

            rbac-sasl-plain)
                echo -e "    \"key.converter\": \"$converter_class\","
                echo -e "    \"key.converter.schema.registry.url\": \"http://schema-registry:8081\","
                echo -e "    \"key.converter.basic.auth.credentials.source\": \"USER_INFO\","
                echo -e "    \"key.converter.basic.auth.user.info\": \"connectorSA:connectorSA\","
                echo -e "    \"value.converter\": \"$converter_class\","
                echo -e "    \"value.converter.schema.registry.url\": \"http://schema-registry:8081\","
                echo -e "    \"value.converter.basic.auth.credentials.source\": \"USER_INFO\","
                echo -e "    \"value.converter.basic.auth.user.info\": \"connectorSA:connectorSA\","
                ;;
            *)
                return
            ;;
            esac
        ;;
    esac
fi