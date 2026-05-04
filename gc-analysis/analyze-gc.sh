#!/usr/bin/env bash
# Wrapper: analyze GC logs, optionally extracting them from a running container.
#
# Usage:
#   ./analyze-gc.sh <gc-log-file> [--json] [--top-pauses N]
#   ./analyze-gc.sh --container <name> --gc-path /path/in/container [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZER="$SCRIPT_DIR/gc_log_analyzer.py"

if [[ $# -eq 0 ]]; then
  echo "Usage:"
  echo "  $0 <gc-log-file> [--json] [--top-pauses N]"
  echo "  $0 --container <name> --gc-path /path/in/container [--json]"
  exit 1
fi

CONTAINER=""
GC_PATH=""
PASS_ARGS=()
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) CONTAINER="$2"; shift 2 ;;
    --gc-path)   GC_PATH="$2";   shift 2 ;;
    --json|--top-pauses) PASS_ARGS+=("$1"); [[ "$1" == "--top-pauses" ]] && { PASS_ARGS+=("$2"); shift; }; shift ;;
    *) FILES+=("$1"); shift ;;
  esac
done

if [[ -n "$CONTAINER" ]]; then
  TMP=$(mktemp /tmp/gc-XXXXXX.log)
  trap "rm -f $TMP" EXIT
  echo "Copying GC log from container '$CONTAINER':$GC_PATH ..."
  docker cp "$CONTAINER:$GC_PATH" "$TMP"
  FILES=("$TMP")
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Error: no log files specified." >&2
  exit 1
fi

python3 "$ANALYZER" "${PASS_ARGS[@]}" "${FILES[@]}"
