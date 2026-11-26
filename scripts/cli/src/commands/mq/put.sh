container="${args[--container]}"
broker="${args[--broker]}"
user="${args[--user]}"
password="${args[--password]}"
mq_vhost="${args[--vhost]:-/}"
mq_vpn="${args[--vpn]:-default}"
queue="${args[--queue]}"
topic="${args[--topic]}"
message="${args[--message]}"
file="${args[--file]}"
nb_messages="${args[--nb-messages]}"
eval "headers=(${args[--header]:-})"

mq_resolve_container "$container" "$broker" || exit 2
mq_resolve_credentials "$user" "$password"
mq_check_destination "$queue" "$topic" put || exit 2
if [[ "$mq_broker" == "mqtt" ]]
then
    mq_mqtt_check_login || exit 2
fi

tmp_dir=$(mktemp -d -t pg-mq-XXXXXXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

# the messages, one per line: --message (a template with %g when --nb-messages is set), --file, or stdin
messages_args=(messages "--nb=${nb_messages:-0}")
if [[ -n "$message" ]]
then
    messages_args+=("--template=$message")
else
    if [[ -n "$file" ]]
    then
        cp "$file" "$tmp_dir/input.txt"
    elif [ ! -t 0 ]
    then
        cat > "$tmp_dir/input.txt"
    else
        logerror "❌ give the messages with --message, --file, or on stdin (one message per line)"
        exit 2
    fi
    messages_args+=("--file=$tmp_dir/input.txt")
fi
python3 -I "$root_folder/tools/mq/mq.py" "${messages_args[@]}" > "$tmp_dir/messages.txt" || exit 2
nb=$(grep -c '' "$tmp_dir/messages.txt" || true)
if [[ "$nb" -eq 0 ]]
then
    logerror "❌ no message to send (empty lines are skipped)"
    exit 2
fi

header_args=()
for h in "${headers[@]}"
do
    header_args+=("--header=$h")
done
if [[ ${#headers[@]} -gt 0 && "$mq_broker" == "ibmmq" ]]
then
    logwarn "⚠️ --header is ignored with IBM MQ: the amqsput / amqspub samples send no message property"
elif [[ ${#headers[@]} -gt 0 && "$mq_broker" == "solace" ]]
then
    logwarn "⚠️ --header is ignored with Solace: REST messaging is used without user properties"
fi

log "📤 Sending $nb message(s) to $mq_broker $mq_dest_type $mq_dest ($(mq_describe))"
case "$mq_broker" in
    ibmmq)
        sample="amqsput"
        [[ "$mq_dest_type" == "topic" ]] && sample="amqspub"
        rc=0
        out=$(mq_exec "/opt/mqm/samp/bin/$sample" "$mq_dest" "$mq_qmgr" < "$tmp_dir/messages.txt" 2>&1) || rc=$?
        if [[ $rc -ne 0 ]] || grep -q "reason code" <<< "$out"
        then
            logerror "❌ $sample failed:"
            echo "$out" | grep -v "^Sample\|^target" >&2
            if grep -q "reason code 2085" <<< "$out"
            then
                logerror "   🎓 2085 MQRC_UNKNOWN_OBJECT_NAME: queue $mq_dest does not exist in $mq_qmgr (DEV.QUEUE.1 to 3 exist in the developer config), create it with runmqsc"
            fi
            exit 1
        fi
    ;;
    mqtt)
        mqtt_args=(-h localhost -p 1883 -u "$mq_user" -P "$mq_password" -t "$mq_dest" -l)
        if [[ ${#headers[@]} -gt 0 ]]
        then
            # MQTT 5 user properties
            mqtt_args+=(-V mqttv5)
            for h in "${headers[@]}"
            do
                mqtt_args+=(-D publish user-property "${h%%=*}" "${h#*=}")
            done
        fi
        if ! out=$(mq_exec mosquitto_pub "${mqtt_args[@]}" < "$tmp_dir/messages.txt" 2>&1)
        then
            logerror "❌ mosquitto_pub failed: $out"
            exit 1
        fi
    ;;
    rabbitmq)
        if mq_rabbitmq_has_admin
        then
            if ! mq_exec rabbitmqctl -q list_queues -p "$mq_vhost" name < /dev/null 2>/dev/null | grep -qx "$mq_dest"
            then
                log "🆕 declaring queue $mq_dest (durable=false) in vhost $mq_vhost"
                mq_rabbitmq_admin declare queue "name=$mq_dest" durable=false > /dev/null || exit 1
            fi
            properties="{}"
            if [[ ${#headers[@]} -gt 0 ]]
            then
                properties=$(printf '%s\n' "${headers[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0) | capture("^(?<k>[^=]*)=(?<v>.*)$")) | {headers: (map({(.k): .v}) | add)}')
            fi
            routed=0
            while IFS= read -r line
            do
                out=$(mq_rabbitmq_admin publish exchange=amq.default "routing_key=$mq_dest" "payload=$line" "properties=$properties" 2>&1 || true)
                if [[ "$out" == "Message published" ]]
                then
                    routed=$((routed + 1))
                else
                    logerror "❌ rabbitmqadmin publish: $out"
                fi
            done < "$tmp_dir/messages.txt"
            if [[ "$routed" -ne "$nb" ]]
            then
                logerror "❌ $routed of $nb message(s) routed to queue $mq_dest"
                exit 1
            fi
            log "✅ $nb message(s) sent to $mq_dest_type $mq_dest"
            exit 0
        fi
        mq_rabbitmq_api_ready || exit 2
        queue_path=$(mq_rabbitmq_queue_path)
        code=$(mq_curl -o /dev/null -w '%{http_code}' -u "$mq_user:$mq_password" "http://localhost:15672/api/queues/$queue_path" || true)
        if [[ "$code" == "404" ]]
        then
            # declared like the producer of the examples: not durable, not auto-deleted
            log "🆕 declaring queue $mq_dest (durable=false) in vhost $mq_vhost"
            mq_curl -f -o /dev/null -u "$mq_user:$mq_password" -X PUT -H "Content-Type: application/json" -d '{"durable":false,"auto_delete":false}' "http://localhost:15672/api/queues/$queue_path" || exit 1
        fi
        python3 -I "$root_folder/tools/mq/mq.py" curl-config --broker rabbitmq "--dest=$mq_dest" --messages "$tmp_dir/messages.txt" "${header_args[@]}" "--user=$mq_user" "--password=$mq_password" "--vhost=$mq_vhost" > "$tmp_dir/curl.conf" || exit 2
        out=$(mq_curl -K - < "$tmp_dir/curl.conf" || true)
        routed=$(grep -o '"routed":true' <<< "$out" | wc -l | tr -d ' ')
        if [[ "$routed" -ne "$nb" ]]
        then
            logerror "❌ $routed of $nb message(s) routed to queue $mq_dest: $(grep -v '"routed":true' <<< "$out" | head -3)"
            exit 1
        fi
    ;;
    activemq|solace)
        python3 -I "$root_folder/tools/mq/mq.py" curl-config --broker "$mq_broker" "--dest=$mq_dest" "--dest-type=$mq_dest_type" --messages "$tmp_dir/messages.txt" "${header_args[@]}" "--user=$mq_user" "--password=$mq_password" > "$tmp_dir/curl.conf" || exit 2
        out=$(mq_curl -K - < "$tmp_dir/curl.conf" || true)
        ok=$(grep -c '^200$' <<< "$out" || true)
        if [[ "$ok" -ne "$nb" ]]
        then
            logerror "❌ $ok of $nb message(s) accepted by $mq_broker (HTTP codes: $(sort <<< "$out" | uniq -c | tr -s ' \n' ' '))"
            grep -q '^401$' <<< "$out" && logerror "   🔐 authentication refused for user $mq_user: pass --user / --password"
            [[ "$mq_broker" == "solace" ]] && grep -q '^400$' <<< "$out" && logerror "   🎓 Solace REST messaging (port 9000 of the default message VPN): the queue must exist, see create_queue_cmd of the Solace examples"
            exit 1
        fi
    ;;
esac
log "✅ $nb message(s) sent to $mq_dest_type $mq_dest"
