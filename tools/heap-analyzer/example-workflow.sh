#!/bin/bash

# Example workflow for heap dump analysis in Kafka Docker Playground
# This script demonstrates how to collect and analyze heap dumps

set -e

echo "🎯 Heap Dump Analysis Workflow Example"
echo "======================================="
echo ""

# Step 1: Check if playground is running
echo "📋 Step 1: Checking playground containers..."
if ! docker ps | grep -q "connect"; then
    echo "❌ No 'connect' container found. Please start a playground example first."
    echo ""
    echo "Example: cd connect/connect-filestream-sink && ./filestream-sink.sh"
    exit 1
fi

echo "✅ Found running containers"
echo ""

# Step 2: Take a heap dump
echo "📋 Step 2: Taking heap dump from connect container..."
playground debug heap-dump --container connect --live

# Find the most recent heap dump
HEAP_FILE=$(ls -t heap-dump-connect-*.hprof 2>/dev/null | head -1)

if [ -z "$HEAP_FILE" ]; then
    echo "❌ No heap dump file found"
    exit 1
fi

echo "✅ Heap dump created: $HEAP_FILE"
echo "   Size: $(du -h "$HEAP_FILE" | cut -f1)"
echo ""

# Step 3: Analyze the heap dump
echo "📋 Step 3: Analyzing heap dump..."
echo ""

playground debug heap-analyze \
    --file "$HEAP_FILE" \
    --output-dir "./heap-analysis-$(date +%Y%m%d-%H%M%S)" \
    --report-type all

echo ""
echo "✅ Analysis complete!"
echo ""
echo "📊 Next steps:"
echo "   1. Review the HTML reports in the output directory"
echo "   2. Check analysis-summary.txt for quick overview"
echo "   3. Look for leak suspects and high memory consumers"
echo ""
echo "💡 Tips:"
echo "   - If you see unexpected memory usage, check leak suspects report"
echo "   - Compare heap dumps before/after operations to track memory growth"
echo "   - Use thread dumps to correlate memory issues with thread activity"
echo ""
