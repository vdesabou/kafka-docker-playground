# kdp Alfred workflow: working on it

User documentation: [🎩 Alfred workflow](https://kafka-docker-playground.io/#/alfred). This page is for changes to the workflow itself.

```bash
playground tools install-alfred-workflow --link   # symlinks this folder into Alfred (run it again after an edit: it reloads the workflow)
```

A nightly CI check (`other/cli/alfred-workflow.sh`, `python3 scripts/alfred-workflow/check.py` locally) runs every mode headless and checks the answers, so a change of the JSON of a command breaks CI rather than the workflow.

With `--link`, Alfred writes your settings to `scripts/alfred-workflow/prefs.plist` (ignored by git), and may rewrite `info.plist` when you edit the workflow in Alfred Preferences: check `git diff` before committing.
