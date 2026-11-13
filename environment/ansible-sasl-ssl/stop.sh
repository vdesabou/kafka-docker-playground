#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
exec "${DIR}/../ansible/stop.sh" "$@"
