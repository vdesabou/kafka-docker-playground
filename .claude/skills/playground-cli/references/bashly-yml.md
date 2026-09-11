# `bashly.yml` vocabulary as used in this repo

Reference for `scripts/cli/src/bashly.yml`. Official docs: https://bashly.dev.
Everything below is what the file actually uses today — prefer matching an
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
  - not_mdc_environment
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

## Anchors and aliases

Shared flags are declared once with a YAML anchor and reused everywhere. This
is the single most important convention in the file — duplicating a flag
definition instead of aliasing it causes drift in help text and completions.

Anchors currently defined (search `bashly.yml` for `&<name>` to see the full
definition):

`&verbose` · `&connector` · `&subject` · `&subject_required` ·
`&compatibility-required` · `&user` · `&environment` · `&environment-run` ·
`&tag` · `&connect-tag` · `&connector-tag` · `&connector-zip` · `&connector-jar` ·
`&cluster-cloud` · `&cluster-type` · `&cluster-region` · `&cluster-environment` ·
`&cluster-name` · `&cluster-creds` · `&cluster-schema-registry-creds` ·
`&enable-ksqldb` · `&enable-rest-proxy` · `&enable-control-center` ·
`&enable-flink` · `&enable-conduktor` · `&enable-multiple-brokers` ·
`&enable-multiple-connect-workers` · `&enable-jmx-grafana` · `&enable-kcat` ·
`&enable-sql-datagen`

Use them as `- *connector`. An anchor must appear earlier in the file than any
alias to it.

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
    - $(playground get-connector-list)
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
`oracle_running` · `not_mdc_environment` · `ccloud_environment` ·
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
filtering. Reference them from any flag with
`completions: [$(playground get-connector-list)]`.

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
