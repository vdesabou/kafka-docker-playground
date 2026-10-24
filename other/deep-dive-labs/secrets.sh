#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-secrets
# no container: a throwaway store with the file backend, so that it runs anywhere (the 1Password steps of the page
# need a 1Password account and are not replayed here)
lab_require_plaintext

EXAMPLE="${DIR}/../../connect/connect-servicenow-sink/servicenow-sink.sh"
LEAK_FILE="${DIR}/secrets-lab-leak.txt"
OLD_PROFILE=$(playground config get secrets.profile)

export PLAYGROUND_SECRETS_DIR=$(mktemp -d)
export PLAYGROUND_SECRETS_BACKEND=file
unset PLAYGROUND_SECRETS_PROFILE
# CI exports the real ones: the lab starts from an empty shell
unset SERVICENOW_URL SERVICENOW_PASSWORD DD_API_KEY DD_APP_KEY DD_SITE

function cleanup () {
    rm -rf "$PLAYGROUND_SECRETS_DIR" "$LEAK_FILE" /tmp/secrets-lab-files
    playground config set secrets.profile "${OLD_PROFILE:-default}" > /dev/null
}
trap cleanup EXIT

log "Step 1: what does the example need?"
lab_run playground secrets check -f "$EXAMPLE"
lab_expect_exit 1
lab_expect_contains "❌ SERVICENOW_PASSWORD missing 👉 playground secrets set SERVICENOW_PASSWORD"
lab_expect_contains "❌ SERVICENOW_URL missing 👉 playground secrets set SERVICENOW_URL"
lab_expect_contains "❌ 2 variable(s) missing, the example would fail"

log "Step 2: store them, the name decides where"
lab_run playground secrets set SERVICENOW_URL --value https://dev12345.service-now.com/
lab_expect_contains "📝 SERVICENOW_URL=https://dev12345.service-now.com/ stored in profile default as a plain variable"
lab_expect_contains "🎓 SERVICENOW_URL does not look like a credential, so it is kept in clear text in ${PLAYGROUND_SECRETS_DIR}/env.ini"
lab_run playground secrets set SERVICENOW_PASSWORD --value 'Demo-Passw0rd-1234'
lab_expect_contains "🔐 SERVICENOW_PASSWORD stored in profile default (backend: file)"
lab_expect_equals "$(stat -c %a "${PLAYGROUND_SECRETS_DIR}/secrets.ini" 2>/dev/null || stat -f %Lp "${PLAYGROUND_SECRETS_DIR}/secrets.ini")" "600" "mode of secrets.ini"

log "Step 3: values are never printed"
lab_run playground secrets list
lab_expect_contains "SERVICENOW_PASSWORD file ****1234 (18 chars, sha256:6d910ac4)"
lab_expect_contains "SERVICENOW_URL plain https://dev12345.service-now.com/"
lab_run playground secrets get SERVICENOW_PASSWORD
lab_expect_contains "🔐 SERVICENOW_PASSWORD ****1234 (18 chars, sha256:6d910ac4)"
lab_run playground secrets check -f "$EXAMPLE"
lab_expect_exit 0
lab_expect_contains "🔐 SERVICENOW_PASSWORD set (file: secrets.ini)"
lab_expect_contains "🔐 SERVICENOW_URL set (plain: https://dev12345.service-now.com/)"
lab_expect_not_contains "Demo-Passw0rd-1234" "the password in clear"
lab_expect_contains "✅ Everything this example needs is available"

log "Step 4: an exported variable always wins"
lab_run env SERVICENOW_PASSWORD=from-my-shell-1234 playground secrets list
lab_expect_contains "SERVICENOW_PASSWORD file ****1234 (18 chars, sha256:6d910ac4) ⚠️ overridden by the environment"
lab_run env SERVICENOW_PASSWORD=from-my-shell-1234 playground secrets get SERVICENOW_PASSWORD
lab_expect_contains "🔐 SERVICENOW_PASSWORD ****1234 (18 chars, sha256:f1e0ed75)" "the value of the shell, not the store"

log "Step 5: one profile per case, falling back to default"
lab_run playground secrets profile case-123456
lab_expect_contains "🗂️ Active secrets profile is now case-123456 (0 variable(s))"
lab_run playground secrets set SERVICENOW_PASSWORD --value 'Customer-Pass-9876'
lab_expect_contains "🔐 SERVICENOW_PASSWORD stored in profile case-123456 (backend: file)"
lab_run playground secrets profile
lab_expect_contains "👉 case-123456 (1 variable(s))"
lab_expect_contains "default (2 variable(s))"
lab_run playground secrets check -f "$EXAMPLE"
lab_expect_contains "servicenow-sink.sh (secrets profile: case-123456)"
lab_expect_contains "🔐 SERVICENOW_URL set (plain: https://dev12345.service-now.com/)" "SERVICENOW_URL comes from default"
lab_run bash -c "playground secrets env -f '$EXAMPLE'"
lab_expect_contains "export SERVICENOW_PASSWORD='Customer-Pass-9876'"
lab_expect_contains "export SERVICENOW_URL='https://dev12345.service-now.com/'"
lab_expect_contains "🔐 2 variable(s) exported for servicenow-sink.sh (profile case-123456)"
lab_run playground secrets profile default
lab_expect_contains "🗂️ Active secrets profile is now default (2 variable(s))"

log "Step 6: secrets env refuses to print to a terminal"
if command -v script > /dev/null 2>&1
then
    if [[ "$OSTYPE" == "darwin"* ]]
    then
        lab_run script -q /dev/null playground secrets env -f "$EXAMPLE"
    else
        lab_run script -qec "playground secrets env -f '$EXAMPLE'" /dev/null
    fi
    lab_expect_contains "❌ stdout is a terminal, every value would be printed in clear on screen"
    lab_expect_not_contains "Demo-Passw0rd-1234" "the password in clear"
fi

log "Step 7: import an old secret.properties"
mkdir -p /tmp/secrets-lab-files
cat > /tmp/secrets-lab-files/secret.properties << 'EOT'
# my old secret.properties
export DD_API_KEY="dd-api-0123456789abcdef"
DD_APP_KEY='dd-app-fedcba9876543210'
DD_SITE=datadoghq.eu
lowercase=skipped
EOT
lab_run playground secrets import --file /tmp/secrets-lab-files/secret.properties --shred
lab_expect_contains "🔐 DD_API_KEY stored in profile default (backend: file)"
lab_expect_contains "📝 DD_SITE=datadoghq.eu stored in profile default as a plain variable"
lab_expect_contains "⏭️ skipping <lowercase>, not an uppercase environment variable name"
lab_expect_contains "✅ Imported 2 secret(s) and 1 plain variable(s), 1 skipped"
lab_expect_equals "$(ls /tmp/secrets-lab-files)" "" "the source file is shredded"
lab_run playground secrets list
lab_expect_contains "DD_API_KEY file ****cdef (23 chars, sha256:69705789)"

log "Step 8: a stored password pasted in the repository"
# the values above are written in this script, which would be found too: a profile of its own, with a value that
# exists nowhere in the repository
LEAK_VALUE="leak-$RANDOM-$RANDOM-$RANDOM"
playground secrets set SERVICENOW_PASSWORD --value "$LEAK_VALUE" --profile scan-lab
lab_run playground secrets scan --profile scan-lab
lab_expect_exit 0
lab_expect_contains "✅ No stored secret value found"
echo "curl -u admin:${LEAK_VALUE} https://dev12345.service-now.com/" > "$LEAK_FILE"
lab_run playground secrets scan --profile scan-lab
lab_expect_exit 1
lab_expect_contains "🚨 the value of SERVICENOW_PASSWORD appears in:"
lab_expect_contains "other/deep-dive-labs/secrets-lab-leak.txt"
lab_expect_contains "🚨 1 secret(s) found in clear text — do not commit"
rm -f "$LEAK_FILE"

log "Step 9: export, only outside the repository"
cd "${DIR}"
lab_run playground secrets export --file ./x.properties --yes-i-want-plaintext
lab_expect_exit 1
lab_expect_contains "❌ refusing to write credentials inside the repository"
lab_expect_equals "$(ls ./x.properties 2>/dev/null)" "" "nothing written in the repository"
lab_run playground secrets export --file /tmp/secrets-lab-files/plain.properties --only plain --yes-i-want-plaintext
lab_expect_contains "📤 Exported 2 variable(s) of profile default"
lab_expect_equals "$(cat /tmp/secrets-lab-files/plain.properties)" "$(printf 'DD_SITE=datadoghq.eu\nSERVICENOW_URL=https://dev12345.service-now.com/')" "only the plain variables"

log "Step 10: unset"
lab_run playground secrets unset DD_APP_KEY
lab_expect_contains "🗑️ DD_APP_KEY removed from profile default"
lab_run playground secrets unset DD_APP_KEY
lab_expect_contains "🤔 DD_APP_KEY is not stored in profile default"

log "✅ all the outputs of the page are as expected"
