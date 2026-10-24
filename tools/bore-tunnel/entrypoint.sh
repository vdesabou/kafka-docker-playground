#!/bin/sh
# ngrok-compatible entrypoint: reads the tunnels of the ngrok v2 config file given with --config (name, addr host:port,
# proto tcp), opens one bore tunnel per entry, then serves {"tunnels":[{"name","proto","public_url":"tcp://host:port"}]}
# on port 4040 like the ngrok agent API, in the order of the config file
config="/etc/ngrok.yml"
while [ $# -gt 0 ]
do
    case "$1" in
        --config) config="$2"; shift 2 ;;
        --config=*) config="${1#--config=}"; shift ;;
        *) shift ;;
    esac
done

if [ -z "$BORE_SERVER" ]
then
    echo "BORE_SERVER is not set" >&2
    exit 1
fi
if [ ! -f "$config" ]
then
    echo "config file $config not found" >&2
    exit 1
fi

# one "<name> <host> <port>" line per tunnel
tunnels=$(awk '
    /^tunnels:/ { in_tunnels = 1; next }
    in_tunnels && /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ { name = $1; sub(":", "", name); next }
    in_tunnels && /^[[:space:]]+addr:/ { addr = $2; gsub(/["\047]/, "", addr); n = split(addr, a, ":"); print name, (n > 1 ? a[1] : "localhost"), a[n] }
' "$config")
if [ -z "$tunnels" ]
then
    echo "no tunnel found in $config" >&2
    exit 1
fi

# bore reads the secret from BORE_SECRET (not on the command line, where ps would show it): compose passes an empty
# value when it is not exported, which would be sent as an empty secret
[ -z "$BORE_SECRET" ] && unset BORE_SECRET

mkdir -p /www/api /tmp/bore
echo "$tunnels" | while read -r name host port
do
    echo "🚇 bore tunnel $name: $host:$port -> $BORE_SERVER"
    bore local "$port" --local-host "$host" --to "$BORE_SERVER" > "/tmp/bore/$name.log" 2>&1 &
done

# public endpoint of each tunnel, from the 'listening at <host>:<port>' line of its client
json=""
echo "$tunnels" | while read -r name host port
do
    public=""
    for i in $(seq 1 60)
    do
        public=$(sed 's/\x1b\[[0-9;]*m//g' "/tmp/bore/$name.log" | sed -n 's/.*listening at \([^ ]*\).*/\1/p' | tail -1)
        [ -n "$public" ] && break
        if ! pgrep -f "bore local $port --local-host $host " > /dev/null
        then
            cat "/tmp/bore/$name.log" >&2
            echo "❌ bore tunnel $name exited" >&2
            exit 1
        fi
        sleep 1
    done
    if [ -z "$public" ]
    then
        cat "/tmp/bore/$name.log" >&2
        echo "❌ bore tunnel $name not ready after 60 seconds" >&2
        exit 1
    fi
    echo "✅ bore tunnel $name: tcp://$public"
    printf '{"name":"%s","proto":"tcp","public_url":"tcp://%s","config":{"addr":"%s:%s"}}\n' "$name" "$public" "$host" "$port" >> /tmp/bore/tunnels.jsonl
done || exit 1

# written once all the tunnels are up: until then the API answers 404, and the examples keep waiting
{ printf '{"tunnels":['; paste -s -d, /tmp/bore/tunnels.jsonl | tr -d '\n'; printf ']}'; } > /www/api/tunnels.tmp
mv /www/api/tunnels.tmp /www/api/tunnels
httpd -p 4040 -h /www

# the container lives as long as its tunnels: one exits (server restart…), the container exits too
tail -n +1 -f /tmp/bore/*.log &
while pgrep -f "bore local" > /dev/null
do
    sleep 5
done
echo "❌ a bore tunnel exited" >&2
exit 1
