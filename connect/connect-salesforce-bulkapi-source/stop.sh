#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# The teardown used to run:
#   sfdx data:query -q "SELECT Id FROM Lead" --result-format csv > /tmp/out.csv
#   sfdx force:data:bulk:delete -s Lead -f /tmp/out.csv
# It has never worked. The redirect captures the CLI's own progress output
# ("Querying Data... done", "Total number of records retrieved: N") into the CSV, so every
# run ended in "InvalidBatch : Records not found" - observed on all four invocations of a
# recent CI run. That is also why a shared org accumulated hundreds of stale Leads despite
# an apparent "delete all Leads" teardown.
#
# It is removed rather than repaired: the query was unfiltered, so a working version would
# delete EVERY Lead in the org including hand-made sample data. Each test already removes
# exactly the records it created, in its own EXIT trap. A filtered sweep for leftovers from
# aborted runs can be added separately, matching only the test naming patterns.

stop_all "$DIR"