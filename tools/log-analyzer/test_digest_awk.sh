#!/bin/bash
# The digest (summarize_log_errors of scripts/cli/src/lib/cli_function.sh) with every awk given: mawk (the default awk of
# Debian / Ubuntu), gawk, busybox awk, the awk of macOS. It must run with each of them and find the same records: a
# construct one of them refuses ("cut is duplicated in argument list" of mawk) made the whole digest fail on that system.
#
#   tools/log-analyzer/test_digest_awk.sh mawk gawk "busybox awk"
set -u
shopt -s nullglob
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed -n '/^function summarize_log_errors/,/^}/p' "$root/scripts/cli/src/lib/cli_function.sh" > "$tmp/digest.sh"
samples=("$root/tools/log-analyzer/samples/connect-oracle-xstream-task-failure.log" "$root"/tools/log-analyzer/samples/kafka-clients/*.log
         "$root"/tools/log-analyzer/samples/kafka-streams/*.log "$root"/tools/log-analyzer/samples/compare/*.log)
failed=0
reference=""
for awk_cmd in "$@"
do
    name=$(printf '%s' "$awk_cmd" | tr -c 'A-Za-z0-9' '-')
    bin="$tmp/bin-$name"
    mkdir -p "$bin"
    printf '#!/bin/sh\nexec %s "$@"\n' "$awk_cmd" > "$bin/awk"
    chmod +x "$bin/awk"
    out="$tmp/out-$name"
    : > "$out"
    for f in "${samples[@]}"
    do
        if ! PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2.records" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out" "$f" > "$out.digest" 2> "$out.err"
        then
            echo "❌ $awk_cmd: the digest of $(basename "$f") failed: $(head -n 2 "$out.err" | tr '\n' ' ')"
            failed=1
        fi
        grep -E '^🔎 ' "$out.digest" | sed "s|^|$(basename "$f"): |" >> "$out"
    done
    if [ -z "$reference" ]
    then
        reference="$out"
        echo "✅ $awk_cmd: $(wc -l < "$out" | tr -d ' ') file(s) with records"
    elif diff -q "$reference" "$out" > /dev/null
    then
        echo "✅ $awk_cmd: same records as $1"
    else
        echo "❌ $awk_cmd: other records than $1:"
        diff "$reference" "$out" | head -n 10
        failed=1
    fi
done
exit $failed
