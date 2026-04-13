heap_file="${args[--file]}"
output_dir="${args[--output-dir]}"
report_type="${args[--report-type]}"

set +e

# Check if heap dump file exists
if [[ ! -f "$heap_file" ]]; then
    logerror "❌ Heap dump file not found: $heap_file"
    exit 1
fi

# Create output directory
mkdir -p "$output_dir"

log "🔬 Starting heap dump analysis for: $heap_file"
log "📂 Reports will be saved to: $output_dir"

# Check if heap analyzer container is available
if ! docker images | grep -q "heap-analyzer"; then
    log "📦 Building heap analyzer Docker image..."

    # Build from tools/heap-analyzer directory
    if [ -d "$root_folder/tools/heap-analyzer" ]; then
        if docker build -t heap-analyzer "$root_folder/tools/heap-analyzer" > /tmp/heap-analyzer-build.log 2>&1; then
            log "✅ Heap analyzer image built successfully"
        else
            logerror "❌ Failed to build heap analyzer image"
            log "📋 Check build logs at: /tmp/heap-analyzer-build.log"
            exit 1
        fi
    else
        logerror "❌ tools/heap-analyzer directory not found"
        exit 1
    fi
fi

# Get absolute paths
heap_file_abs=$(cd "$(dirname "$heap_file")" && pwd)/$(basename "$heap_file")
output_dir_abs=$(mkdir -p "$output_dir" && cd "$output_dir" && pwd)

log "📊 Analyzing heap dump..."

# Run heap analysis in Docker container
set -e
if docker run --rm \
    -v "$heap_file_abs:/analysis/heap.hprof:ro" \
    -v "$output_dir_abs:/analysis/output" \
    heap-analyzer \
    --file /analysis/heap.hprof \
    --output-dir /analysis/output \
    --report-type "$report_type" \
    > /tmp/heap-analysis.log 2>&1; then
    log "✅ Analysis complete!"
else
    logwarn "⚠️  Analysis encountered issues (check /tmp/heap-analysis.log)"
fi

# Generate summary
cat > "$output_dir_abs/analysis-summary.txt" << EOF
    Heap Dump Analysis Summary
    ==========================
    Generated: $(date)
    Heap Dump: $(basename "$heap_file")
    File Size: $(du -h "$heap_file" | cut -f1)

    Reports Generated:
    - Location: $output_dir_abs
    - Type: $report_type

    Reports:
    --------
EOF

# List generated files
if [ -f "$output_dir_abs/analysis-report.html" ]; then
    echo "- analysis-report.html (Main report)" >> "$output_dir_abs/analysis-summary.txt"
fi
if [ -f "$output_dir_abs/histogram.txt" ]; then
    echo "- histogram.txt (Heap histogram)" >> "$output_dir_abs/analysis-summary.txt"
fi

cat >> "$output_dir_abs/analysis-summary.txt" << EOF

    Next Steps:
    -----------
    1. Open analysis-report.html in your browser
    2. Review top memory consumers
    3. Check for unexpected object accumulation

    For deeper analysis:
    - Use VisualVM: https://visualvm.github.io/
    - Use Eclipse MAT: https://www.eclipse.org/mat/
EOF

log ""
log "📁 Analysis reports available at:"
log "   $output_dir_abs"
log ""

if [ -f "$output_dir_abs/analysis-report.html" ]; then
    if [[ $(type -f open 2>&1) =~ "not found" ]]
    then
        log "🔗 Cannot open browser, use url:"
        echo "$output_dir_abs/analysis-report.html"
    else
        log "📊 opening report $output_dir_abs/analysis-report.html in default browser"
        open "$output_dir_abs/analysis-report.html"
    fi
else
    logwarn "⚠️  HTML report not generated. Check /tmp/heap-analysis.log:"
    cat /tmp/heap-analysis.log
fi

log ""
log "📄 Summary: $output_dir_abs/analysis-summary.txt"
