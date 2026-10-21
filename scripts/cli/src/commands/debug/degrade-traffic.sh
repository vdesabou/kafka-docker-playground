eval "containers=(${args[--container]})"
destination="${args[--destination]}"
port="${args[--port]}"
latency="${args[--latency]}"
jitter="${args[--jitter]}"
loss="${args[--loss]}"
corruption="${args[--corruption]}"
duplicate="${args[--duplicate]}"
rate="${args[--rate]}"
action="${args[--action]}"

get_environment_used

# 1. the netem parameters
time_pattern="^[0-9]+(\.[0-9]+)?(us|ms|s)$"
percent_pattern="^[0-9]+(\.[0-9]+)?%$"
rate_pattern="^[0-9]+(\.[0-9]+)?(bit|kbit|mbit|gbit|bps|kbps|mbps|gbps)$"
for check in "--latency@$latency@$time_pattern@100ms" "--jitter@$jitter@$time_pattern@20ms" "--loss@$loss@$percent_pattern@1%" "--corruption@$corruption@$percent_pattern@1%" "--duplicate@$duplicate@$percent_pattern@1%" "--rate@$rate@$rate_pattern@1mbit"
do
    IFS='@' read -r flag value pattern sample <<< "$check"
    if [[ -n "$value" ]] && [[ ! "$value" =~ $pattern ]]
    then
        logerror "❌ $flag $value is not valid, example: $flag $sample"
        exit 1
    fi
done
if [[ -n "$jitter" ]] && [[ -z "$latency" ]]
then
    logerror "❌ --jitter needs --latency"
    exit 1
fi

netem=""
description=""
if [[ -n "$latency" ]]
then
    netem="$netem delay $latency${jitter:+ $jitter}"
    description="$description, ${latency}${jitter:+ ± $jitter} latency"
fi
if [[ -n "$loss" ]]
then
    netem="$netem loss $loss"
    description="$description, $loss packet loss"
fi
if [[ -n "$corruption" ]]
then
    netem="$netem corrupt $corruption"
    description="$description, $corruption packet corruption"
fi
if [[ -n "$duplicate" ]]
then
    netem="$netem duplicate $duplicate"
    description="$description, $duplicate packet duplication"
fi
if [[ -n "$rate" ]]
then
    netem="$netem rate $rate"
    description="$description, $rate bandwidth"
fi
description="${description#, }"

if [ "$action" == "start" ] && [[ -z "$netem" ]]
then
    logerror "❌ --action start needs at least one of --latency, --loss, --corruption, --duplicate or --rate"
    exit 1
fi
if [ "$action" != "start" ] && [[ -n "$netem" ]]
then
    logwarn "🤷 --latency, --loss, --corruption, --duplicate and --rate are only used with --action start"
fi
if [[ -n "$port" ]] && [[ -z "$destination" ]]
then
    logerror "❌ --port needs --destination"
    exit 1
fi

# 2. the destination
destination_ips=()
if [[ -n "$destination" ]]
then
    mapfile -t destination_ips < <(resolve_traffic_destination_ips "$destination")
    if [[ ${#destination_ips[@]} -eq 0 ]]
    then
        logerror "❌ Unable to determine destination IPs for $destination"
        exit 1
    fi
fi
ip_display=$(printf "%s " "${destination_ips[@]}")
ip_display=${ip_display% }

if [[ -n "$destination" ]]
then
    target="to $destination ($ip_display)${port:+ port $port}"
else
    target="to any destination"
fi

#
# 3. the tc commands, run in the network namespace of each container
#
# - with a destination: a prio qdisc whose band 1:1 (the destination, and port) goes through
#   netem and band 1:2 (everything else) through sfq, unchanged
# - without: netem as root qdisc of the interface of the default route
# tc only shapes outgoing packets: the round trip to the destination grows by the latency.
#
# the interface: the one of the route to the destination (containers on several networks
# have several), the one of the default route otherwise
interface_cmd="ip route get ${destination_ips[0]:-1.1.1.1} 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1"

case "$action" in
    start)
        cmd="dev=\$($interface_cmd); [ -n \"\$dev\" ] || { echo 'no network interface found' >&2; exit 1; }; tc qdisc del dev \$dev root 2>/dev/null;"
        if [[ -n "$destination" ]]
        then
            cmd="$cmd tc qdisc add dev \$dev root handle 1: prio && tc qdisc add dev \$dev parent 1:1 handle 10: netem$netem && tc qdisc add dev \$dev parent 1:2 handle 20: sfq"
            for ip in "${destination_ips[@]}"
            do
                if [[ -n "$port" ]]
                then
                    cmd="$cmd && tc filter add dev \$dev protocol ip parent 1: prio 1 u32 match ip dst $ip/32 match ip dport $port 0xffff flowid 1:1"
                else
                    cmd="$cmd && tc filter add dev \$dev protocol ip parent 1: prio 1 u32 match ip dst $ip/32 flowid 1:1"
                fi
            done
            # everything else (ip and icmp) to the band without degradation
            cmd="$cmd && tc filter add dev \$dev protocol all parent 1: prio 2 u32 match ip dst 0.0.0.0/0 flowid 1:2 && tc filter add dev \$dev protocol all parent 1: prio 2 u32 match ip protocol 1 0xff flowid 1:2"
        else
            cmd="$cmd tc qdisc add dev \$dev root netem$netem"
        fi
        ;;
    stop)
        # every interface but lo; 'Cannot delete qdisc with handle of zero' only means there was nothing
        cmd="for dev in \$(ls /sys/class/net | grep -v '^lo\$'); do tc qdisc del dev \$dev root 2>/dev/null; done; true"
        ;;
    status)
        cmd="for dev in \$(ls /sys/class/net | grep -v '^lo\$'); do tc qdisc show dev \$dev | grep -E 'netem|prio|sfq' | sed \"s/^/\$dev: /\"; done; true"
        ;;
esac

# round trip measured from the container, to show the effect: ping, or the time of a tcp
# connection when --port is set (only that tcp traffic is degraded, not icmp)
function measure_round_trip() {
    local container=$1
    local output
    local average
    if [[ -z "$destination" ]]
    then
        return
    fi
    if [[ -n "$port" ]]
    then
        output=$(run_in_network_namespace "$container" "bash -c 'for i in 1 2 3 4; do s=\$EPOCHREALTIME; if timeout 5 bash -c \"exec 3<>/dev/tcp/${destination_ips[0]}/$port\" 2>/dev/null; then e=\$EPOCHREALTIME; echo \"tcp \$s \$e\"; fi; done'" 2>&1 || true)
        average=$(echo "$output" | awk '$1 == "tcp" { total += ($3 - $2) * 1000; n++ } END { if (n > 0) printf "%.3f", total / n }')
        if [[ -n "$average" ]]
        then
            log "⏱️ tcp connection time from $container to $destination:$port: $average ms (average of $(echo "$output" | grep -c "^tcp") connections)"
        else
            logwarn "⏱️ no tcp connection to $destination:$port could be opened in 5 seconds"
        fi
        return
    fi
    output=$(run_in_network_namespace "$container" "ping -c 4 -i 0.3 -W 2 ${destination_ips[0]} 2>&1 | tail -2" 2>&1 || true)
    if grep -q "rtt" <<< "$output"
    then
        log "⏱️ round trip from $container to $destination: $(echo "$output" | grep rtt | awk -F '/' '{ print $5 }') ms (average of 4 pings)"
    else
        loss_line=$(echo "$output" | grep "packet loss" || true)
        logwarn "⏱️ no ping answer from $destination${loss_line:+ ($loss_line)}"
    fi
}

for container in "${containers[@]}"
do
    container=$(resolve_container_name_for_environment "$container")
    case "$action" in
        start)
            log "🐌 Applying $description on container $container $target"
            ;;
        stop)
            log "🟢 Removing the traffic degradation of container $container"
            ;;
        status)
            log "🔎 Traffic degradation of container $container"
            ;;
    esac

    set +e
    output=$(run_in_network_namespace "$container" "$cmd" 2>&1)
    ret=$?
    set -e
    if [ $ret -ne 0 ]
    then
        logerror "❌ tc failed on container $container"
        echo "$output"
        exit 1
    fi

    case "$action" in
        start)
            measure_round_trip "$container"
            ;;
        stop)
            log "✅ traffic of container $container is back to normal"
            measure_round_trip "$container"
            ;;
        status)
            if grep -q "netem" <<< "$output"
            then
                echo "$output" | grep "netem" | sed -e 's/^/   /' -e 's/ seed [0-9]*//'
            else
                log "✅ no degradation applied on container $container"
            fi
            measure_round_trip "$container"
            ;;
    esac
done
