#!/bin/bash
# Script of the Text View (opened by the view_output external trigger, argument = job id):
# shows the output of a read-only playground command, see view() in kdp.py
PYTHONUTF8=1 PATH=/opt/homebrew/bin:/usr/local/bin:$PATH exec python3 "$(dirname "$0")/kdp.py" --view "$1"
