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

# Generate heap histogram
echo "Generating heap histogram..."
jmap -histo:file="$HEAP_FILE" > "$OUTPUT_DIR/histogram.txt" 2>&1 || {
    echo "Warning: Could not generate histogram with jmap"
}

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

# Add recommendations section
cat >> "$OUTPUT_DIR/analysis-report.html" <<'EOF'

    <div class="section">
        <h2>💡 Analysis Tips</h2>

        <div class="tip">
            <strong>🔍 What to Look For:</strong>
            <ul>
                <li><strong>Large byte arrays</strong> - Check if they're expected (caches, buffers) or unexpected (leaks)</li>
                <li><strong>Many instances of business objects</strong> - May indicate objects not being released</li>
                <li><strong>High char[] or String count</strong> - Possible string duplication or not interning strings</li>
                <li><strong>Collection growth</strong> - Maps, Lists, Sets that are growing unbounded</li>
            </ul>
        </div>

        <div class="warning">
            <strong>⚠️ Common Issues in Kafka/Connect:</strong>
            <ul>
                <li><strong>Kafka Buffers</strong> - Producer/consumer buffers are normal, but watch for growth</li>
                <li><strong>Connect Tasks</strong> - Many connector task instances may indicate tasks not being cleaned up</li>
                <li><strong>Schema Registry Cache</strong> - Normal to have schemas cached, but watch the size</li>
                <li><strong>Metrics</strong> - JMX metrics can accumulate, check if retention is configured</li>
            </ul>
        </div>
    </div>

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
