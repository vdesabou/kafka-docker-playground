# Heap Dump Analyzer

Docker-based Eclipse MAT (Memory Analyzer Tool) for analyzing Java heap dumps in the Kafka Docker Playground.

## Overview

This tool provides automated heap dump analysis using Eclipse MAT in headless mode. It's integrated with the playground CLI through the `playground debug heap-analyze` command.

## Features

- 🔬 **Automated Analysis**: Generate leak suspects, system overview, and top components reports
- 📊 **Multiple Report Types**: HTML and ZIP formatted reports
- 🐳 **Docker-based**: No local installation required
- 🚀 **Integrated**: Works seamlessly with `playground debug heap-dump`

## Usage

### Via Playground CLI (Recommended)

```bash
# Take a heap dump
playground debug heap-dump --container connect

# Analyze the heap dump
playground debug heap-analyze --file heap-dump-connect-2026-04-08-12-30-45.hprof

# Analyze with specific report type
playground debug heap-analyze --file heap-dump-broker.hprof --report-type leaks

# Specify custom output directory
playground debug heap-analyze --file heap.hprof --output-dir ./my-analysis
```

### Direct Docker Usage

```bash
# Build the image
docker build -t eclipse-mat-analyzer tools/heap-analyzer/

# Run analysis
docker run --rm \
  -v $(pwd)/heap-dump.hprof:/analysis/heap.hprof:ro \
  -v $(pwd)/output:/analysis/output \
  eclipse-mat-analyzer \
  /analysis/heap.hprof \
  org.eclipse.mat.api:suspects \
  -output /analysis/output/leaks

# Generate all reports
docker run --rm \
  -v $(pwd)/heap-dump.hprof:/analysis/heap.hprof:ro \
  -v $(pwd)/output:/analysis/output \
  eclipse-mat-analyzer \
  /analysis/heap.hprof \
  org.eclipse.mat.api:suspects \
  org.eclipse.mat.api:overview \
  org.eclipse.mat.api:top_components \
  -output /analysis/output
```

## Available Report Types

### Leak Suspects (`leaks`)
Analyzes potential memory leaks and provides suspects with detailed explanations.

**Generated files:**
- `leaks_Leak_Suspects.html` - Main leak suspects report
- `leaks.zip` - Complete analysis package

### System Overview (`overview`)
Provides comprehensive overview of heap usage, class statistics, and object distribution.

**Generated files:**
- `overview_System_Overview.html` - System overview report
- `overview.zip` - Complete analysis package

### Top Components (`top-components`)
Shows the largest memory consumers and component breakdown.

**Generated files:**
- `top_components_Component_Report.html` - Top components report
- `top_components.zip` - Complete analysis package

## Report Interpretation

### Leak Suspects Report
- **Problem Suspect**: Areas where large amounts of memory are retained
- **Shortest Paths to Accumulation Point**: How objects are retained
- **Accumulated Objects**: What objects are consuming memory
- **Thread Details**: Which threads are involved

### Top Components Report
- **Retained Heap**: Memory held by component and its dependencies
- **Shallow Heap**: Memory used by the component itself
- **Objects Count**: Number of instances

## Memory Requirements

The analyzer requires sufficient memory to process heap dumps:
- Default JVM heap: 4GB (`-Xmx4g`)
- For larger dumps (>2GB), consider increasing memory in the Dockerfile

## Integration with Playground Workflow

### Complete Debugging Workflow

```bash
# 1. Enable remote debugging (optional)
playground debug enable-remote-debugging --container connect

# 2. Take thread dump to see what's running
playground debug thread-dump --container connect

# 3. Take heap dump
playground debug heap-dump --container connect --live

# 4. Analyze the heap dump
playground debug heap-analyze --file heap-dump-connect-*.hprof

# 5. Review flight recorder data (optional)
playground debug flight-recorder --container connect
```

## Troubleshooting

### Analysis Fails

If analysis fails, check:
1. Heap dump file size and validity
2. Available disk space
3. Docker memory limits: `docker run` may need `--memory=8g`
4. MAT build logs: `/tmp/mat-build.log`
5. Analysis logs: `/tmp/mat-analysis-*.log`

### Large Heap Dumps

For very large heap dumps (>4GB):

```bash
# Increase Docker memory
docker run --rm --memory=8g \
  -v $(pwd)/large-heap.hprof:/analysis/heap.hprof:ro \
  -v $(pwd)/output:/analysis/output \
  eclipse-mat-analyzer \
  /analysis/heap.hprof \
  org.eclipse.mat.api:suspects \
  -output /analysis/output
```

### No Reports Generated

If no HTML reports are generated:
1. Check the heap dump file is valid (not corrupted)
2. Review analysis logs in `/tmp/mat-analysis-*.log`
3. Try opening the dump with VisualVM or Eclipse MAT GUI
4. Ensure the heap dump was created with the correct JVM version

## Alternative Analysis Tools

If automated analysis doesn't meet your needs:

### VisualVM
```bash
# Download VisualVM
# https://visualvm.github.io/

# Open the .hprof file interactively
visualvm --openfile heap-dump.hprof
```

### Eclipse MAT GUI
```bash
# Download Eclipse MAT
# https://www.eclipse.org/mat/

# Open File -> Acquire Heap Dump or File -> Open Heap Dump
```

### jhat (Deprecated but Simple)
```bash
# Built into JDK
jhat heap-dump.hprof

# Open browser to http://localhost:7000
```

## Examples

### Analyzing Kafka Connect Memory Issues

```bash
# Take heap dump during high memory usage
playground debug heap-dump --container connect --live

# Analyze for memory leaks
playground debug heap-analyze \
  --file heap-dump-connect-2026-04-08-15-30-00.hprof \
  --report-type leaks \
  --output-dir connect-leak-analysis

# Review the suspects report
open connect-leak-analysis/suspects_Leak_Suspects.html
```

### Comparing Heap Dumps Over Time

```bash
# Take first snapshot
playground debug heap-dump --container broker --live
mv heap-dump-broker-*.hprof heap-before.hprof

# Run workload...

# Take second snapshot
playground debug heap-dump --container broker --live  
mv heap-dump-broker-*.hprof heap-after.hprof

# Analyze both
playground debug heap-analyze --file heap-before.hprof --output-dir analysis-before
playground debug heap-analyze --file heap-after.hprof --output-dir analysis-after

# Compare reports to identify growth
```

## References

- [Eclipse MAT Documentation](https://help.eclipse.org/latest/index.jsp?topic=%2Forg.eclipse.mat.ui.help%2Fwelcome.html)
- [MAT Query Language](https://help.eclipse.org/latest/index.jsp?topic=%2Forg.eclipse.mat.ui.help%2Fconcepts%2Fquerymatrix.html)
- [Heap Dump Analysis Best Practices](https://dzone.com/articles/heap-dump-analysis)
- [Kafka Memory Tuning](https://kafka.apache.org/documentation/#java)
