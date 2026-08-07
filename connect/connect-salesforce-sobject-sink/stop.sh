#!/bin/bash



DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# The unfiltered Lead sweep that used to run here never worked (the redirect captured the
# CLI's own progress output into the CSV) and would have deleted every Lead in the org if it
# had. Each test removes exactly the records it created, in its own EXIT trap.

stop_all "$DIR"