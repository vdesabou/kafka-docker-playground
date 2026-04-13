#!/bin/bash

set -e

# Simple heap dump analyzer using JDK tools
# Generates HTML reports with histogram and basic analysis

HEAP_FILE=""
OUTPUT_DIR="/analysis/output"
REPORT_TYPE="all"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --file|-f)
            HEAP_FILE="$2"
            shift 2
            ;;
        --output-dir|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --report-type|-r)
            REPORT_TYPE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Heap Dump Analyzer"
            echo ""
            echo "Usage: analyze-heap --file HEAP_FILE [options]"
            echo ""
            echo "Options:"
            echo "  --file, -f FILE          Heap dump file (.hprof)"
            echo "  --output-dir, -o DIR     Output directory (default: /analysis/output)"
            echo "  --report-type, -r TYPE   Report type: all, leaks, overview, top-components"
            echo "  --help, -h               Show this help"
            exit 0
            ;;
        *)
            HEAP_FILE="$1"
            shift
            ;;
    esac
done

if [[ -z "$HEAP_FILE" || ! -f "$HEAP_FILE" ]]; then
    echo "Error: Heap dump file required"
    echo "Usage: analyze-heap --file HEAP_FILE"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Analyzing heap dump: $HEAP_FILE"
echo "Output directory: $OUTPUT_DIR"
echo "Report type: $REPORT_TYPE"
echo ""

# Generate heap histogram using Python parser
echo "Generating heap histogram..."

if python3 /usr/local/bin/parse_hprof.py "$HEAP_FILE" "$OUTPUT_DIR/histogram.txt" 2>&1; then
    echo "✅ Histogram generated successfully"
else
    echo "⚠️ Warning: Could not parse heap dump"
    echo "Heap dump file: $(basename "$HEAP_FILE")" > "$OUTPUT_DIR/histogram.txt"
    echo "Size: $(du -h "$HEAP_FILE" | cut -f1)" >> "$OUTPUT_DIR/histogram.txt"
    echo "" >> "$OUTPUT_DIR/histogram.txt"
    echo "For detailed analysis, please use:" >> "$OUTPUT_DIR/histogram.txt"
    echo "  - Eclipse MAT: https://www.eclipse.org/mat/" >> "$OUTPUT_DIR/histogram.txt"
    echo "  - VisualVM: https://visualvm.github.io/" >> "$OUTPUT_DIR/histogram.txt"
fi

# Create HTML report
cat > "$OUTPUT_DIR/analysis-report.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Heap Dump Analysis Report</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 20px;
        }
        .section {
            background: white;
            padding: 20px;
            margin: 20px 0;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1, h2 {
            margin-top: 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e0e0e0;
        }
        th {
            background: #f8f9fa;
            font-weight: 600;
        }
        tr:hover {
            background: #f8f9fa;
        }
        .metric {
            display: inline-block;
            background: #e3f2fd;
            padding: 15px 20px;
            margin: 10px;
            border-radius: 8px;
            border-left: 4px solid #2196f3;
        }
        .metric-label {
            font-size: 12px;
            color: #666;
            text-transform: uppercase;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            color: #1976d2;
        }
        pre {
            background: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
            font-size: 13px;
        }
        .warning {
            background: #fff3e0;
            border-left: 4px solid #ff9800;
            padding: 15px;
            margin: 10px 0;
            border-radius: 4px;
        }
        .tip {
            background: #e8f5e9;
            border-left: 4px solid #4caf50;
            padding: 15px;
            margin: 10px 0;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔬 Heap Dump Analysis Report</h1>
        <p>Generated: TIMESTAMP</p>
        <p>File: HEAP_FILE_NAME</p>
    </div>
EOF

# Add file info to HTML
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
FILE_SIZE=$(du -h "$HEAP_FILE" | cut -f1)
FILE_NAME=$(basename "$HEAP_FILE")

sed -i "s/TIMESTAMP/$TIMESTAMP/g" "$OUTPUT_DIR/analysis-report.html"
sed -i "s/HEAP_FILE_NAME/$FILE_NAME ($FILE_SIZE)/g" "$OUTPUT_DIR/analysis-report.html"

# Parse histogram and add top consumers
if [[ -f "$OUTPUT_DIR/histogram.txt" ]]; then
    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'

    <div class="section">
        <h2>📊 Top Memory Consumers</h2>
        <p>Classes consuming the most memory in the heap:</p>
        <table>
            <thead>
                <tr>
                    <th>#</th>
                    <th>Class Name</th>
                    <th>Instances</th>
                    <th>Bytes</th>
                </tr>
            </thead>
            <tbody>
EOF

    # Extract top 20 entries from histogram (skip header lines)
    grep -E '^\s+[0-9]+:' "$OUTPUT_DIR/histogram.txt" | head -20 | while IFS= read -r line; do
        # Parse the line: "   1:         12345        1234567  ClassName"
        num=$(echo "$line" | awk '{print $1}' | tr -d ':')
        instances=$(echo "$line" | awk '{print $2}')
        bytes=$(echo "$line" | awk '{print $3}')
        classname=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed 's/^[[:space:]]*//')

        # Format bytes
        if [[ $bytes -gt 1073741824 ]]; then
            size=$(awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}")
        elif [[ $bytes -gt 1048576 ]]; then
            size=$(awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}")
        elif [[ $bytes -gt 1024 ]]; then
            size=$(awk "BEGIN {printf \"%.2f KB\", $bytes/1024}")
        else
            size="$bytes B"
        fi

        echo "                <tr>"
        echo "                    <td>$num</td>"
        echo "                    <td><code>$classname</code></td>"
        echo "                    <td>$(printf "%'d" $instances 2>/dev/null || echo $instances)</td>"
        echo "                    <td>$size</td>"
        echo "                </tr>"
    done >> "$OUTPUT_DIR/analysis-report.html"

    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
            </tbody>
        </table>
    </div>
EOF

    # Add statistics
    total_instances=$(grep "Total" "$OUTPUT_DIR/histogram.txt" | awk '{print $2}' | head -1)
    total_bytes=$(grep "Total" "$OUTPUT_DIR/histogram.txt" | awk '{print $3}' | head -1)

    if [[ -n "$total_bytes" ]]; then
        if [[ $total_bytes -gt 1073741824 ]]; then
            total_size=$(awk "BEGIN {printf \"%.2f GB\", $total_bytes/1073741824}")
        elif [[ $total_bytes -gt 1048576 ]]; then
            total_size=$(awk "BEGIN {printf \"%.2f MB\", $total_bytes/1048576}")
        else
            total_size=$(awk "BEGIN {printf \"%.2f KB\", $total_bytes/1024}")
        fi

        cat >> "$OUTPUT_DIR/analysis-report.html" <<EOF

    <div class="section">
        <h2>📈 Heap Statistics</h2>
        <div class="metric">
            <div class="metric-label">Total Instances</div>
            <div class="metric-value">$(printf "%'d" $total_instances 2>/dev/null || echo $total_instances)</div>
        </div>
        <div class="metric">
            <div class="metric-label">Total Size</div>
            <div class="metric-value">$total_size</div>
        </div>
    </div>
EOF
    fi
fi

# Analyze histogram and generate dynamic insights
INSIGHTS_FILE="$OUTPUT_DIR/.insights.tmp"
WARNINGS_FILE="$OUTPUT_DIR/.warnings.tmp"
SUSPECT_FILE="$OUTPUT_DIR/.suspects.tmp"
> "$INSIGHTS_FILE"
> "$WARNINGS_FILE"
> "$SUSPECT_FILE"

if [[ -f "$OUTPUT_DIR/histogram.txt" ]]; then
    # Get total bytes for percentage calculations
    total_bytes=$(grep "^Total:" "$OUTPUT_DIR/histogram.txt" | awk '{print $3}' | tr -d ',' || echo "0")

    # Analyze top 50 entries
    grep -E '^\s+[0-9]+:' "$OUTPUT_DIR/histogram.txt" | head -50 | while IFS= read -r line; do
        instances=$(echo "$line" | awk '{print $2}')
        bytes=$(echo "$line" | awk '{print $3}')
        classname=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed 's/^[[:space:]]*//')

        # Calculate percentage of total heap
        if [[ $total_bytes -gt 0 ]]; then
            pct=$(awk "BEGIN {printf \"%.1f\", ($bytes/$total_bytes)*100}")
        else
            pct="0"
        fi

        # Detect patterns and generate insights

        # Large byte arrays (with percentage)
        if [[ "$classname" == "byte[]" && $bytes -gt 10485760 ]]; then
            size_mb=$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")
            if [[ $(awk "BEGIN {print ($pct > 20)}") -eq 1 ]]; then
                echo "<li>🔴 <strong>Large byte arrays detected:</strong> ${size_mb} MB (${pct}%) across $(printf "%'d" $instances 2>/dev/null || echo $instances) instances. This is significant - verify these are expected buffers/caches.</li>" >> "$INSIGHTS_FILE"
            else
                echo "<li><strong>Byte arrays:</strong> ${size_mb} MB (${pct}%) across $(printf "%'d" $instances 2>/dev/null || echo $instances) instances. Check if these are expected buffers/caches.</li>" >> "$INSIGHTS_FILE"
            fi
        fi

        # High String/char[] count
        if [[ "$classname" == "java/lang/String" ]]; then
            if [[ $instances -gt 100000 ]]; then
                echo "<li><strong>High String count:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) String objects (${pct}% of heap). Consider string interning or deduplication.</li>" >> "$INSIGHTS_FILE"
            elif [[ $(awk "BEGIN {print ($pct > 10)}") -eq 1 ]]; then
                echo "<li><strong>String overhead:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) String objects consuming ${pct}% of heap.</li>" >> "$INSIGHTS_FILE"
            fi
        fi

        if [[ "$classname" == "char[]" && $instances -gt 50000 ]]; then
            echo "<li><strong>Many char arrays:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) instances. May indicate string duplication.</li>" >> "$INSIGHTS_FILE"
        fi

        # Detect custom classes (potential leak suspects)
        # Exclude: Java standard libs, Kafka, Confluent, arrays, and primitive types
        if [[ ! "$classname" =~ ^(java/|javax/|sun/|jdk/|org/apache/kafka/|io/confluent/|\[|byte\[\]|int\[\]|long\[\]|char\[\]|short\[\]|float\[\]|double\[\]|boolean\[\]) ]]; then
            # Custom class not from standard libraries
            if [[ $instances -gt 1000 || $(awk "BEGIN {print ($pct > 5)}") -eq 1 ]]; then
                size_mb=$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")
                echo "<li>⚠️ <strong>Custom class accumulation:</strong> <code>$classname</code> has $(printf "%'d" $instances 2>/dev/null || echo $instances) instances (${size_mb} MB, ${pct}%). Review for memory leaks.</li>" >> "$SUSPECT_FILE"
            fi
        fi

        # Collection warnings
        if [[ "$classname" =~ HashMap.*Node ]]; then
            if [[ $instances -gt 100000 ]]; then
                size_mb=$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")
                echo "<li><strong>Large HashMap detected:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) nodes (${size_mb} MB, ${pct}%). Verify expected size.</li>" >> "$WARNINGS_FILE"
            elif [[ $(awk "BEGIN {print ($pct > 15)}") -eq 1 ]]; then
                size_mb=$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")
                echo "<li><strong>HashMap nodes:</strong> ${pct}% of heap (${size_mb} MB). Check if maps are growing unbounded.</li>" >> "$WARNINGS_FILE"
            fi
        fi

        if [[ "$classname" =~ ArrayList && $instances -gt 50000 ]]; then
            echo "<li><strong>Many ArrayList instances:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) found. Ensure lists are properly cleared.</li>" >> "$WARNINGS_FILE"
        fi

        if [[ "$classname" =~ ConcurrentHashMap && $instances -gt 10000 ]]; then
            echo "<li><strong>Many ConcurrentHashMap instances:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) found. May indicate cache proliferation.</li>" >> "$WARNINGS_FILE"
        fi

        # Thread-related
        if [[ "$classname" == "java/lang/Thread" && $instances -gt 100 ]]; then
            echo "<li>⚠️ <strong>High thread count:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) Thread objects. Check for thread leaks or unbounded thread pools.</li>" >> "$WARNINGS_FILE"
        fi

        if [[ "$classname" =~ ThreadLocal ]]; then
            echo "<li><strong>ThreadLocal usage detected:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) instances. Verify ThreadLocals are cleaned up properly.</li>" >> "$WARNINGS_FILE"
        fi

        # Kafka-specific
        if [[ "$classname" =~ kafka.*Record && ! "$classname" =~ RecordMetadata ]]; then
            size_mb=$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")
            echo "<li><strong>Kafka Records in heap:</strong> <code>$classname</code> - $(printf "%'d" $instances 2>/dev/null || echo $instances) instances (${size_mb} MB). Check consumer commit/poll frequency.</li>" >> "$WARNINGS_FILE"
        fi

        if [[ "$classname" =~ BoundedConcurrentHashMap.*HashEntry ]]; then
            size_mb=$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")
            if [[ $(awk "BEGIN {print ($pct > 5)}") -eq 1 ]]; then
                echo "<li><strong>Schema Registry cache:</strong> ${size_mb} MB (${pct}%) in schema cache. Consider tuning cache size limits.</li>" >> "$WARNINGS_FILE"
            fi
        fi

        if [[ "$classname" =~ connect.*Task ]]; then
            echo "<li><strong>Connect Tasks:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) task instances. Verify proper cleanup on reconfiguration.</li>" >> "$WARNINGS_FILE"
        fi

        # Couchbase-specific
        if [[ "$classname" =~ couchbase ]]; then
            size_mb=$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")
            echo "<li><strong>Couchbase objects:</strong> <code>$classname</code> - ${size_mb} MB (${pct}%). Monitor connection pool and buffer usage.</li>" >> "$WARNINGS_FILE"
        fi

        # Netty buffers
        if [[ "$classname" =~ netty.*ByteBuf ]]; then
            size_mb=$(awk "BEGIN {printf \"%.1f\", $bytes/1048576}")
            echo "<li><strong>Netty buffers:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) ByteBuf instances (${size_mb} MB). Check for buffer leaks - ensure .release() is called.</li>" >> "$WARNINGS_FILE"
        fi

        # Metrics
        if [[ "$classname" =~ Metric && $instances -gt 10000 ]]; then
            echo "<li><strong>High metric count:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) metric objects (${pct}% of heap). Review JMX metric retention.</li>" >> "$WARNINGS_FILE"
        fi

        if [[ "$classname" =~ KafkaMetric ]]; then
            echo "<li><strong>Kafka metrics:</strong> $(printf "%'d" $instances 2>/dev/null || echo $instances) KafkaMetric objects. Check if metric reporters are consuming excessive memory.</li>" >> "$WARNINGS_FILE"
        fi
    done
fi

# Generate dynamic analysis section
cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'

    <div class="section">
        <h2>💡 Heap Analysis Insights</h2>
EOF

# Add leak suspects if any
if [[ -s "$SUSPECT_FILE" ]]; then
    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
        <div class="warning" style="border-left-color: #f44336; background: #ffebee;">
            <strong>🔴 Potential Memory Leak Suspects:</strong>
            <ul>
EOF
    cat "$SUSPECT_FILE" >> "$OUTPUT_DIR/analysis-report.html"
    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
            </ul>
            <p style="margin-top: 10px; font-size: 13px; color: #666;">
                <strong>💡 Tip:</strong> Take another heap dump after reproducing the issue and compare object counts. Growing instances indicate a leak.
            </p>
        </div>
EOF
fi

# Add specific findings if any
if [[ -s "$INSIGHTS_FILE" ]]; then
    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
        <div class="tip">
            <strong>🔍 Key Findings:</strong>
            <ul>
EOF
    cat "$INSIGHTS_FILE" >> "$OUTPUT_DIR/analysis-report.html"
    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
            </ul>
        </div>
EOF
fi

# Add warnings if any
if [[ -s "$WARNINGS_FILE" ]]; then
    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
        <div class="warning">
            <strong>⚠️ Items to Review:</strong>
            <ul>
EOF
    cat "$WARNINGS_FILE" >> "$OUTPUT_DIR/analysis-report.html"
    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
            </ul>
        </div>
EOF
fi

# If nothing found, show all clear message
if [[ ! -s "$SUSPECT_FILE" && ! -s "$INSIGHTS_FILE" && ! -s "$WARNINGS_FILE" ]]; then
    cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
        <div class="tip">
            <strong>✅ Heap looks healthy</strong>
            <p>No unusual patterns detected in the top memory consumers. Memory distribution appears normal for the application type.</p>
        </div>
EOF
fi

# Add general tips based on what's in the heap
cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'
        <div class="tip">
            <strong>💡 General Recommendations:</strong>
            <ul>
                <li>Compare this heap dump with previous dumps to identify growth trends</li>
                <li>Use <code>playground debug thread-dump</code> to correlate memory usage with thread activity</li>
                <li>For deeper analysis, open this .hprof file in Eclipse MAT or VisualVM</li>
                <li>Monitor heap usage over time to detect slow memory leaks</li>
            </ul>
        </div>
    </div>
EOF

# Cleanup temp files
rm -f "$INSIGHTS_FILE" "$WARNINGS_FILE" "$SUSPECT_FILE"

cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'

    <div class="section">
        <h2>🛠️ Next Steps</h2>
        <ol>
            <li>Review the top memory consumers table above</li>
            <li>Check if sizes are expected for your workload</li>
            <li>For detailed analysis, use:
                <ul>
                    <li><a href="https://visualvm.github.io/" target="_blank">VisualVM</a> - Interactive heap browser</li>
                    <li><a href="https://www.eclipse.org/mat/" target="_blank">Eclipse MAT</a> - Advanced leak detection</li>
                </ul>
            </li>
            <li>Compare multiple heap dumps over time to identify growth patterns</li>
            <li>Use <code>playground debug thread-dump</code> to correlate with thread activity</li>
        </ol>
    </div>

    <div class="section">
        <h2>📄 Raw Histogram</h2>
        <p>Full heap histogram output:</p>
        <a href="histogram.txt" target="_blank">View histogram.txt</a>
    </div>
</body>
</html>
EOF

echo ""
echo "✅ Analysis complete!"
echo ""
echo "📊 Reports generated:"
echo "   - HTML Report: $OUTPUT_DIR/analysis-report.html"
echo "   - Histogram: $OUTPUT_DIR/histogram.txt"
echo ""
echo "💡 Open the HTML report in your browser for interactive analysis"
