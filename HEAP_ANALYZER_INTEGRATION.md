# Heap Dump Analyzer Integration

This document describes the new heap dump analysis feature added to the Kafka Docker Playground.

## Overview

The playground now includes automated heap dump analysis using Eclipse MAT (Memory Analyzer Tool). This provides:

- 🔬 Automated memory leak detection
- 📊 HTML/ZIP formatted analysis reports  
- 🐳 Docker-based analyzer (no local installation needed)
- 🚀 Seamless CLI integration

## Changes Made

### 1. New CLI Command: `playground debug heap-analyze`

Added to `scripts/cli/src/bashly.yml` and implemented in `scripts/cli/src/commands/debug/heap-analyze.sh`

**Usage:**
```bash
playground debug heap-analyze --file heap-dump.hprof
```

**Options:**
- `--file, -f`: Path to .hprof file (required)
- `--output-dir, -o`: Output directory for reports (default: ./heap-analysis)
- `--report-type, -r`: Type of report (all, leaks, overview, top-components)

### 2. Heap Analyzer Tool (`tools/heap-analyzer/`)

New tool directory containing:

- **Dockerfile**: Eclipse MAT 1.15.0 with headless analysis support
- **README.md**: Comprehensive documentation with use cases and examples
- **QUICK_START.md**: Quick reference guide for common scenarios
- **build.sh**: Script to build the analyzer Docker image
- **test-analyzer.sh**: Test script to verify functionality
- **example-workflow.sh**: End-to-end workflow demonstration
- **.gitignore**: Prevents committing large heap dump files

### 3. Integration with Existing Workflow

Complements existing debug commands:
- `playground debug heap-dump` - Collect heap dumps
- `playground debug heap-analyze` - **NEW** Analyze heap dumps
- `playground debug thread-dump` - Thread analysis
- `playground debug flight-recorder` - JFR profiling

## Features

### Automated Reports

1. **Leak Suspects Report** (`--report-type leaks`)
   - Identifies potential memory leaks
   - Shows accumulation points and retention paths
   - Provides actionable insights

2. **System Overview** (`--report-type overview`)
   - Heap usage statistics
   - Class distribution
   - Object counts

3. **Top Components** (`--report-type top-components`)
   - Largest memory consumers
   - Component breakdown
   - Retained vs shallow heap comparison

### Docker-Based Analysis

- No local Eclipse MAT installation required
- Consistent environment across all users
- Configurable memory limits
- Works with any JVM heap dump

## Usage Examples

### Basic Analysis
```bash
# Take a heap dump
playground debug heap-dump --container connect --live

# Analyze it
playground debug heap-analyze --file heap-dump-connect-*.hprof
```

### Memory Leak Investigation
```bash
# Baseline
playground debug heap-dump --container connect --live
mv heap-dump-connect-*.hprof baseline.hprof

# After reproducing issue
playground debug heap-dump --container connect --live

# Analyze for leaks
playground debug heap-analyze --file heap-dump-connect-*.hprof --report-type leaks
```

### High Memory Troubleshooting
```bash
# Find top memory consumers
playground debug heap-analyze \
  --file heap-dump-broker.hprof \
  --report-type top-components \
  --output-dir memory-analysis
```

## File Structure

```
kafka-docker-playground/
├── scripts/cli/src/
│   ├── bashly.yml                           # Added heap-analyze command
│   └── commands/debug/
│       └── heap-analyze.sh                  # NEW: Analysis logic
│
├── tools/heap-analyzer/                     # NEW: Analyzer tool
│   ├── Dockerfile                           # MAT Docker image
│   ├── README.md                            # Full documentation
│   ├── QUICK_START.md                       # Quick reference
│   ├── build.sh                             # Build script
│   ├── test-analyzer.sh                     # Test suite
│   ├── example-workflow.sh                  # Usage examples
│   └── .gitignore                           # Ignore heap dumps
│
└── HEAP_ANALYZER_INTEGRATION.md             # This file
```

## Testing

Run the test suite:
```bash
bash tools/heap-analyzer/test-analyzer.sh
```

This will:
1. Build the analyzer Docker image
2. Create a test heap dump
3. Run analysis
4. Verify reports are generated

## Dependencies

- Docker (already required by playground)
- Eclipse MAT 1.15.0 (bundled in Docker image)
- Eclipse Temurin JDK 17 (base image)

## Documentation

- **Quick Start**: `tools/heap-analyzer/QUICK_START.md`
- **Full README**: `tools/heap-analyzer/README.md`
- **CLI Help**: `playground debug heap-analyze --help`

## Benefits

1. **Faster Debugging**: Automated analysis vs manual inspection
2. **Consistent Results**: Standardized reports across team
3. **No Setup**: Docker-based, no local tools needed
4. **Learning Tool**: Reports explain memory issues with context
5. **Integration**: Works with existing playground workflows

## Future Enhancements

Potential improvements:
- Historical comparison (compare multiple dumps)
- Custom MAT queries
- Integration with monitoring dashboards
- Automated leak detection in CI
- Support for additional report types

## Migration Notes

- Existing `playground debug heap-dump` functionality unchanged
- New command is additive, no breaking changes
- Backwards compatible with existing scripts

## Support

For issues or questions:
1. Check test logs: `/tmp/mat-analysis-*.log`
2. Review documentation in `tools/heap-analyzer/`
3. Open issue at https://github.com/vdesabou/kafka-docker-playground/issues

## Credits

- Eclipse MAT: https://www.eclipse.org/mat/
- Bashly CLI framework: https://bashly.dev/
- Kafka Docker Playground: https://kafka-docker-playground.io/
