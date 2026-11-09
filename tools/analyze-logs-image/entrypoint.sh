#!/usr/bin/env bash
# Entry point of the kdp-analyze-logs image: playground analyze logs, with every flag.
#   docker run --rm --network none -v "$PWD":/data -e KDP_HOST_DIR="$PWD" ghcr.io/vdesabou/kdp-analyze-logs -f bundle.zip
# The folder mounted in /data is the current folder: relative paths (-f bundle.zip) and the default output folder
# (./log-analysis-output) are on the host. KDP_HOST_DIR, the same folder seen from the host: the paths printed and the ✏️
# links of the report use it (without it, the paths are printed relative to that folder and the report has no ✏️ link).

# PLAYGROUND_HOST_PATH_MAP=<folder in the container>=<folder on the host>, read by the CLI (shown_path) and by
# tools/report-common/log_viewer.py
export PLAYGROUND_HOST_PATH_MAP="/data=${KDP_HOST_DIR:-.}"

if ! mountpoint -q /data 2>/dev/null
then
    case " $* " in
        *" --sample "*|*" --help "*|*" -h "*) ;;
        *) echo "⚠️  nothing is mounted in /data: add -v \"\$PWD\":/data to docker run, the logs are read from there and the report is written there" >&2 ;;
    esac
fi

exec /kdp/scripts/cli/playground analyze logs "$@"
