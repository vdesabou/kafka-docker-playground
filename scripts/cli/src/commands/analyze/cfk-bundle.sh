bundle="${args[--bundle]}"
sample="${args[--sample]}"
json_out="${args[--json]}"
no_sanitize="${args[--no-sanitize]}"
severity="${args[--severity]}"
top="${args[--top]}"
html="${args[--html]}"
output_dir="${args[--output-dir]}"
include_warnings="${args[--include-warnings]}"

set +e

if [[ -n "$bundle" && -n "$sample" ]]; then
    logerror "❌ Provide either --bundle or --sample, not both"
    exit 1
fi
if [[ -z "$bundle" && -z "$sample" ]]; then
    logerror "❌ Must provide --bundle <directory or archive> (or --sample synthetic to try it)"
    exit 1
fi
# ── Sample mode: bundle shipped in cfk-analysis/samples (built by make_synthetic_bundle.py) ──
if [[ "$sample" == "synthetic" ]]; then
    bundle="$root_folder/cfk-analysis/samples/cfk-support-bundle-synthetic.tar.gz"
fi

# Handle fzf @path trick (mirrors gc-logs convention), only when the path itself does not exist
if [[ ! -e "$bundle" && "$bundle" == *"@"* ]]; then
    bundle=$(echo "$bundle" | cut -d "@" -f 2)
fi

if [[ ! -e "$bundle" ]]; then
    logerror "❌ Bundle path does not exist: $bundle"
    exit 1
fi

analyzer_dir="$root_folder/cfk-analysis"
if [[ ! -f "$analyzer_dir/analyzer_cli.py" ]]; then
    logerror "❌ CFK analyzer not found at: $analyzer_dir/analyzer_cli.py"
    exit 1
fi

# ── Analyzer image (dependencies baked once, code mounted at run time) ─────
# The tag changes when the Dockerfile or requirements change, so the image is rebuilt only then
image_tag=$(cat "$analyzer_dir/Dockerfile" "$analyzer_dir/requirements.txt" | cksum | cut -d ' ' -f 1)
image="cfk-bundle-analyzer:$image_tag"
if ! docker image inspect "$image" > /dev/null 2>&1; then
    # stderr: stdout must stay valid JSON with --json
    log "🏗️  Building $image (first run only)..." >&2
    build_log="/tmp/cfk-bundle-analyzer-build.log"
    if ! docker build --load -t "$image" "$analyzer_dir" > "$build_log" 2>&1 && ! docker build -t "$image" "$analyzer_dir" >> "$build_log" 2>&1; then
        logerror "❌ Failed to build $image, see $build_log"
        tail -20 "$build_log" >&2
        exit 1
    fi
fi

bundle_abs=$(cd "$(dirname "$bundle")" && pwd -P)/$(basename "$bundle")
bundle_container="/tmp/input/$(basename "$bundle")"

# ── Build CLI args ─────────────────────────────────────────────────────────
cli_args=("$bundle_container")

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

if [[ -n "$include_warnings" ]]; then
    cli_args+=(--include-warnings)
fi

# run as the current user: it can read the bundle and write the HTML report
docker_args=(
    --rm
    --user "$(id -u):$(id -g)"
    -v "$analyzer_dir:/tmp/cfk-analysis:ro"
    -v "$bundle_abs:$bundle_container:ro"
)

# ── HTML output target ─────────────────────────────────────────────────────
html_out=""
if [[ -n "$html" ]]; then
    : "${output_dir:=./cfk-reports}"
    mkdir -p "$output_dir"
    output_dir_abs=$(cd "$output_dir" && pwd -P)

    bundle_basename=$(basename "$bundle")
    # strip common archive suffixes for a clean filename
    bundle_basename="${bundle_basename%.tar.gz}"
    bundle_basename="${bundle_basename%.tgz}"
    bundle_basename="${bundle_basename%.tar}"
    bundle_basename="${bundle_basename%.zip}"

    html_out="${output_dir_abs}/${bundle_basename}-cfk-report-$(date '+%Y%m%d-%H%M%S').html"
    cli_args+=(--html-out "/tmp/output/$(basename "$html_out")")
    docker_args+=( -v "$output_dir_abs:/tmp/output" )
fi

# ── Run the analyzer ───────────────────────────────────────────────────────
if [[ -z "$json_out" ]]; then
    log "🔬 Analyzing CFK bundle: $bundle"
    log ""
fi

docker run "${docker_args[@]}" "$image" "${cli_args[@]}"
exit_code=$?

case $exit_code in
    0) ;;
    64) logerror "❌ Analysis failed — invalid, unsafe or empty bundle (see error above)." ;;
    *) logerror "❌ Analyzer failed with exit code $exit_code." ;;
esac

# ── Open HTML report in browser ────────────────────────────────────────────
if [[ $exit_code -eq 0 && -n "$html" && -f "$html_out" ]]; then
    log ""
    log "🌐 HTML report saved: $html_out"
    # only open a browser in an interactive terminal
    if [[ ! -t 1 ]]; then
        log "🔗 Open in browser: file://$html_out"
    elif command -v open &>/dev/null; then
        log "🌐 Opening report in browser..."
        open "$html_out"
    elif command -v xdg-open &>/dev/null; then
        log "🌐 Opening report in browser..."
        xdg-open "$html_out" >/dev/null 2>&1 &
    else
        log "🔗 Open in browser: file://$html_out"
    fi
fi

exit $exit_code
