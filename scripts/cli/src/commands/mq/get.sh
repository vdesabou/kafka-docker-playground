container="${args[--container]}"
broker="${args[--broker]}"
user="${args[--user]}"
password="${args[--password]}"
mq_vhost="${args[--vhost]:-/}"
mq_vpn="${args[--vpn]:-default}"
queue="${args[--queue]}"
topic="${args[--topic]}"
max_messages="${args[--max-messages]}"
timeout="${args[--timeout]}"
json="${args[--json]}"

if [[ -n "$json" ]]
then
    # stdout only gets the json document
    exec 3>&1 1>&2
fi

mq_resolve_container "$container" "$broker" || exit 2
mq_resolve_credentials "$user" "$password"
mq_check_destination "$queue" "$topic" get || exit 2
if [[ "$mq_broker" == "mqtt" ]]
then
    mq_mqtt_check_login || exit 2
fi

tmp_dir=$(mktemp -d -t pg-mq-XXXXXXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

case "$mq_broker" in
    ibmmq)
        log "🔎 Browsing queue $mq_dest ($(mq_describe)), the messages stay in the queue"
        # amqsbcg browses (MQOO_BROWSE): nothing is removed
        mq_exec /opt/mqm/samp/bin/amqsbcg "$mq_dest" "$mq_qmgr" < /dev/null > "$tmp_dir/raw.txt" 2>&1 || true
        if grep -q -i "failed with CompCode\|reason code" "$tmp_dir/raw.txt"
        then
            logerror "❌ amqsbcg failed: $(grep -i "failed with CompCode\|reason code" "$tmp_dir/raw.txt" | head -1 | sed 's/^ *//')"
            if grep -q "2085" "$tmp_dir/raw.txt"
            then
                logerror "   🎓 2085 MQRC_UNKNOWN_OBJECT_NAME: queue $mq_dest does not exist in $mq_qmgr"
            fi
            exit 2
        fi
    ;;
    rabbitmq)
        log "🔎 Browsing queue $mq_dest ($(mq_describe)): read and requeued, the messages stay in the queue (marked redelivered)"
        if mq_rabbitmq_has_admin
        then
            if ! mq_exec rabbitmqctl -q list_queues -p "$mq_vhost" name < /dev/null 2>/dev/null | grep -qx "$mq_dest"
            then
                logerror "❌ queue $mq_dest does not exist in vhost $mq_vhost"
                exit 2
            fi
            mq_rabbitmq_admin -f raw_json get "queue=$mq_dest" "count=$max_messages" ackmode=ack_requeue_true > "$tmp_dir/raw.txt" 2>&1 || true
            code=200
        else
        mq_rabbitmq_api_ready || exit 2
        code=$(mq_curl_to_file "$tmp_dir/raw.txt" -u "$mq_user:$mq_password" -X POST -H "Content-Type: application/json" \
            -d "{\"count\":$max_messages,\"ackmode\":\"ack_requeue_true\",\"encoding\":\"auto\",\"truncate\":100000}" \
            "http://localhost:15672/api/queues/$(mq_rabbitmq_queue_path)/get")
        fi
        if [[ "$code" == "404" ]]
        then
            logerror "❌ queue $mq_dest does not exist in vhost $mq_vhost"
            exit 2
        fi
    ;;
    mqtt)
        log "👂 Subscribing to topic $mq_dest for up to $timeout seconds or $max_messages message(s) ($(mq_describe)): only the retained message and the messages published meanwhile are received"
        rc=0
        mq_exec mosquitto_sub -h localhost -p 1883 -u "$mq_user" -P "$mq_password" -t "$mq_dest" -C "$max_messages" -W "$timeout" < /dev/null > "$tmp_dir/raw.txt" 2> "$tmp_dir/err.txt" || rc=$?
        # 27: timeout of -W, not an error
        if [[ $rc -ne 0 && $rc -ne 27 ]]
        then
            logerror "❌ mosquitto_sub failed: $(cat "$tmp_dir/err.txt")"
            exit 2
        fi
    ;;
    activemq)
        log "🔎 Browsing queue $mq_dest ($(mq_describe)) with Jolokia, the messages stay in the queue"
        search=$(mq_curl -u "$mq_user:$mq_password" "http://localhost:8161/api/jolokia/search/org.apache.activemq:type=Broker,brokerName=*,destinationType=Queue,destinationName=$(mq_urlencode "$mq_dest")" || true)
        mbean=$(jq -r '.value[0] // empty' <<< "$search" 2>/dev/null)
        if [[ -z "$mbean" ]]
        then
            if jq -e '.status == 200' <<< "$search" > /dev/null 2>&1
            then
                logerror "❌ queue $mq_dest does not exist in $mq_container"
            else
                logerror "❌ could not reach the Jolokia API of $mq_container (port 8161, user $mq_user): $(head -c 200 <<< "$search")"
            fi
            exit 2
        fi
        jq -n --arg m "$mbean" '{"type":"exec","mbean":$m,"operation":"browse()"}' > "$tmp_dir/req.json"
        mq_curl -u "$mq_user:$mq_password" -H "Content-Type: application/json" -H "Origin: http://localhost" -d @- "http://localhost:8161/api/jolokia/" < "$tmp_dir/req.json" > "$tmp_dir/raw.txt" || true
    ;;
    solace)
        log "🔎 Listing the messages spooled in queue $mq_dest ($(mq_describe)) with SEMP: their metadata only, SEMP does not return the bodies"
        mq_curl -u "$mq_user:$mq_password" "http://localhost:8080/SEMP/v2/monitor/msgVpns/$(mq_urlencode "$mq_vpn")/queues/$(mq_urlencode "$mq_dest")/msgs?count=$max_messages" > "$tmp_dir/raw.txt" || true
    ;;
esac

if ! python3 -I "$root_folder/tools/mq/mq.py" parse --broker "$mq_broker" "--max=$max_messages" < "$tmp_dir/raw.txt" > "$tmp_dir/messages.jsonl"
then
    exit 2
fi
if [[ -n "$json" ]]
then
    python3 -I "$root_folder/tools/mq/mq.py" show --json "--dest=$mq_dest_type $mq_dest" < "$tmp_dir/messages.jsonl" >&3
else
    python3 -I "$root_folder/tools/mq/mq.py" show "--dest=$mq_dest_type $mq_dest" < "$tmp_dir/messages.jsonl"
fi
