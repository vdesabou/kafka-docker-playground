bundle="${args[--bundle]}"
json_out="${args[--json]}"
no_sanitize="${args[--no-sanitize]}"
severity="${args[--severity]}"
top="${args[--top]}"
html="${args[--html]}"
output_dir="${args[--output-dir]}"

set +e

# ── Validate input ─────────────────────────────────────────────────────────
if [[ -z "$bundle" ]]; then
    logerror "❌ Must provide --bundle <path-to-cfk-support-bundle>"
    log ""
    log "Examples:"
    log "  playground debug cfk-bundle-analyze --bundle ./customer-bundle.tar.gz"
    log "  playground debug cfk-bundle-analyze --bundle ./extracted-bundle/"
    log "  playground debug cfk-bundle-analyze --bundle ./bundle.zip --json > report.json"
    exit 1
fi

# Handle fzf @path trick (mirrors gc-analyze convention)
if [[ "$bundle" == *"@"* ]]; then
    bundle=$(echo "$bundle" | cut -d "@" -f 2)
fi

if [[ ! -e "$bundle" ]]; then
    logerror "❌ Bundle path does not exist: $bundle"
    exit 1
fi

# ── Locate the analyzer CLI ────────────────────────────────────────────────
analyzer_cli="$root_folder/cfk-analysis/analyzer_cli.py"
if [[ ! -f "$analyzer_cli" ]]; then
    logerror "❌ CFK analyzer CLI not found at: $analyzer_cli"
    logerror "   Make sure cfk-analysis/analyzer_cli.py exists in the playground root"
    logerror "   (symlink cfk-bundle-analyzer/ as cfk-analysis/ in the playground root)"
    exit 1
fi

analyzer_dir="$root_folder/cfk-analysis"

bundle_abs=$(cd "$(dirname "$bundle")" && pwd)/$(basename "$bundle")
bundle_container="/tmp/input/$(basename "$bundle")"

# ── Build CLI args ─────────────────────────────────────────────────────────
cli_args=("$bundle")

if [[ -n "$json_out" ]]; then
    cli_args+=(--json)
fi

if [[ -n "$no_sanitize" ]]; then
    cli_args+=(--no-sanitize)
    logwarn "⚠️  Sanitization DISABLED. Do not share this output for customer bundles."
fi

if [[ -n "$severity" ]]; then
    cli_args+=(--severity "$severity")
fi

if [[ -n "$top" ]]; then
    cli_args+=(--top "$top")
fi

# ── HTML output target ─────────────────────────────────────────────────────
html_out=""
html_out_container=""
if [[ -n "$html" ]]; then
    : "${output_dir:=./cfk-reports}"
    mkdir -p "$output_dir"
    output_dir_abs=$(cd "$output_dir" && pwd)

    bundle_basename=$(basename "$bundle")
    # strip common archive suffixes for a clean filename
    bundle_basename="${bundle_basename%.tar.gz}"
    bundle_basename="${bundle_basename%.tgz}"
    bundle_basename="${bundle_basename%.tar}"
    bundle_basename="${bundle_basename%.zip}"

    html_out="${output_dir_abs}/${bundle_basename}-cfk-report-$(date '+%Y%m%d-%H%M%S').html"
    html_out_container="/tmp/output/$(basename "$html_out")"
    cli_args+=(--html-out "$html_out_container")
fi

# ── Run the analyzer ───────────────────────────────────────────────────────
if [[ -z "$json_out" ]]; then
    log "🔬 Analyzing CFK bundle: $bundle"
    log ""
fi

docker_args=(
    -i
    --rm
    -v "$analyzer_dir:/tmp/cfk-analysis:ro"
    -v "$bundle_abs:$bundle_container:ro"
)

if [[ -n "$html_out" ]]; then
    docker_args+=( -v "$output_dir_abs:/tmp/output" )
fi

container_cli_args=("$bundle_container")
if [[ ${#cli_args[@]} -gt 1 ]]; then
    container_cli_args+=("${cli_args[@]:1}")
fi

docker run "${docker_args[@]}" python:3.7-slim sh -lc 'pip install -q -r /tmp/cfk-analysis/requirements.txt && python /tmp/cfk-analysis/analyzer_cli.py "$@"' sh "${container_cli_args[@]}"
exit_code=$?

# ── Open HTML report in browser ────────────────────────────────────────────
if [[ -n "$html" && -f "$html_out" ]]; then
    log ""
    log "🌐 HTML report saved: $html_out"
    if command -v open &>/dev/null; then
        log "🌐 Opening report in browser..."
        open "$html_out"
    elif command -v xdg-open &>/dev/null; then
        log "🌐 Opening report in browser..."
        xdg-open "$html_out" >/dev/null 2>&1 &
    else
        log "🔗 Open in browser: file://$html_out"
    fi
fi

if [[ -z "$json_out" ]]; then
    log ""
    case $exit_code in
        0) log "✅ Analysis complete — no critical or high-severity issues found." ;;
        1) logwarn "⚠️  Analysis complete — high-severity issues found. Review the report above." ;;
        2) logerror "❌ Analysis complete — CRITICAL issues found. Act on the recommendations above." ;;
        64) logerror "❌ Analysis failed — invalid bundle path or format." ;;
        *) logerror "❌ Analyzer exited with code $exit_code." ;;
    esac
fi

exit $exit_code
