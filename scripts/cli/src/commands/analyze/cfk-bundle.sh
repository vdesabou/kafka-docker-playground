# hidden alias: playground analyze logs detects a CFK support bundle and runs the same analysis (analyze_cfk_bundle)
bundle="${args[--bundle]}"
sample="${args[--sample]}"
json_out="${args[--json]}"
no_sanitize="${args[--no-sanitize]}"
severity="${args[--severity]}"
top="${args[--top]}"
output_dir="${args[--output-dir]}"
include_warnings="${args[--include-warnings]}"
eval "component_array=(${args[--component]})"

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

if [[ -z "$json_out" ]]; then
    log "🔬 Analyzing CFK bundle: $bundle"
    log ""
fi
analyze_cfk_bundle "$bundle" "$json_out" "$no_sanitize" "$severity" "$top" "${output_dir:-./cfk-reports}" "$include_warnings" "${component_array[@]}"
