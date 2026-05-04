gc_file="${args[--file]}"
container="${args[--container]}"
output_dir="${args[--output-dir]}"
html="${args[--html]}"
json_out="${args[--json]}"
top_pauses="${args[--top-pauses]}"

set +e

# ── Validate input: need --file OR --container ─────────────────────────────
if [[ -z "$gc_file" && -z "$container" ]]; then
    logerror "❌ Must provide either --file <gc-log-file> or --container <name>"
    log ""
    log "Examples:"
    log "  playground debug gc-analyze --file kafkaServer-gc.log"
    log "  playground debug gc-analyze --container broker"
    exit 1
fi

if [[ -n "$gc_file" && -n "$container" ]]; then
    logerror "❌ Provide either --file or --container, not both"
    exit 1
fi

# ── Locate the analyzer script ─────────────────────────────────────────────
analyzer="$root_folder/gc-analysis/gc_log_analyzer.py"
if [[ ! -f "$analyzer" ]]; then
    logerror "❌ GC analyzer not found at: $analyzer"
    logerror "   Make sure gc-analysis/gc_log_analyzer.py exists in the playground root"
    exit 1
fi

# ── Check Python3 ──────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    logerror "❌ python3 is required but not found on PATH"
    exit 1
fi

# ── Container mode: find and extract the GC log ───────────────────────────
if [[ -n "$container" ]]; then
    log "🐳 Looking for GC log in container: $container"

    # 1. Try to read the GC log path from -Xlog:gc*:file=<path> (JDK 9+)
    gc_log_path=$(docker exec "$container" sh -c \
        "ps aux 2>/dev/null | grep -oP '(?<=-Xlog:gc\*:file=)[^:]+' | head -1" 2>/dev/null)

    # 2. Try legacy -Xloggc:<path> flag (JDK 8)
    if [[ -z "$gc_log_path" ]]; then
        gc_log_path=$(docker exec "$container" sh -c \
            "ps aux 2>/dev/null | grep -oP '(?<=-Xloggc:)\S+' | head -1" 2>/dev/null)
    fi

    # 3. Try -Xlog:gc:file=<path> (simpler unified log variant)
    if [[ -z "$gc_log_path" ]]; then
        gc_log_path=$(docker exec "$container" sh -c \
            "ps aux 2>/dev/null | grep -oP '(?<=-Xlog:gc:file=)[^:]+' | head -1" 2>/dev/null)
    fi

    # 4. Fallback: search common locations
    if [[ -z "$gc_log_path" ]]; then
        log "🔍 No -Xlog/Xloggc flag found, searching common log locations..."
        gc_log_path=$(docker exec "$container" sh -c \
            "find /tmp /var/log /opt /var/log/kafka /etc/kafka 2>/dev/null \
             \( -name '*gc*.log' -o -name 'kafkaServer-gc.log' -o -name 'zookeeper-gc.log' \
                -o -name 'connect-gc.log' -o -name 'schema-registry-gc.log' \) \
             -type f | head -1" 2>/dev/null)
    fi

    if [[ -z "$gc_log_path" ]]; then
        logerror "❌ Could not locate a GC log in container '$container'"
        log ""
        log "💡 To enable GC logging, add these JVM flags:"
        log "   JDK 9+: -Xlog:gc*:file=/tmp/gc.log:time,uptime,level,tags:filecount=5,filesize=20m"
        log "   JDK 8:  -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:/tmp/gc.log"
        log ""
        log "   For Kafka, set in KAFKA_JVM_PERFORMANCE_OPTS or KAFKA_HEAP_OPTS"
        exit 1
    fi

    log "📄 Found GC log: $gc_log_path"

    tmp_gc_file="/tmp/gc-log-${container}-$(date '+%Y%m%d-%H%M%S').log"
    if ! docker cp "${container}:${gc_log_path}" "$tmp_gc_file" 2>/dev/null; then
        logerror "❌ Failed to copy GC log from container '$container'"
        exit 1
    fi

    log "✅ GC log copied to: $tmp_gc_file"
    gc_file="$tmp_gc_file"
fi

# Handle fzf @path trick
if [[ $gc_file == *"@"* ]]; then
    gc_file=$(echo "$gc_file" | cut -d "@" -f 2)
fi

log "📈 Analyzing GC log: $gc_file"
log ""

# ── JSON mode: print and exit ──────────────────────────────────────────────
if [[ -n "$json_out" ]]; then
    python3 "$analyzer" "$gc_file" --json --top-pauses "$top_pauses"
    exit $?
fi

# ── Text analysis ──────────────────────────────────────────────────────────
python3 "$analyzer" "$gc_file" --top-pauses "$top_pauses"
text_exit=$?

# ── HTML report ────────────────────────────────────────────────────────────
if [[ -n "$html" && $text_exit -eq 0 ]]; then
    mkdir -p "$output_dir"
    output_dir_abs=$(cd "$output_dir" && pwd)

    basename_noext=$(basename "$gc_file" .log)
    html_out="${output_dir_abs}/${basename_noext}-gc-report.html"

    log ""
    log "🌐 Generating HTML report..."
    python3 "$analyzer" "$gc_file" --html-out "$html_out" --top-pauses "$top_pauses" > /dev/null 2>&1
    html_exit=$?

    if [[ $html_exit -eq 0 && -f "$html_out" ]]; then
        log "✅ HTML report saved: $html_out"
        log ""
        if command -v open &>/dev/null; then
            log "🌐 Opening report in browser..."
            open "$html_out"
        else
            log "🔗 Open in browser: file://$html_out"
        fi
    else
        logwarn "⚠️  HTML report generation failed"
    fi
fi

exit $text_exit
