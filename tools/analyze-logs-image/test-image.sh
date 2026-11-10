#!/usr/bin/env bash
# Tests of the kdp-analyze-logs image, run by .github/workflows/analyze-logs-image.yml before it is published:
#   tools/analyze-logs-image/test-image.sh <image>
# Every run uses --network none (the analysis needs no network) and the samples shipped in the image or in the
# repository. Exit code 1 on the first failed check.
set -u
image="${1:?usage: $0 <image>}"
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# the user of docker run on Linux, as documented: the report belongs to the user, not to root
user_args=(--user "$(id -u):$(id -g)")
failed=0

check() {
    local name="$1"
    shift
    if "$@"
    then
        echo "✅ $name"
    else
        echo "❌ $name"
        failed=1
    fi
}

run() {
    docker run --rm --network none "${user_args[@]}" -v "$work":/data "$@"
}

cp "$repo/tools/log-analyzer/samples/support-bundle.zip" "$work/"
mkdir -p "$work/logs-folder"
cp "$repo/tools/log-analyzer/samples/connect-many-connectors.log" "$work/logs-folder/"

# 1. a .zip, sanitized, host folder not known: paths printed relative to the folder, no ✏️ link
run "$image" -f support-bundle.zip --sanitize > "$work/out1.txt" 2>&1
rc=$?
check "zip: exit code 0" test $rc -eq 0
check "zip: report written" test -s "$work/log-analysis-output/support-bundle-log-report.html"
check "zip: ticket summary written" test -s "$work/log-analysis-output/support-bundle-ticket.md"
check "zip: path printed relative to the folder" grep -q "HTML report saved: ./log-analysis-output/support-bundle-log-report.html" "$work/out1.txt"
check "zip: no ✏️ link without KDP_HOST_DIR" bash -c "! grep -rqs 'vscode://' '$work/log-analysis-output'"
check "zip: sanitized" grep -q "🔒 Sanitized (--sanitize)" "$work/log-analysis-output/support-bundle-log-report.html"
check "zip: not marked as not sanitized" bash -c "! grep -q 'Not sanitized' '$work/log-analysis-output/support-bundle-log-report.html'"

# 2. a folder with KDP_HOST_DIR: host paths printed, ✏️ links to the original files on the host
run -e KDP_HOST_DIR=/host/case "$image" -f logs-folder --output-dir out2 > "$work/out2.txt" 2>&1
rc=$?
check "folder: exit code 0" test $rc -eq 0
check "folder: host path printed" grep -q "HTML report saved: /host/case/out2/logs-folder-log-report.html" "$work/out2.txt"
check "folder: ✏️ links to the host file" grep -q "vscode://file/host/case/logs-folder/connect-many-connectors.log:" "$work/out2/logs-folder-log-report.html"

# 3. a CFK support bundle: the ☸️ sections, by the python3 of the image (no Docker in Docker)
run "$image" --sample cfk_bundle --output-dir out3 > "$work/out3.txt" 2>&1
rc=$?
check "cfk: exit code 0" test $rc -eq 0
check "cfk: no warning about a missing container engine" bash -c "! grep -q 'no container engine' '$work/out3.txt'"
check "cfk: analysis JSON written" test -s "$work/out3/cfk-support-bundle-cfk.json"
check "cfk: ☸️ sections in the report" test "$(grep -o '☸️' "$work/out3/cfk_bundle-log-report.html" | wc -l)" -gt 10

# 4. two CFK support bundles compared
run "$image" --sample cfk_rollout --sample cfk_rollout_after --output-dir out4 > "$work/out4.txt" 2>&1
rc=$?
check "cfk comparison: exit code 0" test $rc -eq 0
check "cfk comparison: report written" bash -c "ls '$work'/out4/cfk-bundles-comparison-*.html > /dev/null 2>&1"

# 5. --json: only JSON on stdout
run "$image" -f support-bundle.zip --json > "$work/out5.json" 2> "$work/out5.err"
rc=$?
check "json: exit code 0" test $rc -eq 0
check "json: stdout parses" python3 -c "import json, sys; d = json.load(open(sys.argv[1])); assert 'findings' in d" "$work/out5.json"

# 5b. thread dumps in a zip: analyzed in the report by the thread analyzer of the image (🧵), and --json too (no copy
# kept: read from the tmp dir of the run); the broker signals and the cluster layout of a folder of broker logs
mkdir -p "$work/dumps/connect-0"
cp "$repo/tools/log-analyzer/samples/connect-oracle-xstream-task-failure.log" "$work/dumps/connect-0/connect.log"
for i in 1 2 3; do cp "$repo/tools/thread-analyzer/samples/jdk21-scenario-$i.txt" "$work/dumps/connect-0/thread-dump-$i.txt"; done
(cd "$work" && python3 -c "import shutil; shutil.make_archive('dumps', 'zip', '.', 'dumps')")
run "$image" -f dumps.zip --output-dir out5b > "$work/out5b.txt" 2>&1
check "thread dumps: analyzed in the report" grep -q "\[CRITICAL\] Deadlock between deadlock-1, deadlock-2" "$work/out5b.txt"
check "thread dumps: thread report written" bash -c "ls '$work'/out5b/dumps-thread-dumps.html > /dev/null 2>&1"
run "$image" -f dumps.zip --json > "$work/out5c.json" 2> /dev/null
check "thread dumps: .thread_dumps of --json" python3 -c "import json, sys; d = json.load(open(sys.argv[1])); assert d['thread_dumps'][0]['findings'][0]['severity'] == 'CRITICAL'" "$work/out5c.json"
cp -r "$repo/tools/log-analyzer/samples/broker-pressure" "$work/"
run "$image" -f broker-pressure --output-dir out5d > "$work/out5d.txt" 2>&1
check "broker signals" grep -q "🌀 STORM broker 1: 30 ISR shrinks" "$work/out5d.txt"
check "cluster layout" grep -q "🗺️ Cluster layout (kafka-log-dirs.txt, kafka-topics-describe.txt)" "$work/out5d.txt"

# 5e. --sample jvm_dumps: its thread dumps and heap dump are shipped in the image
run "$image" --sample jvm_dumps --output-dir out5e > "$work/out5e.txt" 2>&1
check "sample jvm_dumps: exit code 0" test $? -eq 0
check "sample jvm_dumps: thread dumps analyzed" grep -q "\[CRITICAL\] Deadlock between deadlock-1, deadlock-2" "$work/out5e.txt"
check "sample jvm_dumps: heap dump listed" grep -q "session-cache-leak-1.hprof.gz" "$work/out5e.txt"

# 6. no folder mounted: a hint, and the help without arguments
docker run --rm --network none "$image" --sample connect_task_failure --output-dir /tmp/out > "$work/out6.txt" 2>&1
check "sample without a mounted folder: exit code 0" test $? -eq 0
docker run --rm "$image" -f x.log > "$work/out7.txt" 2>&1
check "no folder mounted: hint" grep -q 'add -v "$PWD":/data' "$work/out7.txt"
docker run --rm "$image" > "$work/out8.txt" 2>&1
check "no argument: help" grep -q "playground analyze logs" "$work/out8.txt"

if [ $failed -ne 0 ]
then
    for f in "$work"/out*.txt
    do
        echo "--- $(basename "$f")"
        tail -30 "$f"
    done
    exit 1
fi
echo "🎉 all the checks passed"
