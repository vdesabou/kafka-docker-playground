#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔨 Building Eclipse MAT Analyzer Docker Image..."
echo ""

docker build -t heap-analyzer "$SCRIPT_DIR"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Successfully built heap-analyzer image"
    echo ""
    echo "📋 Usage examples:"
    echo ""
    echo "  # Via playground CLI (recommended):"
    echo "  playground debug heap-analyze --file heap-dump.hprof"
    echo ""
    echo "  # Direct docker usage:"
    echo "  docker run --rm \\"
    echo "    -v \$(pwd)/heap-dump.hprof:/analysis/heap.hprof:ro \\"
    echo "    -v \$(pwd)/output:/analysis/output \\"
    echo "    heap-analyzer \\"
    echo "    /analysis/heap.hprof \\"
    echo "    org.eclipse.mat.api:suspects \\"
    echo "    -output /analysis/output"
    echo ""
else
    echo ""
    echo "❌ Build failed"
    exit 1
fi
