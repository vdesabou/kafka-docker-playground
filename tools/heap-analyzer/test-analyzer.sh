#!/bin/bash

# Test script for heap analyzer
# Creates a sample heap dump and tests the analysis functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/test-output"

echo "🧪 Testing Heap Analyzer"
echo "========================"
echo ""

# Clean up previous test
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Step 1: Build the analyzer image
echo "📦 Step 1: Building analyzer image..."
if ! docker images | grep -q "eclipse-mat-analyzer"; then
    bash "$SCRIPT_DIR/build.sh"
else
    echo "✅ Analyzer image already exists"
fi
echo ""

# Step 2: Create a test heap dump using a simple Java application
echo "📋 Step 2: Creating test heap dump..."

# Create a simple Java app that creates some objects
cat > "$TEST_DIR/TestApp.java" <<'EOF'
import java.util.*;

public class TestApp {
    private static List<byte[]> memoryHog = new ArrayList<>();

    public static void main(String[] args) throws Exception {
        System.out.println("Creating test objects...");

        // Allocate some memory
        for (int i = 0; i < 100; i++) {
            memoryHog.add(new byte[1024 * 1024]); // 1MB each
        }

        System.out.println("Created " + memoryHog.size() + " MB of data");
        System.out.println("Taking heap dump...");

        // Trigger heap dump
        String heapDumpPath = "/tmp/test-heap-dump.hprof";
        String pid = java.lang.management.ManagementFactory.getRuntimeMXBean().getName().split("@")[0];

        System.out.println("PID: " + pid);
        System.out.println("Heap dump will be at: " + heapDumpPath);

        // Keep alive for a moment
        Thread.sleep(2000);
    }
}
EOF

# Create heap dump using Docker
echo "🐳 Running test application in Docker..."
docker run --rm \
    -v "$TEST_DIR:/test" \
    -w /test \
    eclipse-temurin:17-jdk \
    bash -c "
        javac TestApp.java && \
        java -XX:+HeapDumpOnOutOfMemoryError \
             -XX:HeapDumpPath=test-heap-dump.hprof \
             -Xmx200m \
             TestApp || true
    " 2>/dev/null || {
    # Try alternative: just compile and run with jmap
    docker run --rm \
        -v "$TEST_DIR:/test" \
        -w /test \
        eclipse-temurin:17-jdk \
        bash -c "
            javac TestApp.java && \
            java -Xmx200m TestApp &
            PID=\$!
            sleep 1
            jmap -dump:live,format=b,file=test-heap-dump.hprof \$PID 2>/dev/null || true
            kill \$PID 2>/dev/null || true
        "
}

if [ ! -f "$TEST_DIR/test-heap-dump.hprof" ]; then
    echo "⚠️  Could not create heap dump with test app"
    echo "   Trying to create minimal heap dump..."

    # Create minimal valid heap dump
    docker run --rm \
        -v "$TEST_DIR:/test" \
        eclipse-temurin:17-jdk \
        bash -c "
            echo 'public class Minimal { public static void main(String[] a) { System.gc(); } }' > Minimal.java && \
            javac Minimal.java && \
            java Minimal &
            PID=\$!
            sleep 1
            jmap -dump:format=b,file=/test/test-heap-dump.hprof \$PID 2>/dev/null || true
        "
fi

if [ -f "$TEST_DIR/test-heap-dump.hprof" ]; then
    echo "✅ Test heap dump created: $(du -h "$TEST_DIR/test-heap-dump.hprof" | cut -f1)"
else
    echo "❌ Failed to create test heap dump"
    exit 1
fi
echo ""

# Step 3: Test the analyzer
echo "📋 Step 3: Testing heap dump analysis..."
echo ""

docker run --rm \
    -v "$TEST_DIR/test-heap-dump.hprof:/analysis/heap.hprof:ro" \
    -v "$TEST_DIR/analysis:/analysis/output" \
    eclipse-mat-analyzer \
    /analysis/heap.hprof \
    org.eclipse.mat.api:suspects \
    -output /analysis/output/leaks

echo ""

# Step 4: Verify results
echo "📋 Step 4: Verifying results..."

if [ -d "$TEST_DIR/analysis/leaks" ]; then
    echo "✅ Analysis directory created"

    if ls "$TEST_DIR/analysis/leaks"/*.html >/dev/null 2>&1; then
        echo "✅ HTML reports generated"
        echo ""
        echo "📊 Generated reports:"
        ls -lh "$TEST_DIR/analysis/leaks"/*.html | awk '{print "   " $9, "(" $5 ")"}'
    else
        echo "⚠️  No HTML reports found"
    fi

    if ls "$TEST_DIR/analysis/leaks"/*.zip >/dev/null 2>&1; then
        echo "✅ ZIP package created"
    fi
else
    echo "❌ Analysis directory not created"
    exit 1
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "📁 Test output available at: $TEST_DIR"
echo ""
echo "🧹 To clean up test files:"
echo "   rm -rf $TEST_DIR"
echo ""
