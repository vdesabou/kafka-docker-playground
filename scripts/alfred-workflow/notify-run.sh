#!/bin/bash
# Runs a command started from the kdp Alfred workflow (playground run -f …, re-run, stop, update-version) in the
# terminal, then posts a macOS notification with its result and duration, so you can work elsewhere meanwhile.
#   notify-run.sh playground run -f <script> [flags]
start=$(date +%s)
"$@"
rc=$?
d=$(( $(date +%s) - start ))
name="$*"
for ((i = 1; i < $#; i++))
do
    # the example of playground run -f <script>
    if [ "${!i}" = "-f" ]
    then
        j=$((i + 1))
        name=$(basename "${!j}")
    fi
done
if [ $rc -eq 0 ]
then
    msg="✅ done in $((d / 60))m$((d % 60))s"
else
    msg="❌ exit $rc after $((d / 60))m$((d % 60))s"
fi
osascript -e "on run argv" -e "display notification (item 2 of argv) with title (item 1 of argv)" -e "end run" \
    "kdp: $name" "$msg" > /dev/null 2>&1
exit $rc
