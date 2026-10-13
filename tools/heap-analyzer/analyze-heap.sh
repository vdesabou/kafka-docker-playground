#!/bin/bash
#
# Entrypoint of the heap-analyzer image: runs Eclipse Memory Analyzer (MAT) headless on a heap dump,
# then prints a text digest (leak suspects, biggest retained sizes) with digest.py.
#
# Usage: analyze-heap.sh --file /input/<dump.hprof[.gz]> --output-dir /output
#                        [--report-type all|leaks|overview|top-components] [--max-memory 8g]
#                        [--compare /compare/<dump.hprof[.gz]>]
#
# Exit codes: 0 analysis done, 2 MAT could not parse a dump, 1 usage error.

set -o pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEAP_FILE=""
OUTPUT_DIR="/output"
REPORT_TYPE="all"
MAX_MEMORY=""
COMPARE_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --file|-f) HEAP_FILE="$2"; shift 2 ;;
        --output-dir|-o) OUTPUT_DIR="$2"; shift 2 ;;
        --report-type|-r) REPORT_TYPE="$2"; shift 2 ;;
        --max-memory) MAX_MEMORY="$2"; shift 2 ;;
        --compare) COMPARE_FILE="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "❌ Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$HEAP_FILE" || ! -f "$HEAP_FILE" ]]; then
    echo "❌ Heap dump file not found: $HEAP_FILE"
    exit 1
fi
if [[ -n "$COMPARE_FILE" && ! -f "$COMPARE_FILE" ]]; then
    echo "❌ Heap dump file to compare not found: $COMPARE_FILE"
    exit 1
fi

case "$REPORT_TYPE" in
    all) REPORTS=(org.eclipse.mat.api:suspects org.eclipse.mat.api:overview org.eclipse.mat.api:top_components) ;;
    leaks) REPORTS=(org.eclipse.mat.api:suspects) ;;
    overview) REPORTS=(org.eclipse.mat.api:overview) ;;
    top-components) REPORTS=(org.eclipse.mat.api:top_components) ;;
    *) echo "❌ Unknown report type: $REPORT_TYPE"; exit 1 ;;
esac

mkdir -p "$OUTPUT_DIR/queries"
MAT_LOG="$OUTPUT_DIR/mat.log"
: > "$MAT_LOG"

# MAT needs roughly as much heap as the used heap of the dump (1 to 1.5x the file size)
if [[ -n "$MAX_MEMORY" ]]; then
    JVM_MEMORY="-Xmx$MAX_MEMORY"
    memory_label="$MAX_MEMORY"
else
    JVM_MEMORY="-XX:MaxRAMPercentage=80"
    limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
    if [[ -z "$limit" || "$limit" == "max" ]]; then
        limit=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) * 1024 ))
    fi
    available=$(( limit * 80 / 100 ))
    memory_label="$(( available / 1024 / 1024 )) MB (80% of the container memory)"
    for f in "$HEAP_FILE" $COMPARE_FILE; do
        size=$(stat -c %s "$f")
        if [[ "$f" != *.gz && $size -gt $available ]]; then
            echo "⚠️  $(basename "$f") is $(( size / 1024 / 1024 )) MB, more than the $(( available / 1024 / 1024 )) MB MAT can use: it may fail with OutOfMemoryError."
            echo "   Raise the Docker memory or pass --max-memory (e.g. --max-memory $(( size * 3 / 2 / 1024 / 1024 / 1024 + 1 ))g)."
        fi
    done
fi

# $1: dump (symlink in a writable work dir, MAT writes its indexes and reports next to it), then MAT arguments
run_mat() {
    local dump="$1"; shift
    java $JVM_MEMORY -Dosgi.locking=none -Duser.home=/tmp \
        -jar /opt/mat/launcher.jar -consolelog -nosplash -data /tmp/mat-workspace -configuration /tmp/mat-configuration \
        -application org.eclipse.mat.api.parse "$dump" "$@" >> "$MAT_LOG" 2>&1
}

# $1: dump, $2: query command, $3: output name
run_query() {
    local dump="$1" command="$2" name="$3"
    local base="${dump%.gz}"; base="${base%.hprof}"
    rm -rf "${base}_Query" "${base}_Query.zip"
    if ! run_mat "$dump" -format=txt -unzip "-command=$command" org.eclipse.mat.api:query; then
        return 1
    fi
    local txt
    txt=$(find "${base}_Query" -name '*.txt' | head -1)
    [[ -n "$txt" ]] && cp "$txt" "$OUTPUT_DIR/queries/$name.txt"
}

fail_parse() {
    echo ""
    echo "❌ Eclipse MAT could not analyze $(basename "$1")."
    grep -E 'SnapshotException|OutOfMemoryError|Caused by|Exception:' "$MAT_LOG" | grep -v '^\s*at ' | sort -u | head -8 | sed 's/^/   /'
    if grep -q 'OutOfMemoryError' "$MAT_LOG"; then
        echo "💡 MAT ran out of memory: raise the Docker memory or pass --max-memory."
    elif grep -q 'violation of the HPROF specification' "$MAT_LOG"; then
        echo "💡 The dump is probably truncated (copy or jmap interrupted, disk full): take a new one."
    fi
    echo "📋 Full MAT log: mat.log in the output directory"
    exit 2
}

# $1: dump path, $2: work dir name; prints the symlink path
prepare_dump() {
    local src="$1" work="/tmp/work/$2"
    mkdir -p "$work"
    local name="heap.hprof"
    [[ "$src" == *.gz ]] && name="heap.hprof.gz"
    ln -sf "$src" "$work/$name"
    echo "$work/$name"
}

start=$(date +%s)
elapsed() { echo "$(( $(date +%s) - start ))s"; }

dump=$(prepare_dump "$HEAP_FILE" main)
echo "🔬 Eclipse MAT ${MAT_VERSION}: parsing $(basename "$HEAP_FILE") ($(du -h "$HEAP_FILE" | cut -f1)), MAT heap $memory_label"
echo "⏳ Building indexes and the ${REPORT_TYPE} report(s), this takes about 1 minute per GB of dump..."
run_mat "$dump" "${REPORTS[@]}" || fail_parse "$HEAP_FILE"

echo "⏳ Computing retained sizes by class ($(elapsed))..."
run_query "$dump" "dominator_tree -groupBy BY_CLASS" dominator_by_class || fail_parse "$HEAP_FILE"
run_query "$dump" "heap_dump_overview" overview || fail_parse "$HEAP_FILE"

if [[ -n "$COMPARE_FILE" ]]; then
    run_query "$dump" "histogram" histogram || fail_parse "$HEAP_FILE"
    compare_dump=$(prepare_dump "$COMPARE_FILE" compare)
    echo "⏳ Parsing $(basename "$COMPARE_FILE") to compare ($(elapsed))..."
    run_query "$compare_dump" "histogram" compare_histogram || fail_parse "$COMPARE_FILE"
    run_query "$compare_dump" "heap_dump_overview" compare_overview || fail_parse "$COMPARE_FILE"
fi

# Unzip the HTML reports next to their zip
for zip in /tmp/work/main/heap_*.zip; do
    [[ -f "$zip" ]] || continue
    [[ "$zip" == *_Query.zip ]] && continue
    name=$(basename "$zip" .zip)
    name="${name#heap_}"
    rm -rf "${OUTPUT_DIR:?}/$name"
    mkdir -p "$OUTPUT_DIR/$name"
    unzip -q -o "$zip" -d "$OUTPUT_DIR/$name"
    cp "$zip" "$OUTPUT_DIR/$name.zip"
done

echo "✅ Analysis done in $(elapsed)"
echo ""
python3 -I "$TOOLS_DIR/digest.py" --output-dir "$OUTPUT_DIR" --heap-file "$(basename "$HEAP_FILE")" \
    ${COMPARE_FILE:+--compare-file "$(basename "$COMPARE_FILE")"} | tee "$OUTPUT_DIR/summary.txt"
