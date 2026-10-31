#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-tcp-proxy
# it runs the JDBC PostgreSQL source example itself (no credentials), then puts the Zazkia TCP proxy between the
# connector and postgres
lab_require_plaintext

# 'tcp-proxy start' and 'tcp-proxy open-ui' call 'open http://localhost:9191' when an 'open' command exists: a stub
# that only prints the URL, so that the lab never opens a browser (and doesn't depend on what 'open' is on Linux)
stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT
cat << 'EOF' > "$stub_dir/open"
#!/bin/bash
echo "(lab) not opening $*"
EOF
chmod +x "$stub_dir/open"
export PATH="$stub_dir:$PATH"

# wait_for_zazkia_links <ids to ignore>: prints the ids of the active Zazkia connections once there is at least one
# and the list differs from <ids to ignore> (a new connection after a close), waits up to 120 seconds
function wait_for_zazkia_links () {
    local previous="$1" ids="" waited=0
    while [ $waited -lt 120 ]
    do
        ids=$(playground get-zazkia-connection-list 2> /dev/null || true)
        if [ -n "$ids" ] && [ "$ids" != "$previous" ]
        then
            echo "$ids"
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done
    echo ""
}

log "Step 0: the JDBC PostgreSQL source example"
(cd "${DIR}/../../connect/connect-jdbc-postgresql-source" && bash postgres.sh)

log "Step 1: before start, there is no proxy to talk to"
lab_run playground tcp-proxy get-connections
lab_expect_exit 1
lab_expect_contains "❌ curl request failed with error code"

log "Step 2: put the proxy between the connector and postgres"
# outside CI (GITHUB_RUN_NUMBER not set), start asks 'Continue (y/n)?' before updating the connector: answer y
lab_run playground tcp-proxy start --hostname postgres --port 5432 <<< "y"
lab_expect_exit 0
lab_expect_contains "💫 adding container zazkia listening on port 49998"
lab_expect_contains "💗 you can now use zazkia tcp proxy using <zazkia:49998>"
lab_expect_contains "🌐 zazkia UI is available on http://localhost:9191"
lab_expect_contains "🔮 checking existence of hostname postgres and port 5432 in connector postgres-source configuration to replace with zazkia and port 49998"
lab_expect_contains "replacing postgres:5432 by zazkia:49998"
lab_expect_contains "💫 updating connector postgres-source configuration with"
lab_expect_contains "jdbc:postgresql://zazkia:49998/postgres"
lab_run playground connector show-config --connector postgres-source --force-rest-endpoint
lab_expect_exit 0
lab_expect_contains "zazkia:49998"
lab_expect_not_contains "postgres:5432"

log "Step 3: the connections going through the proxy"
ids=$(wait_for_zazkia_links "")
[ -n "$ids" ] || { logerror "❌ no connection went through zazkia after 120 seconds"; exit 1; }
log "🧲 active Zazkia connections: $ids"
lab_run playground tcp-proxy get-connections
lab_expect_exit 0
lab_expect_contains '"state": {'
lab_expect_contains '"delay-service-response": 0'
lab_expect_contains '"receiving-from-service": true'
lab_expect_contains '"stats": {'
lab_expect_contains '"bytesReceivedFromService":'

log "Step 4: a slow database"
lab_run playground tcp-proxy delay --delay-service-response 2000
lab_expect_exit 0
lab_expect_contains "⏲️ Add 2000 milliseconds delay to service response for connection id"
lab_expect_contains '"delay-service-response": 2000'
lab_run playground tcp-proxy delay --delay-service-response 0
lab_expect_exit 0
lab_expect_contains '"delay-service-response": 0'

log "Step 5: break the responses, then kill the connections"
lab_run playground tcp-proxy break --break-service-response 100
lab_expect_exit 0
lab_expect_contains "💔 Break sending the response to the client for 100 % for connection id"
lab_expect_contains '"break-service-response": 100'
ids=$(playground get-zazkia-connection-list 2> /dev/null || true)
lab_run playground tcp-proxy close-connection
lab_expect_exit 0
lab_expect_contains "❌ closing connection id"
# does the connector reconnect by itself? a new connection gets the defaults of the route (no break)
new_ids=$(wait_for_zazkia_links "$ids")
[ -n "$new_ids" ] || { logerror "❌ the connector did not open a new connection through zazkia after 120 seconds"; exit 1; }
log "🧲 new Zazkia connections: $new_ids"
lab_run playground tcp-proxy get-connections
lab_expect_exit 0
lab_expect_contains '"break-service-response": 0'
lab_run playground connector wait --connector postgres-source --max-wait 120
lab_expect_exit 0

log "Step 6: refuse new connections, then accept them again"
lab_run playground tcp-proxy toggle-accept-connections
lab_expect_exit 0
lab_expect_contains "🙅‍♂️ Change whether new connections can be accepted"
lab_expect_equals "$(tail -1 <<< "$LAB_OUTPUT")" "false" "accept-connections after the first toggle"
lab_run playground tcp-proxy toggle-accept-connections
lab_expect_exit 0
lab_expect_equals "$(tail -1 <<< "$LAB_OUTPUT")" "true" "accept-connections after the second toggle"

log "Step 7: a black hole in one direction"
lab_run playground tcp-proxy toggle-reads-service
lab_expect_exit 0
lab_expect_contains "✅ toggle-reads-service for connection id"
lab_expect_contains "200"
lab_run playground tcp-proxy get-connections
lab_expect_exit 0
lab_expect_contains '"receiving-from-service": false'
lab_run playground tcp-proxy toggle-reads-service
lab_expect_exit 0
lab_expect_contains "200"

log "Step 8: clean up and the UI"
lab_run playground tcp-proxy close-all-connection-with-error
lab_expect_exit 0
lab_expect_contains "🧹 Close all Zazkia TCP connections which are in error state"
lab_expect_contains "200"
lab_run playground tcp-proxy open-ui
lab_expect_exit 0
lab_expect_contains "🧲 Open Zazkia UI"

log "✅ all the outputs of the page are as expected"
