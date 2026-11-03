# bashly config vocabulary as used in this repo

Reference for the command tree: `scripts/cli/src/bashly.yml` (global settings
and the `- import:` lines only), one `scripts/cli/src/commands/<command>.yml`
per top-level command, and the flags shared by several commands in
`scripts/cli/src/flags/`. Official docs: https://bashly.dev.
Everything below is what those files actually use today — prefer matching an
existing pattern over inventing one.

## Top level

```yaml
name: playground
version: 1.0.0
dependencies:
  docker: visit https://docs.docker.com/get-docker to install
help: |-
  🧠 CLI for Kafka Docker Playground 🐳
filters:
- docker_running          # applies to every command
help_header_override: |   # the ASCII-art banner
  echo ...
flags:                    # global flags: --vvv / -v, --output-level / -o
commands:
```

`scripts/cli/settings.yml` holds the Bashly settings: `source_dir: src`,
`commands_dir: commands`, `lib_dir: lib`, `target_dir: .`,
`env: development` (file markers kept in the generated script),
`compact_short_flags: true`, `strict: false`.

## Defining a command

```yaml
- name: connector
  expose: always          # show subcommands in the parent's help
  group: Connector        # heading in `playground --help`
  filters:
  - not_ccloud_environment
  help: |-
    🔗 Connector commands

  commands:
  - name: pause
    help: ⏸️  Pause connector
    flags:
    - *verbose
    - *connector
```

Nesting maps directly to the filesystem:

| Command | Partial |
| --- | --- |
| `playground status` | `src/commands/status.sh` |
| `playground connector pause` | `src/commands/connector/pause.sh` |
| `playground connector offsets get` | `src/commands/connector/offsets/get.sh` |

A parent command that only groups subcommands needs no partial of its own.

## Shared flags, anchors and aliases

Duplicating a flag definition instead of sharing it causes drift in help text
and completions. There are two mechanisms, and which one to use depends only on
whether the flag is shared **across** command files:

**1. Across top-level commands → a file in `src/flags/`.** A YAML anchor cannot
cross files (`Psych::AnchorNotDefined`), so these live on their own:

```yaml
    flags:
    - import: src/flags/verbose.yml
```

Available today: `verbose` · `cluster` · `container` · `tag` · `connect-tag` ·
`connector-tag` · `connector-zip` · `connector-jar` · `force-refresh` ·
`level` · `compatibility-required`, plus the list groups
`analyze-thread-dump-flags` · `analyze-heap-dump-flags` · `analyze-logs-flags` ·
`analyze-gc-logs-flags` · `analyze-cfk-bundle-flags`.

`import` replaces one list item, so a file holding a **list** of flags cannot be
imported — it is included with ERB, which bashly runs over the config before
loading it. The line starts at column 0 and the `gsub` string is the
indentation of the result:

```yaml
  flags:
<%= File.read('src/flags/analyze-thread-dump-flags.yml').gsub(/^(?=.)/, '    ') %>
```

Paths in `import:` and `File.read` are relative to `scripts/cli/`, never to the
importing file.

**2. Inside one command file → a YAML anchor**, for a flag reused by several
subcommands of the same command (`&connector` / `*connector`, used 27 times in
`commands/connector.yml`; `&context`, `&json`, `&subject_required` in
`commands/schema.yml`; `&rbac-*` in `commands/rbac.yml`; `&quota-*` in
`commands/quota.yml`…). The anchor must
appear earlier in the file than any alias to it. Use it as `- *connector`.

When a flag that is an anchor today is needed by a second top-level command,
move it to `src/flags/` instead of copying it.

## Flag and argument attributes

```yaml
- long: --connector
  short: -c
  arg: connector          # flag takes a value
  required: false
  default: "plaintext"
  repeatable: true        # may be passed several times
  allowed: [INFO, WARN, ERROR]
  conflicts: [--other-flag]
  needs: [--other-flag]
  validate: validate_not_empty
  completions:
    dynamic:
    - playground get-connector-list
  help: |-
    🔗 Connector name

    🎓 Tip: If not specified, the command will apply to all connectors
```

## Validators

Files in `src/lib/validations/`, each defining `validate_<name>()` that echoes
an error message (via `logerror`) when the value is invalid:

`validate_not_empty` · `validate_integer` · `validate_percentage` ·
`validate_json` · `validate_date_format` · `validate_dir_exists` ·
`validate_editor_exists` · `validate_file_exists` ·
`validate_file_exists_with_trick` · `validate_file_exists_and_avro` ·
`validate_file_exists_and_log` · `validate_file_exists_and_hprof` ·
`validate_file_exists_and_parquet` · `validate_minimal_cp_version`

To add one, create `src/lib/validations/validate_<name>.sh` and reference it
with `validate: validate_<name>`.

## Filters

Preconditions checked before a command runs. Implemented as `filter_<name>()`
in `src/lib/cli_function.sh`, referenced without the `filter_` prefix:

`docker_running` · `connect_running` · `schema_registry_running` ·
`oracle_running` · `not_ccloud_environment` · `ccloud_environment` ·
`cfk_environment` · `plaintext_or_ccloud_environment` · `aws_ec2_permissions`

## Completion-provider commands

Dynamic completions come from `private: true` commands that print candidates,
one per line:

```yaml
- name: get-connector-list
  help: Return some completion for connector list
  private: true

- name: get-ec2-instance-list
  help: Return some completion for ec2 instance list
  private: true
  args:
  - name: cur
    required: false
    help: correspond to completion $cur
```

Those taking `cur` receive the partial word being completed, for fzf-style
filtering. Reference them from any arg/flag with (bashly 2.x format):

```yaml
completions:
  dynamic:
  - playground get-ec2-instance-list "$completion_current"
  # static: [a, b]                 # literal candidates
  # options: [files, no-space]     # files | directories | no-space
```

Some completion sources are cached files at `scripts/cli/` — `tag-list.txt`,
`connect-tag-list.txt`, `confluent-hub-plugin-list.txt`,
`get_examples_list_with_fzf*` — all gitignored and refreshed by the
`generate-*` / `update-cache-versions` commands.

## Groups

`group:` values in use: Cloud Resources, Connector, Connector-Plugin,
Container, Debug, EC2, Kafka, Repro, Run, Schema, TCP Proxy, Tools, Topic.

## Examples

`examples:` entries show up in `--help` and, because
`show_examples_on_error: true`, also when the user gets the invocation wrong.
Write them as full copy-pasteable invocations.

Bashly prints examples (and `footer:`) with `printf "..."`: `"`, `` ` `` and `%`
are escaped, but **`$` is not**. Write `\$PWD`, `\$schema`: an unescaped `$VAR`,
`${...}` or `$(...)` would be expanded, or run, every time `--help` is shown.
The markdown template turns `\$` back into `$` for the docs. Lines longer than
78 characters are wrapped in `--help` (not in `footer:`).

### Example output

For read-only commands whose output helps understand them (`status`,
`connector diagnose`, `topic get-offsets`, …), add a real, sanitized output
(no colours, no user paths, no `reproduction-models/` names or case numbers,
trimmed with `...`):

```yaml
  x_example_outputs:
  - command: playground topic get-number-records --topic filestream
    output: |-
      17:22:53 ℹ️ 💯 Get number of records in topic filestream
      5
```

`x_example_outputs` is a custom key rendered by `templates/markdown/markdown.gtx`
on the documentation site only. For the few commands agents rely on most, also
add a `footer:` (`Example output:` then the output indented) so that it shows at
the end of `--help`; footers are not shown on usage errors. `playground
bashly-reload` fails if an `x_example_outputs` command does not start with the
full command name, or if an example or footer contains an unescaped `$`.
Refresh the output when you change what the command prints.
