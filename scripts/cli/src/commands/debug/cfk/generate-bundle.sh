#!/bin/bash

# Extract arguments
namespace="confluent"
follow_logs_duration="${args[--follow-logs-duration]}"
output_dir="/tmp/cfk-support-bundle"
verbose="${args[--verbose]}"

set +e

# Check if confluent plugin is installed
if ! kubectl confluent support-bundle -h &> /dev/null 2>&1; then
    log "⚠️  kubectl confluent plugin not found. Installing..."
    install_confluent_plugin
fi

# ── Create output directory if needed ───────────────────────────────────────
if [[ -n "$output_dir" ]]; then
    if ! mkdir -p "$output_dir"; then
        logerror "❌ Failed to create output directory: $output_dir"
        exit 1
    fi
    cd "$output_dir" || exit 1
    log "📁 Output directory: $(pwd)"
fi

# ── Build kubectl command ──────────────────────────────────────────────────
cmd="kubectl confluent support-bundle --namespace $namespace"

if [[ -n "$follow_logs_duration" ]]; then    
    if [[ $follow_logs_duration -gt 0 ]]; then
        cmd="$cmd --follow-logs-duration $follow_logs_duration"
        log "📝 Following pod logs for $follow_logs_duration seconds"
    fi
fi

# Add verbose flag if requested
if [[ -n "$verbose" ]]; then
    cmd="$cmd --verbose"
fi

# ── Generate support bundle ────────────────────────────────────────────────
log "🔧 Generating CFK support bundle for namespace: $namespace"
log "⏳ Please wait... this may take a few minutes"
log ""

if [[ -n "$verbose" ]]; then
    log "📋 Running: $cmd"
    log ""
fi

# Run the command and capture output
output=$($cmd 2>&1)
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    log "✅ Support bundle generated successfully!"
    log ""
    
    # Extract bundle full path from output (kubectl outputs the full path)
    bundle_file=$(echo "$output" | grep -oE '/[^ ]*support-bundle.*\.tar\.gz' | head -1)
    
    if [[ -z "$bundle_file" ]]; then
        # Fallback: try to extract just the filename
        bundle_filename=$(echo "$output" | grep -oE 'support-bundle.*\.tar\.gz' | head -1)
        if [[ -n "$bundle_filename" ]]; then
            bundle_file="$output_dir/$bundle_filename"
        fi
    fi
    
    if [[ -n "$bundle_file" ]]; then
        log "📦 Bundle: $bundle_file"
        log ""
        log "📊 To analyze the bundle, run:"
        log "   playground debug cfk cfk-bundle-analyze --bundle $bundle_file --html"
        log ""
        log "📈 To extract the bundle, run:"
        log "   tar -xzf $bundle_file"
    else
        log "Full output:"
        echo "$output"
    fi
else
    logerror "❌ Failed to generate support bundle"
    logerror ""
    logerror "Output:"
    echo "$output" >&2
    exit $exit_code
fi

set -e
