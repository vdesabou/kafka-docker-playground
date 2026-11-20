output_dir="${args[--output-dir]}"
no_open="${args[--no-open]}"

if ! command -v python3 > /dev/null 2>&1
then
  logerror "❌ python3 is required to build the pipeline builder page"
  exit 1
fi

output_dir="${output_dir:-/tmp/playground-pipeline-builder}"
mkdir -p "$output_dir"
report="$output_dir/pipeline-builder.html"

log "🔗 Reading the connector examples of $root_folder"
if ! python3 -I "$root_folder/tools/pipeline-builder/catalog.py" html --root "$root_folder" --output "$report" 2> "$output_dir/pipeline-builder.log"
then
  logerror "❌ could not build the pipeline builder page:"
  cat "$output_dir/pipeline-builder.log"
  exit 1
fi
log "🧭 pick a source (or a sink for a fan-out) and the sinks, then copy the 'playground repro bootstrap --pipeline' command"
open_html_report "$report" "$no_open"
