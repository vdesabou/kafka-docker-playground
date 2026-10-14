heap_file="${args[--file]}"
sample="${args[--sample]}"
output_dir="${args[--output-dir]}"
report_type="${args[--report-type]}"
max_memory="${args[--max-memory]}"
compare_file="${args[--compare]}"

set +e

if [[ -n "$heap_file" && -n "$sample" ]]; then
    logerror "❌ Provide either --file or --sample, not both"
    exit 1
fi
if [[ -z "$heap_file" && -z "$sample" ]]; then
    logerror "❌ Must provide --file <heap dump> (or --sample leak to try it)"
    exit 1
fi

# ── Sample mode: dumps shipped with the analyzer (see tools/heap-analyzer/samples) ──
samples_dir="$root_folder/tools/heap-analyzer/samples"
case "$sample" in
    leak) heap_file="$samples_dir/session-cache-leak-2.hprof.gz" ;;
    leak_growth)
        heap_file="$samples_dir/session-cache-leak-1.hprof.gz"
        compare_file="$samples_dir/session-cache-leak-2.hprof.gz"
    ;;
esac

if [[ ! -f "$heap_file" && $heap_file == *"@"* ]]
then
  heap_file=$(echo "$heap_file" | cut -d "@" -f 2)
fi
if [[ ! -f "$compare_file" && $compare_file == *"@"* ]]
then
  compare_file=$(echo "$compare_file" | cut -d "@" -f 2)
fi

for f in "$heap_file" $compare_file
do
    if [[ ! -f "$f" ]]; then
        logerror "❌ Heap dump file not found: $f"
        exit 1
    fi
done

tools_dir="$root_folder/tools/heap-analyzer"
if [ ! -f "$tools_dir/Dockerfile" ]; then
    logerror "❌ $tools_dir not found"
    exit 1
fi

# ── Analyzer image: Eclipse MAT baked once, scripts mounted at run time ────
# The tag changes when the Dockerfile changes (new MAT version), so the image is rebuilt only then
image="heap-analyzer:$(cksum < "$tools_dir/Dockerfile" | cut -d ' ' -f 1)"
if ! docker image inspect "$image" > /dev/null 2>&1; then
    log "📦 Building $image with Eclipse MAT (first run only, downloads ~100 MB)..."
    build_log=$(mktemp -t heap-analyzer-build-XXXXXXXXXX)
    if ! docker build --load -t "$image" "$tools_dir" > "$build_log" 2>&1 && ! docker build -t "$image" "$tools_dir" >> "$build_log" 2>&1; then
        logerror "❌ Failed to build $image, see $build_log"
        tail -20 "$build_log"
        exit 1
    fi
    rm -f "$build_log"
fi

mkdir -p "$output_dir"
heap_file_abs=$(cd "$(dirname "$heap_file")" && pwd -P)/$(basename "$heap_file")
output_dir_abs=$(cd "$output_dir" && pwd -P)

docker_args=(
    --rm
    --user "$(id -u):$(id -g)"
    -v "$tools_dir:/tools/heap-analyzer:ro"
    -v "$heap_file_abs:/input/$(basename "$heap_file"):ro"
    -v "$output_dir_abs:/output"
)
analyzer_args=(
    --file "/input/$(basename "$heap_file")"
    --output-dir /output
    --report-type "$report_type"
)

if [[ -n "$max_memory" ]]; then
    analyzer_args+=(--max-memory "$max_memory")
fi

if [[ -n "$compare_file" ]]; then
    compare_file_abs=$(cd "$(dirname "$compare_file")" && pwd -P)/$(basename "$compare_file")
    docker_args+=(-v "$compare_file_abs:/compare/$(basename "$compare_file"):ro")
    analyzer_args+=(--compare "/compare/$(basename "$compare_file")")
fi

log "🔬 Analyzing heap dump $heap_file, reports in $output_dir_abs"
docker run "${docker_args[@]}" "$image" "${analyzer_args[@]}"
exit_code=$?

if [ $exit_code -ne 0 ]; then
    logerror "❌ Heap dump analysis failed (exit code $exit_code), MAT log: $output_dir_abs/mat.log"
    exit $exit_code
fi

log "📄 Digest saved in $output_dir_abs/summary.txt"
report="$output_dir_abs/Leak_Suspects/index.html"
[ -f "$report" ] || report=$(ls "$output_dir_abs"/*/index.html 2>/dev/null | head -1)
# only open a browser in an interactive terminal
if [[ -n "$report" && -t 1 ]]; then
    if [[ $(type -f open 2>&1) =~ "not found" ]]
    then
        log "🔗 Cannot open browser, use url: $report"
    else
        log "📊 Opening $report in default browser"
        open "$report"
    fi
fi
