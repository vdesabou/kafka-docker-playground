eval "file_array=(${args[--file]})"
eval "sample_array=(${args[--sample]})"
eval "container_array=(${args[--container]})"
eval "kafka_port_array=(${args[--kafka-port]})"
eval "http_port_array=(${args[--http-port]})"
hosts="${args[--hosts]}"
duration="${args[--duration]}"
port="${args[--port]}"
filter="${args[--filter]}"
output_dir="${args[--output-dir]}"
json_out="${args[--json]}"
top="${args[--top]}"

# with --json, logs go to stderr and only the analysis to stdout (same as analyze thread-dump)
if [[ -n "$json_out" ]]; then
    exec 3>&1 1>&2
fi

nb_modes=0
[[ ${#file_array[@]} -gt 0 ]] && nb_modes=$((nb_modes + 1))
[[ ${#sample_array[@]} -gt 0 ]] && nb_modes=$((nb_modes + 1))
[[ ${#container_array[@]} -gt 0 ]] && nb_modes=$((nb_modes + 1))
if [[ $nb_modes -gt 1 ]]; then
    logerror "❌ Provide only one of --file, --container and --sample"
    exit 1
fi
if [[ $nb_modes -eq 0 ]]; then
    container_array=("connect")
fi

# ── Container mode: capture for --duration with playground debug tcp-dump, which analyzes the captures ──
if [[ ${#container_array[@]} -gt 0 ]]; then
    if [[ -n "$json_out" ]]; then
        logerror "❌ --json works with --file and --sample: capture first, then analyze the .pcap"
        exit 1
    fi
    capture_args=(--duration "$duration" --output-dir "$output_dir")
    for container in "${container_array[@]}"
    do
        capture_args+=(--container "$container")
    done
    [[ -n "$port" ]] && capture_args+=(--port "$port")
    [[ -n "$filter" ]] && capture_args+=(--filter "$filter")
    playground debug tcp-dump "${capture_args[@]}"
    exit $?
fi

# ── Sample mode: captures shipped with the analyzer ──
samples_dir="$root_folder/tools/tcp-dump/samples"
for sample in "${sample_array[@]}"
do
    file_array+=("$samples_dir/$sample.pcap")
done

analyzer="$root_folder/tools/tcp-dump/tcp_dump_analyzer.py"
extractor="$root_folder/tools/tcp-dump/extract.sh"
if ! command -v python3 &>/dev/null; then
    logerror "❌ python3 is required but not found on PATH"
    exit 1
fi
if ! docker image inspect $PLAYGROUND_NETSHOOT_IMAGE > /dev/null 2>&1; then
    log "📥 pulling $PLAYGROUND_NETSHOOT_IMAGE (tshark, only the first time)"
    docker pull $PLAYGROUND_NETSHOOT_IMAGE > /dev/null
fi

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

# listener ports decoded as Kafka, besides 9092: the KRaft controller and the host listeners of the playground brokers
kafka_ports="9093 29092 29292 29392 ${kafka_port_array[*]}"
# ports decoded as HTTP, besides the defaults of tshark (80, 8080, 8088...): schema registry, rest proxy, connect,
# ksqldb, the test HTTP server of the examples (httpserver), control center
http_ports="8081 8082 8083 8088 9006 9021 ${http_port_array[*]}"

tmp_dir=$(mktemp -d -t pg-tcp-dump-XXXXXXXXXX)
extract_container="pg-tcpdump-analyze-$$"
if [ -z "$PG_VERBOSE_MODE" ]; then
    trap 'rm -rf "$tmp_dir"; docker rm -f "$extract_container" > /dev/null 2>&1' EXIT
else
    log "🐛📂 not deleting tmp dir $tmp_dir"
fi

# tshark runs in a netshoot container: the capture goes in and the extracted fields come out with docker cp (no bind
# mount, so any folder works, /tmp included, with docker and podman)
docker rm -f "$extract_container" > /dev/null 2>&1
if ! docker run -d --name "$extract_container" --entrypoint sleep $PLAYGROUND_NETSHOOT_IMAGE 3600 > /dev/null; then
    logerror "❌ could not start the $PLAYGROUND_NETSHOOT_IMAGE container that runs tshark"
    exit 1
fi
docker cp "$extractor" "$extract_container:/extract.sh" > /dev/null

failed=0
reports=()
for i in "${!file_array[@]}"
do
    file="${file_array[$i]}"
    # fzf @path trick
    if [[ ! -e "$file" && "$file" == *"@"* ]]; then
        file=$(echo "$file" | cut -d "@" -f 2)
    fi
    base=$(basename "$file")
    stem="${base%.*}"
    file_hosts="$hosts"
    # the .hosts file written by playground debug tcp-dump next to the capture
    if [[ -z "$file_hosts" ]] && [[ -f "${file%.*}.hosts" ]]; then
        file_hosts="${file%.*}.hosts"
    fi

    log "🦈 Analyzing $file${file_hosts:+ (names from $file_hosts)}"
    data_dir="$tmp_dir/$i"
    docker exec "$extract_container" rm -rf /data /capture > /dev/null 2>&1
    if ! docker cp "$file" "$extract_container:/capture" > /dev/null \
        || ! docker exec -e KAFKA_PORTS="$kafka_ports" -e HTTP_PORTS="$http_ports" "$extract_container" sh /extract.sh /capture /data \
        || ! docker cp "$extract_container:/data" "$data_dir" > /dev/null; then
        logerror "❌ could not read $file with tshark"
        failed=1
        continue
    fi

    analyzer_args=(--data "$data_dir" --title "$base" --top "$top")
    [[ -n "$file_hosts" ]] && analyzer_args+=(--hosts "$file_hosts")
    if [[ -n "$json_out" ]]; then
        python3 -I "$analyzer" "${analyzer_args[@]}" --json >&3 || failed=1
        continue
    fi
    html_out="$output_dir/${stem}-tcp-dump-report.html"
    log ""
    python3 -I "$analyzer" "${analyzer_args[@]}" --html-out "$html_out"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        failed=$exit_code
        continue
    fi
    log ""
    log "✅ HTML report saved: $html_out"
    reports+=("$html_out")
done

for html_out in "${reports[@]}"
do
    # only open a browser in an interactive terminal
    if [[ -t 1 ]] && [ -z "$GITHUB_RUN_NUMBER" ] && command -v open &>/dev/null; then
        log "🌐 Opening $html_out in browser..."
        open "$html_out"
    else
        log "🔗 Open in browser: file://$html_out"
    fi
done

exit $failed
