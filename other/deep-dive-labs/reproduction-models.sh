#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-reproduction-models (no container needed)
lab_require_plaintext

root_dir="$( cd "${DIR}/../.." >/dev/null && pwd )"
model_dir="${root_dir}/reproduction-models/connect-connect-filestream-sink"
if [ ! -d "$model_dir" ]
then
    logwarn "the private reproduction-models submodule is not checked out (it isn't in CI), skipping"
    exit 111
fi

# the lab writes into the private submodule: a description that can't collide with a real model, and a cleanup
# that deletes exactly the files it creates (never the symlinks of the folder, shared by the other models)
model="${model_dir}/filestream-sink-repro-000000-deep-dive-lab-ci.sh"
override="${model_dir}/docker-compose.plaintext.repro-000000-deep-dive-lab-ci.yml"
imported="${model_dir}/filestream-sink-repro-000000-deep-dive-lab-ci-imported-$(date +%Y%m%d).sh"
report="${model_dir}/filestream-sink-repro-000000-deep-dive-lab-ci.REPRO.md"
config_model="${model_dir}/filestream-sink-repro-000000-deep-dive-lab-ci-config.sh"
config_override="${model_dir}/docker-compose.plaintext.repro-000000-deep-dive-lab-ci-config.yml"
for f in "$model" "$override" "$imported" "$report" "$config_model" "$config_override"
do
    if [ -e "$f" ]
    then
        logerror "❌ $f already exists, remove it before running the lab"
        exit 1
    fi
done
prev_test_file=$(playground state get run.test_file 2> /dev/null | tail -1)
prev_clipboard=$(playground config get clipboard 2> /dev/null | tail -1)
export_dir=$(mktemp -d)
function cleanup_lab () {
    rm -f "$model" "$override" "$imported" "$report" "$config_model" "$config_override"
    rm -rf "$export_dir"
    # the verdicts of the lab models
    if [ -f "${root_dir}/playground-repro-verdicts" ]
    then
        grep -vF "000000-deep-dive-lab-ci" "${root_dir}/playground-repro-verdicts" > "${root_dir}/playground-repro-verdicts.tmp" || true
        mv "${root_dir}/playground-repro-verdicts.tmp" "${root_dir}/playground-repro-verdicts"
    fi
    if [ -n "$prev_test_file" ]
    then
        playground state set run.test_file "$prev_test_file" > /dev/null 2>&1
    fi
    playground config set clipboard "${prev_clipboard:-true}" > /dev/null 2>&1
}
trap cleanup_lab EXIT
playground config set clipboard false > /dev/null 2>&1

log "Step 1: bootstrap without running"
lab_run playground repro bootstrap -f "${root_dir}/connect/connect-filestream-sink/filestream-sink.sh" -d "000000 deep dive lab ci" --no-run
lab_expect_exit 0
lab_expect_contains "✨ Creating file ${model}"
lab_expect_contains "✨ Creating file ${override}"
lab_expect_contains "🌟 command to run generated example"
lab_expect_contains "playground run -f ${model}"
lab_expect_contains "🛑 --no-run is set, not running the reproduction model"
lab_run playground state get run.test_file
lab_expect_not_contains "$model" "--no-run leaves the current model unchanged"

log "Step 2: what was generated"
lab_run head -20 "$model"
lab_expect_contains "# 💡 description: 000000 deep dive lab ci"
lab_expect_contains "# 🔮 ticket: https://confluent.zendesk.com/agent/tickets/000000"
lab_expect_contains "# 💬 comments:"
lab_expect_contains "# 🎯 expected:"
lab_expect_contains "# 💥 actual:"
lab_expect_contains "# 🎫 jira:"
lab_expect_contains "# 🩹 status: open"
lab_run grep -n "docker-compose" "$model"
lab_expect_contains '--docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000000-deep-dive-lab-ci.yml"'
lab_run grep -c "^exit 0" "$model"
lab_expect_equals "$LAB_OUTPUT" "1" "exit 0 lines (cheat sheet above, snippets below)"
lab_run readlink "${model_dir}/README.md"
lab_expect_contains "../../connect/connect-filestream-sink/README.md"
lab_run readlink "${model_dir}/stop.sh"
lab_expect_contains "../../connect/connect-filestream-sink/stop.sh"
lab_run playground repro status -f "$model" --set "lab only" --jira CC-1234
lab_expect_exit 0
lab_expect_contains "✏️  updated in the header: jira status"
lab_expect_contains "🧬 based on: connect/connect-filestream-sink"
lab_expect_contains "🎯 expected: (empty)"
lab_expect_contains "🎫 jira: https://confluentinc.atlassian.net/browse/CC-1234"
lab_expect_contains "🩹 status: lab only"
lab_expect_contains "💡 fill in the empty fields: playground repro status -f ${model} --expected"
lab_expect_contains "🧪 last verdict: none yet (end the scenario with 'playground repro assert')"
lab_run grep -c "^# 🩹 status: lab only$" "$model"
lab_expect_equals "$LAB_OUTPUT" "1" "status lines (replaced, not added)"
lab_run grep -c "^# playground repro assert --reproduced-if-log" "$model"
lab_expect_equals "$LAB_OUTPUT" "1" "commented repro assert lines at the end of the scenario"
lab_run playground repro bisect -f "$model" --connector-tag 1.0.0 --connector-tag 2.0.0
lab_expect_exit 1 "bisect needs a model that calls repro assert (nothing is run)"
lab_expect_contains "does not call 'playground repro assert'"
lab_run playground repro assert -f "$model" --reproduced-if-command "test -f '$model'" --message "the model exists"
lab_expect_exit 0
lab_expect_contains "🐞 REPRODUCED: the model exists (the command succeeded: test -f"
lab_run playground repro assert -f "$model" --reproduced-if-command "false"
lab_expect_exit 0 "a model that does not reproduce is a result, not an error"
lab_expect_contains "✅ NOT REPRODUCED: the command failed: false"
lab_run playground repro assert -f "$model" --reproduced-if-records-less-than 3
lab_expect_exit 1
lab_expect_contains "need --topic"
lab_run playground repro assert -f "$model" --reproduced-if-command "test -f '$model'" --json
lab_expect_contains '"verdict": "reproduced"'
lab_run playground repro status -f "$model"
lab_expect_contains "🧪 last verdict: 🐞 reproduced on $(date -u +%Y-%m-%d)"
lab_run bash -c "playground repro list --grep '000000-deep-dive-lab-ci' --json 2> /dev/null | jq -c '.[0] | {path, case, status, jira, verdict: .last_verdict.verdict, base_example}'"
lab_expect_contains '{"path":"connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-ci.sh","case":"000000","status":"lab only","jira":"https://confluentinc.atlassian.net/browse/CC-1234","verdict":"reproduced","base_example":"connect/connect-filestream-sink"}'
lab_run playground repro list --case 000000 --status "lab only"
lab_expect_contains "000000 deep dive lab ci"
lab_expect_contains "↳ connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-ci.sh"

log "Step 3: check it, with and without a secret"
lab_run playground repro check -f "$model"
lab_expect_exit 0
lab_expect_contains "✅ no secret nor customer data found"
echo '# aws_access_key_id = AKIAABCDEFGHIJKLMNOP' >> "$model"
lab_run playground repro check -f "$model"
lab_expect_exit 1
lab_expect_contains "filestream-sink-repro-000000-deep-dive-lab-ci.sh:"
lab_expect_contains "looks like an AWS access key id"
lab_expect_contains "❌ 1 secret finding(s): remove them (use \${VAR} instead of the value)"
lab_run bash -c "playground repro check -f '$model' --json 2> /dev/null | jq -c '{files, blocks: [.blocks[].message], warnings}'"
lab_expect_contains '"blocks":["looks like an AWS access key id"]'
lab_expect_contains '"warnings":[]'
perl -i -ne 'print unless /AKIAABCDEFGHIJKLMNOP/' "$model"

log "Step 4: export"
lab_run playground repro export -f "$model" --dry-run
lab_expect_exit 0
lab_expect_contains "no 'playground run' found in playground-run-history, the bundle will not say which flags to use"
lab_expect_contains "👷‍♂️ 1 reproduction model(s)"
lab_expect_contains "▶️  playground run -f {repro_dir}/filestream-sink-repro-000000-deep-dive-lab-ci.sh"
lab_expect_contains "connect-connect-filestream-sink/README.md  (symlink to connect/connect-filestream-sink/README.md, stored as content)"
lab_expect_contains "📄 connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-ci.REPRO.md"
lab_expect_contains "✅ no secret nor customer data found"
lab_expect_contains "🔍 dry run: no bundle written"
lab_run playground repro export -f "$model" --output "$export_dir" --no-clipboard
lab_expect_exit 0
lab_expect_contains "📤 Exported bundle is available: ${export_dir}/playground_repro_filestream-sink-repro-000000-deep-dive-lab-ci_"
bundle=$(ls "$export_dir"/playground_repro_*.tgz | head -1)
lab_run tar tzf "$bundle"
lab_expect_contains "repro-manifest.json"
lab_expect_contains "connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-ci.sh"
lab_expect_contains "connect-connect-filestream-sink/docker-compose.plaintext.repro-000000-deep-dive-lab-ci.yml"
lab_expect_contains "connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-ci.REPRO.md" "the hand-off report"
lab_run bash -c "playground repro export -f '$model' --report-only 2> /dev/null"
lab_expect_exit 0
lab_expect_contains "# 🐞 000000 deep dive lab ci"
lab_expect_contains "| 🩹 status | lab only |"
lab_expect_contains "| 🧪 last verdict | 🐞 reproduced on"
lab_expect_contains "## ▶️ How to run it"
lab_expect_contains "## 🔀 What it changes compared with \`connect/connect-filestream-sink/filestream-sink.sh\`"
lab_expect_not_contains "📤 Exported bundle" "--report-only writes no bundle"
lab_run bash -c "tar xzOf '$bundle' repro-manifest.json | jq -c '.models[0] | {script, case, base_example, jira, status, verdict: .last_verdict.verdict, run_command}'"
lab_expect_contains '{"script":"connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-ci.sh","case":"000000","base_example":"connect/connect-filestream-sink","jira":"https://confluentinc.atlassian.net/browse/CC-1234","status":"lab only","verdict":"reproduced","run_command":"playground run -f {repro_dir}/filestream-sink-repro-000000-deep-dive-lab-ci.sh"}'

log "Step 5: import, with a conflict"
lab_run playground repro import -f "$bundle" --dry-run
lab_expect_exit 0
lab_expect_contains "🧬 based on connect/connect-filestream-sink"
lab_expect_contains "🩹 status: lab only"
lab_expect_contains "🧪 last verdict of the exporter: 🐞 reproduced on"
lab_expect_contains "📋 1 new, "
lab_expect_contains " identical, 0 conflicting file(s)" "your own model: every file identical, plus its new hand-off report"
lab_expect_contains "🔍 dry run: nothing imported"
echo "# a local change" >> "$model"
lab_run playground repro import -f "$bundle"
lab_expect_exit 1
lab_expect_contains "⚔️  conflict   connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-ci.sh"
lab_expect_contains "❌ 1 file(s) differ from your copy, nothing imported. Use --on-conflict rename (keeps yours) or --on-conflict overwrite"
lab_run playground repro import -f "$bundle" --on-conflict rename
lab_expect_exit 0
lab_expect_contains "imported as connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-ci-imported-$(date +%Y%m%d).sh"
lab_expect_contains "▶️  playground run -f ${imported}"
lab_expect_contains "📖 hand-off report: ${report}"
if [ ! -f "$imported" ]
then
    logerror "❌ $imported was not written"
    exit 1
fi
lab_run playground state get run.test_file
lab_expect_contains "$imported" "the imported model is now the current one"

log "Step 6: a model from the config the customer sent"
lab_run playground repro bootstrap --config "${root_dir}/tools/connector-config/fixtures/cfk-filestream-sink.yaml" -d "000000 deep dive lab ci config" --no-run
lab_expect_exit 0
lab_expect_contains "📄 --config: CFK Connector custom resource (spec.class, spec.taskMax, spec.configs), connector filestream-cfk, connector.class org.apache.kafka.connect.file.FileStreamSinkConnector"
lab_expect_contains "🔖 example to start from: connect/connect-filestream-sink/filestream-sink.sh (-f to pick another one)"
lab_expect_contains "value.converter.schema.registry.url: https://sr.prod.example.com:8081 → http://schema-registry:8081"
lab_expect_contains "📄 the connector config of the example is replaced with the one of cfk-filestream-sink.yaml"
lab_expect_contains "values of the example kept (they point to its systems): topics file"
lab_expect_contains "✨ Creating file ${config_model}"
lab_run sed -n '/^# 📄/,/^EOF/p' "$config_model"
lab_expect_contains "playground connector create-or-update --connector filestream-sink --wait << EOF"
lab_expect_contains '"file": "/tmp/output.json"' "the file of the example, that the scenario reads"
lab_expect_contains '"errors.deadletterqueue.topic.name": "dlq-cfk"' "the behaviour of the customer config"
lab_expect_contains '"errors.deadletterqueue.topic.replication.factor": "1"'
lab_expect_not_contains "sr-password" "secrets of the customer"
lab_expect_not_contains "customer-license"
lab_run bash -n "$config_model"
lab_expect_exit 0
lab_run playground repro check -f "$config_model" --skip-secrets-store
lab_expect_exit 0
lab_expect_contains "✅ no secret nor customer data found"

log "Step 7: clean up (in the EXIT trap: the models, their compose overrides and the imported copy)"

log "✅ all the outputs of the page are as expected"
