#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# the page's steps that call 'playground run' itself (two runs, history, re-run, a bad flag combination) can't run
# inside this script, which is already started by 'playground run': this lab covers the update-version steps

lab_require_plaintext

# the image of each container. Podman shows it fully qualified (docker.io/confluentinc/cp-server:8.2.0): drop the
# registry, so that the assertions hold with both engines
function lab_run_inspect_images () {
    lab_run docker inspect -f '{{.Name}} {{.Config.Image}}' "$@"
    LAB_OUTPUT=${LAB_OUTPUT//docker.io\//}
}

older_tag="8.2.0"
newer_tag=$(docker inspect -f '{{.Config.Image}}' connect 2> /dev/null | cut -d ":" -f 2)
newer_tag=${newer_tag:-$TAG}

log "Step 1: an older CP version"
# utils.sh derives the tag of every component (CP_KAFKA_TAG, CP_CONNECT_TAG…) from TAG when they are not set: clear
# them, then source it again with the older tag
for tag_variable in $(compgen -e | grep -E '^CP_[A-Z_]+_TAG$')
do
    unset "$tag_variable"
done
export TAG="$older_tag"
source ${DIR}/../../scripts/utils.sh
lab_start_environment
lab_create_filestream_sink
# the next commands must read the versions from the running containers, as in a terminal: don't pass the older tags on
for tag_variable in TAG TAG_BASE $(compgen -e | grep -E '^CP_[A-Z_]+_TAG$')
do
    unset "$tag_variable"
done
lab_run_inspect_images broker connect
lab_expect_contains "/broker confluentinc/cp-server:$older_tag"
lab_expect_contains "/connect confluentinc/cp-server-connect:$older_tag"

log "Step 3: connect only, on another version"
lab_run playground update-version --connect-tag 8.4.0
lab_expect_exit 0
lab_expect_contains "✨ Loading new version(s) based on flags ⛳ --connect-tag=8.4.0"
lab_expect_contains "💣 Detected confluent version change, restarting containers"
lab_expect_contains "Container connect Recreate"
lab_expect_not_contains "Container broker Recreate" "the broker keeps its version"
lab_run_inspect_images broker connect schema-registry
lab_expect_contains "/broker confluentinc/cp-server:$older_tag"
lab_expect_contains "/connect confluentinc/cp-server-connect:8.4.0"
lab_expect_contains "/schema-registry confluentinc/cp-schema-registry:$older_tag"
lab_run playground connector wait --connector filestream-sink --max-wait 180
lab_expect_exit 0

log "Step 4: every component"
lab_run playground update-version --tag 8.4.0
lab_expect_exit 0
lab_run_inspect_images broker connect
lab_expect_contains "/broker confluentinc/cp-server:8.4.0"
lab_expect_contains "/connect confluentinc/cp-server-connect:8.4.0"
lab_run playground update-version --tag 8.4.0
lab_expect_contains "--tag=8.4.0 is same as current tag, ignoring..."
lab_expect_not_contains "based on flags ⛳ =8.4.0" "no leftover of the ignored flag"

log "Step 5: what changed in Confluent Platform between two versions"
lab_run playground cp-changelog --from 8.3.0 --to 8.3.1
lab_expect_exit 0
lab_expect_contains "📜 Changes of Confluent Platform after 8.3.0 up to 8.3.1: 3 change(s) in 1 version(s)"
lab_expect_contains "🔢 8.3.1 - 📅 released: August 2026 - 3 change(s)"
lab_expect_contains "🔐 Update Netty to 4.1.135 (0eaea7a9)"
lab_expect_contains "🌐 changelog: https://docs.confluent.io/platform/8.3/release-notes/changelog.html"
lab_expect_not_contains "🔢 8.3.0 -"
lab_run playground cp-changelog --from 8.1.4 --to 8.3.2 --component schema-registry --grep "anyOf|allOf"
lab_expect_exit 0
lab_expect_contains "Handle anyOf/allOf in JSON transforms (560bf4ca)"
lab_expect_not_contains "🧩 ksqlDB"

log "✅ all the outputs of the page are as expected"
