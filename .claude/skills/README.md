# Claude Code skills

Playbooks that [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) uses when a request matches their
description, or when called with `/<skill name>`. Start `claude` from the root of the repository so that they, `CLAUDE.md`
and `.claude/settings.json` are picked up.

| Skill | Use it to | Example |
| --- | --- | --- |
| [`kdp-new-example`](kdp-new-example/SKILL.md) | add a self-managed or fully managed connector example | `/kdp-new-example add the fully managed Zendesk Source connector` |
| [`kdp-pr-review`](kdp-pr-review/SKILL.md) | review a PR or a local diff against the repository rules | `/kdp-pr-review 9293` |
| [`playground-cli`](playground-cli/SKILL.md) | add or change a `playground` command, flag or help text | "add a --sort-by-size flag to playground topic list" |
| [`kdp-benchmark`](kdp-benchmark/SKILL.md) | measure or compare connector throughput, write a `benchmark-load.bash` | "is version 10.8 of the JDBC sink slower than 10.7?" |
| [`kdp-xstream-report`](kdp-xstream-report/SKILL.md) | analyze Oracle XStream CDC diagnostics reports | `/kdp-xstream-report orclcdc_diag_20261013_0912.html` |
| [`kdp-bump-cp-version`](kdp-bump-cp-version/SKILL.md) | update the default CP version (`TAG`), CI matrix and docs | `/kdp-bump-cp-version 8.4.0` |

Full documentation: <https://kafka-docker-playground.io/#/claude-code>. When you add a skill here, add it to this table
and to [`docs/claude-code.md`](../../docs/claude-code.md).
