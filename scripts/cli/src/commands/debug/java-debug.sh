container="${args[--container]}"
type="${args[--type]}"
action="${args[--action]}"

if [[ "$action" == "enable" ]]
then
    case "${type}" in
        "ssl_all")
            OPTS="-Djavax.net.debug=all"
        ;;
        "ssl_handshake")
            OPTS="-Djavax.net.debug=ssl:handshake"
        ;;
        "class_loading")
            OPTS="-verbose:class"
        ;;
        "kerberos")
            OPTS="-Dsun.security.krb5.debug=true"
        ;;
    esac
    
    playground container set-enviroment-variables --container "${container}" --env "KAFKA_OPTS: ${OPTS}"
else
    playground container set-enviroment-variables --container "${container}" --restore-original-values
fi