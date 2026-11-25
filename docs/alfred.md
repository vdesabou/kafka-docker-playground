# 🎩 Alfred workflow (macOS)

On macOS, the [Alfred](https://www.alfredapp.com/) workflow puts the most common lookups one keystroke away, without opening a terminal first (Alfred 5 with the Powerpack):

<video src="videos/kdp-alfred-workflow.mp4" autoplay loop muted playsinline controls width="100%"></video>

```bash
playground tools install-alfred-workflow          # builds it and opens it in Alfred, which asks to import it
playground tools install-alfred-workflow --link   # symlinks scripts/alfred-workflow/ instead, to work on it (run it again after an edit: it reloads the workflow)
```

Run it again after a `git pull` to update the workflow (`kdp` shows 🆕 when the clone has a newer one). Then type `kdp` in Alfred: the first line says what is running (↩ status, ⌘ re-run it, ⌥ stop it, ⇧ update versions). Or select text anywhere and use the Universal Action **kdp: config, stack trace, logs, connector class, key, case…**: a connector config (JSON, CFK / Strimzi YAML, terraform, properties) gets validate / convert / repro bootstrap, log lines or a stack trace `analyze logs`, a connector class its plugin and examples, a config key `kdp key`, a case number `kdp case`. It also takes files and folders selected in Finder (⌥⌘\ by default, several at once), and runs the matching `playground analyze` command with its HTML report opened right away: `analyze logs` for log files, folders, archives and CFK support bundles (⌘ `--errors-only`), `thread-dump` / `gc-logs` for a file whose name has `thread`, `jstack`, `tdump` or `gc` (plus `analyze logs`), `heap-dump` for a `.hprof`, `flight-recorder` for a `.jfr`, `tcp-dump` for a `.pcap`, `oracle-xstream-report` for an `orclcdc_diag*.html`, `jscissors` for a `jscissors*` folder:

| Query | What |
| --- | --- |
| `kdp find <words>` | [`playground find-example`](/playground%20find-example): ↩ copies `playground run -f …`, Tab opens the example: ▶️ run it in the terminal (the subtitle says what it stops), README, repro bootstrap |
| `kdp history [words]` | a past run: ↩ copies its exact command, Tab: 🔁 re-run it with the same flags, or without them |
| `kdp plugin <words> [version]` | pick the plugin in the Confluent Hub list (↩ fills it in, ⌘ Hub page, ⌥ source repository), then a version in its list (newest first, `10.7` narrows it), then `connector-plugin info`, `changelog`, `sourcecode`, `dependencies`, `cve-scan`. A connector class or a fully managed type (`S3_SINK`) works as typed |
| `kdp key <words>` | pick the key in the list of the keys of the connector references (`*/config-<class>.txt`, with the number of connectors, type, default, doc), then one of the connectors that have it: `connector-plugin config-key` (`--connector-class`, `--since-version`) |
| `kdp docs [words]` | the deep dive and toolkit pages of this site |
| `kdp connector [words]` | pick a running connector (❌ failed ones first, with the state of its tasks), then `connector diagnose`, `status`, `tasks`, `metrics`, `history`, `show-config`, `offsets get`, `topics`, and `restart --only-failed`, pause / resume |
| `kdp logs [container] [pattern]` | pick a container (`connect` first), then `container logs --errors` (with warnings, last 10 minutes), the last 300 lines, the lines matching a pattern, or ⌃ follow them in the terminal |
| `kdp topic [words]` | pick a topic (internal ones when the query starts with `_`), then `topic describe`, `get-number-records`, the last or first 10 records, the records matching a pattern, `topic dlq inspect` for a dead letter queue |
| `kdp schema [words]` | pick a subject, then `schema describe`, the latest schema, `schema history`, `schema diff`, `get-compatibility` |
| `kdp ci [words]` | pick a test directory of the CI matrix, then `get-ci-result` (with the logs and its HTML report), its 🔥 issues |
| `kdp status` | `status`, `connector status`, `connector diagnose`, connect errors, `broker health` |
| `kdp repro [words]` | reproduction models, yours first (when `reproduction-models/` has models): ↩ copies the run command, Tab opens its actions (`repro diff`, hand-off report, export, `repro status --set`) |
| `kdp notes [words]` | a notes folder, and the Claude Code session that wrote a note (when the folder exists) |
| `kdp case <number>` | ticket link, notes and repro models of a support case (`ticket_url` setting) |

On a result, ↩ copies the command (or opens the page), ⌘ opens the script in VS Code, ⌃ runs the command in the terminal (for an example, the subtitle says what it stops; a run started from the workflow posts a notification with its result when it ends), and ⌥ / ⇧ depend on the mode: hold the key to see what it does. Read-only commands (`plugin`, `key`, `status`, the repro hand-off report) show their output in the Alfred window, streamed while they run, with ✅ or ❌ and the exit code at the end. In that window, ↩ runs the command again, `watch` + ↩ runs it every 5 seconds (`watch 30`, `stop`), text + ↩ keeps the lines that contain it, ⇧↩ opens the HTML report the command wrote (`connector diagnose`, `topic dlq inspect`…), ⌘↩ copies the output and ⌥↩ the command; ⌃ on the result runs it in the terminal instead. Interactive ones (`playground run`, `claude`) always go to the terminal.

The workflow settings (Alfred Preferences > Workflows > kafka-docker-playground (kdp) > Configure Workflow) are:

| Setting | What |
| --- | --- |
| `kdp_root` | your clone, set by the install |
| Show output (`show_output`) | where read-only commands show their output: the Alfred window (default, needs Alfred 5.5 or later) or the terminal |
| Run in the terminal (`terminal`) | where terminal commands go: the terminal set in Alfred Preferences > Features > Terminal (default), **VS Code** (a new integrated terminal in the front window: the command is pasted there, so Alfred needs Accessibility in System Settings > Privacy & Security), **Terminal.app**, or **copy only** |
| `ticket_url` | for `kdp case`, for example `https://example.zendesk.com/agent/tickets/{}` |
| `notes_dir` | for `kdp notes` and `kdp case` |

> If a terminal item does nothing with the default setting, the application set in Alfred Preferences > Features > Terminal is probably not installed (a custom iTerm script left behind, for example): pick another one there, or another **Run in the terminal** value.

> [!NOTE]
> Working on the workflow itself (the nightly check, `--link` and `info.plist`): see [scripts/alfred-workflow/README.md](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/alfred-workflow/README.md).
