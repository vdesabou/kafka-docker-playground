# Heap Analyzer - Quick Start Guide

Get started with heap dump analysis in 3 simple steps!

## Prerequisites

- Docker installed and running
- Kafka Docker Playground environment running
- Playground CLI installed

## Quick Start

### 1. Capture a Heap Dump

```bash
# Take heap dump from any container (e.g., connect, broker, schema-registry)
playground debug heap-dump --container connect --live
```

This creates a `.hprof` file in your current directory, e.g., `heap-dump-connect-2026-04-08-12-30-45.hprof`

### 2. Analyze the Heap Dump

```bash
# Analyze the heap dump (generates all reports)
playground debug heap-analyze --file heap-dump-connect-*.hprof
```

Or specify report type:

```bash
# Just leak suspects
playground debug heap-analyze --file heap-dump-connect-*.hprof --report-type leaks

# System overview
playground debug heap-analyze --file heap-dump-connect-*.hprof --report-type overview

# Top memory consumers
playground debug heap-analyze --file heap-dump-connect-*.hprof --report-type top-components
```

### 3. Review the Reports

```bash
# Open the HTML report in your browser
open heap-analysis/suspects_Leak_Suspects.html

# Or check the summary
cat heap-analysis/analysis-summary.txt
```

## Common Use Cases

### Memory Leak Investigation

```bash
# 1. Take baseline heap dump
playground debug heap-dump --container connect --live
mv heap-dump-connect-*.hprof baseline.hprof

# 2. Run your workload / reproduce the issue
# ... wait for memory to grow ...

# 3. Take another heap dump
playground debug heap-dump --container connect --live
mv heap-dump-connect-*.hprof after-leak.hprof

# 4. Analyze for leaks
playground debug heap-analyze --file after-leak.hprof --report-type leaks --output-dir leak-analysis

# 5. Review leak suspects
open leak-analysis/suspects_Leak_Suspects.html
```

### High Memory Usage

```bash
# Take heap dump when memory is high
playground debug heap-dump --container broker --live

# Analyze top consumers
playground debug heap-analyze \
  --file heap-dump-broker-*.hprof \
  --report-type top-components \
  --output-dir memory-analysis

# Review what's consuming memory
open memory-analysis/top_components_Component_Report.html
```

### Connector Troubleshooting

```bash
# Get heap histogram first (lightweight)
playground debug heap-dump --container connect --histo

# If you see suspicious patterns, take full dump
playground debug heap-dump --container connect --live

# Analyze with all reports
playground debug heap-analyze --file heap-dump-connect-*.hprof --output-dir connector-analysis
```

## Understanding the Reports

### Leak Suspects Report
**Look for:**
- 🔴 Red flags: Large retained heaps (>50% of total)
- 📍 Accumulation points: Objects holding onto memory
- 🔗 Shortest paths: How objects are referenced

**Common issues:**
- Collection growth (List, Map, Set not cleared)
- Thread locals not cleaned up
- Event listeners not unregistered
- Cache not evicting entries

### Top Components Report
**Look for:**
- 📊 Largest retained heaps
- 🏗️ Object counts (many small objects = overhead)
- 🔄 Duplicate strings/objects

**What's normal:**
- Kafka buffers (producer/consumer)
- Connect framework objects
- Connector instances
- Schema registry cache

**What's suspicious:**
- Unexpectedly large collections
- Many instances of business objects
- Growing number of connections/threads

### System Overview Report
**Check:**
- ✅ Total heap size vs used
- 📈 Number of classes loaded
- 🧵 Number of threads
- 📦 Number of GC roots

## Tips & Tricks

### 1. Use Live Dumps for Accurate Analysis
```bash
# --live triggers a GC before dump (cleaner analysis)
playground debug heap-dump --container connect --live
```

### 2. Take Multiple Snapshots
```bash
# Compare heap growth over time
for i in {1..3}; do
  playground debug heap-dump --container connect --live
  sleep 300  # 5 minutes
done
```

### 3. Combine with Thread Dumps
```bash
# Thread dump shows what's running
playground debug thread-dump --container connect

# Heap dump shows what's in memory
playground debug heap-dump --container connect --live
```

### 4. Check Histogram First (Faster)
```bash
# Quick peek at heap contents (text output)
playground debug heap-dump --container connect --histo --live > heap-histo.txt
less heap-histo.txt
```

## Troubleshooting

### Analysis Takes Too Long
- Large heap dumps can take several minutes to analyze
- Be patient or use `--report-type leaks` for faster single report

### Docker Memory Issues
```bash
# Increase Docker memory limit (in Docker Desktop settings)
# Or run analyzer with more memory:
docker run --memory=8g eclipse-mat-analyzer ...
```

### No Reports Generated
- Check logs: `cat /tmp/mat-analysis-*.log`
- Verify heap dump is valid: `file heap-dump.hprof`
- Try with VisualVM for manual analysis

### Heap Dump Too Large
```bash
# Use histogram instead for quick analysis
playground debug heap-dump --container connect --histo --live
```

## Next Steps

- 📚 Read the [full README](./README.md) for detailed information
- 🧪 Run the [example workflow](./example-workflow.sh)
- 🔬 Try the [test script](./test-analyzer.sh) to verify setup
- 📖 Learn more about [Eclipse MAT](https://www.eclipse.org/mat/)

## Cheat Sheet

```bash
# Complete analysis workflow
playground debug heap-dump --container connect --live
playground debug heap-analyze --file heap-dump-connect-*.hprof
open heap-analysis/suspects_Leak_Suspects.html

# Quick leak check
playground debug heap-analyze --file heap.hprof --report-type leaks

# Memory profiling
playground debug heap-analyze --file heap.hprof --report-type top-components

# Custom output location
playground debug heap-analyze --file heap.hprof --output-dir ./my-analysis
```

## Support

For issues or questions:
1. Check the logs: `/tmp/mat-analysis-*.log` and `/tmp/mat-build.log`
2. Review the [main README](./README.md)
3. Open an issue at [kafka-docker-playground](https://github.com/vdesabou/kafka-docker-playground/issues)
