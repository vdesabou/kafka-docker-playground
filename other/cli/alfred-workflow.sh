#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# headless check of the kdp Alfred workflow (scripts/alfred-workflow): info.plist, every mode returns valid Alfred
# JSON, the output view; no Alfred and no environment needed (playground tools install-alfred-workflow installs it)
log "🎩 Checking the kdp Alfred workflow"
python3 -I "${DIR}/../../scripts/alfred-workflow/check.py" --root "${DIR}/../.."
