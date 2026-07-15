#!/bin/bash

# Extract arguments
namespace="confluent"
follow_logs_duration="${args[--follow-logs-duration]}"
output_dir="/tmp/cfk-support-bundle"
verbose="${args[--verbose]}"

set +e

# Function to install confluent plugin
install_confluent_plugin() {
    log "📦 Installing kubectl confluent plugin..."
    
    # Create temporary directory for bundle
    tmp_bundle_dir=$(mktemp -d -t cfk-bundle-XXXXXXXXXX)
    if [ -z "$PG_VERBOSE_MODE" ]; then
        trap 'rm -rf $tmp_bundle_dir' EXIT
    else
        log "🐛📂 Bundle temp dir: $tmp_bundle_dir"
    fi
    
    # Detect CFK version (try to get latest or default to 3.3)
    cfk_version="${CFK_VERSION:-3.3.0}"
    log "⏳ Downloading CFK bundle version $cfk_version..."
    
    bundle_url="https://packages.confluent.io/bundle/cfk/confluent-for-kubernetes-${cfk_version}.tar.gz"
    bundle_file="$tmp_bundle_dir/confluent-for-kubernetes-${cfk_version}.tar.gz"
    
    # Download the bundle
    if ! curl -f -L -o "$bundle_file" "$bundle_url" 2>&1 | grep -v "^  "; then
        logerror "❌ Failed to download CFK bundle from $bundle_url"
        logerror "   Check the version is correct: $cfk_version"
        logerror "   You can set a custom version: export CFK_VERSION=3.2.0"
        exit 1
    fi
    
    # Extract bundle
    log "⏳ Extracting bundle..."
    tar -xzf "$bundle_file" -C "$tmp_bundle_dir" 2>&1 | grep -v "^x " || true
    
    # Detect OS and architecture
    os_type=$(uname -s)
    arch_type=$(arch)
    
    # Map OS type to plugin name
    case "$os_type" in
        Darwin)
            os_name="darwin"
            ;;
        Linux)
            os_name="linux"
            ;;
        *)
            logerror "❌ Unsupported OS: $os_type"
            logerror "   Supported: macOS (Darwin) and Linux"
            exit 1
            ;;
    esac
    
    # Map architecture
    case "$arch_type" in
        arm64|aarch64)
            arch_name="arm64"
            ;;
        x86_64)
            arch_name="amd64"
            ;;
        *)
            logerror "❌ Unsupported architecture: $arch_type"
            logerror "   Supported: arm64 and amd64"
            exit 1
            ;;
    esac
    
    log "🔧 Detected OS: $os_name, Architecture: $arch_name"
    
    # Find the extracted CFK bundle directory (it may have a timestamp suffix)
    cfk_dir=$(find "$tmp_bundle_dir" -maxdepth 1 -type d -name "confluent-for-kubernetes-${cfk_version}*" | head -1)
    
    if [[ -z "$cfk_dir" ]]; then
        logerror "❌ CFK bundle directory not found"
        logerror "   Available directories:"
        find "$tmp_bundle_dir" -maxdepth 1 -type d | sed 's/^/     /'
        exit 1
    fi
    
    # Find and extract the plugin
    plugin_tar="$cfk_dir/kubectl-plugin/kubectl-confluent-${os_name}-${arch_name}.tar.gz"
    
    if [[ ! -f "$plugin_tar" ]]; then
        logerror "❌ Plugin not found: $plugin_tar"
        logerror "   Available files:"
        find "$cfk_dir" -name "kubectl-confluent*" 2>/dev/null | sed 's/^/     /'
        exit 1
    fi
    
    log "📋 Extracting plugin to /usr/local/bin/"
    
    # Ensure /usr/local/bin exists
    if [[ ! -d /usr/local/bin ]]; then
        log "ℹ️  Creating /usr/local/bin directory..."
        sudo mkdir -p /usr/local/bin
    fi
    
    # Try to extract to /usr/local/bin
    extraction_success=false
    
    # First try without sudo
    if tar -xzf "$plugin_tar" -C /usr/local/bin/ 2>/dev/null; then
        extraction_success=true
    # Then try with sudo
    elif sudo tar -xzf "$plugin_tar" -C /usr/local/bin/ 2>/dev/null; then
        extraction_success=true
    fi
    
    if [[ "$extraction_success" == false ]]; then
        logerror "❌ Failed to extract plugin to /usr/local/bin/"
        logerror "   Trying alternative location: ~/.local/bin/"
        
        # Try alternative location
        mkdir -p ~/.local/bin
        if tar -xzf "$plugin_tar" -C ~/.local/bin/ 2>/dev/null; then
            log "✅ Plugin extracted to ~/.local/bin/"
            log ""
            log "⚠️  To use the plugin, add ~/.local/bin to your PATH:"
            log "   export PATH=~/.local/bin:\$PATH"
            log ""
            log "   Add this to your ~/.zshrc or ~/.bashrc to make it permanent"
            extraction_success=true
        else
            logerror "❌ Failed to extract to ~/.local/bin/ as well"
            logerror "   Try manually:"
            logerror "   sudo tar -xzf $plugin_tar -C /usr/local/bin/"
            exit 1
        fi
    fi
    
    # Refresh shell command cache
    hash -r 2>/dev/null || true
    
    # Verify plugin was installed
    if ! kubectl confluent support-bundle -h &> /dev/null 2>&1; then
        logerror "❌ Plugin extraction completed but kubectl still cannot find the confluent plugin"
        logerror "   Try restarting your terminal"
        exit 1
    fi
    
    log "✅ Confluent kubectl plugin installed successfully!"
}

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
