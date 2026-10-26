---
name: kdp-bump-cp-version
description: |
  Update the default Confluent Platform (CP) version of kafka-docker-playground (for example 8.3.2 → 8.4.0):
  check that the images and the matching Apache Kafka clients are published, change the `# default tag` line
  of scripts/utils.sh, the `tag:` matrices and `update-readme --tags` of ci.yml, the docs and CLAUDE.md that
  state the default, the deep-dive lab pinned on it, regenerate the CLI, smoke-test one example, and (after
  asking) open the "👾⬆️ Upgrade playground to default CP <version>" issue + PR. Use when asked to update /
  bump / upgrade the default CP version or TAG, or when a new CP release is out.
---

# Update the default CP version

The default CP version is the `TAG` used when no `--tag` is given. It drives every `CP_*_TAG` (broker,
connect, schema registry, ksqlDB, REST proxy, cfk), the CI matrix and the README badges. Past bumps:
`git log --oneline --grep "default CP"` (e.g. `4a5c0c0ec 👾 Upgrade playground to default CP 8.3.2 #8844`).

Below, `OLD` is the current default and `NEW` the target version:

```bash
OLD=$(grep '# default tag' scripts/utils.sh | sed -E 's/.*TAG=([^ ]+) .*/\1/'); NEW=8.4.0; echo "$OLD -> $NEW"
```

## 1. Check that the release is usable

Every image that follows `TAG` must exist on Docker Hub, for amd64 and arm64:

```bash
for r in cp-server cp-server-connect cp-schema-registry cp-ksqldb-server cp-kafka-rest
do
  printf "%-20s " $r; curl -s -o /dev/null -w "%{http_code}\n" "https://hub.docker.com/v2/repositories/confluentinc/$r/tags/$NEW"
done
curl -s "https://hub.docker.com/v2/repositories/confluentinc/cp-server/tags?name=$NEW" | jq -r '.results[].name'   # NEW.amd64 / NEW.arm64
```

Anything other than `200`: stop, the release is not fully published yet.

The Kafka clients built by some examples (`-Dkafka.client.tag=$KAFKA_CLIENT_TAG`) need **no change**:
`set_kafka_client_tag` in `scripts/cli/src/lib/utils_function.sh` derives the Apache Kafka version from the CP
version (CP 8.y = AK 4.y…), and falls back to the newest published `X.Y.0` when Maven Central doesn't have it yet.
Check what it resolves to:

```bash
bash -c 'source scripts/cli/src/lib/utils_function.sh >/dev/null 2>&1; TAG_BASE='"$NEW"'; set_kafka_client_tag; echo $KAFKA_CLIENT_TAG'
```

Only edit that function if Confluent changes the CP ↔ AK numbering (a new CP major, a CP minor not
matching the AK minor): then fix the `case` there, never add an `if [[ $TAG_BASE = … ]]` per version.

## 2. Change the default

Branch off `master` first (`git switch -c default-cp-$NEW`). These lines state the default, change all of them:

| File | Line |
| --- | --- |
| `scripts/utils.sh` | `export TAG=$OLD # default tag` (`run-tests.sh` and `update-readme` grep that exact comment: keep the format) |
| `.github/workflows/ci.yml` | `tag: ["$OLD"]` in **both** matrices (nightly job and `workflow_dispatch` job), and `./playground update-readme --tags "$OLD"` |
| `CLAUDE.md` | `(currently \`TAG=$OLD\`)` in Conventions |
| `docs/how-to-use.md` | `(currently CP $OLD, which is KRaft only)` |
| `other/deep-dive-labs/run-and-versions.sh` | the target of `update-version --tag` / `--connect-tag` (so the lab reuses the default images); its quote in `docs/deep-dive-run-and-versions.md` (`--tag=$OLD is same as current tag, ignoring...`) |

```bash
sed -i '' "s/export TAG=$OLD # default tag/export TAG=$NEW # default tag/" scripts/utils.sh
sed -i '' "s/tag: \[\"$OLD\"\]/tag: [\"$NEW\"]/; s/update-readme --tags \"$OLD\"/update-readme --tags \"$NEW\"/" .github/workflows/ci.yml
sed -i '' "s/(currently \`TAG=$OLD\`)/(currently \`TAG=$NEW\`)/" CLAUDE.md
sed -i '' "s/(currently CP $OLD, which/(currently CP $NEW, which/" docs/how-to-use.md
sed -i '' "s/$OLD/$NEW/g" other/deep-dive-labs/run-and-versions.sh
sed -i '' "s/\`--tag=$OLD is same as current tag/\`--tag=$NEW is same as current tag/" docs/deep-dive-run-and-versions.md
grep -rn "$OLD" .github/ scripts/utils.sh CLAUDE.md docs/how-to-use.md other/deep-dive-labs/run-and-versions.sh   # must print nothing
```

(`sed -i ''` is the macOS form; on Linux use `sed -i`.)

**Leave alone** the other `$OLD` hits of `grep -rn "$OLD" docs/ scripts/cli/src/bashly.yml tools/`: they are
captured outputs (`confluentinc/cp-server:$OLD` in `playground status`, `8.3.2-ce` plugin versions, analyzer
samples recorded on that version, `--cp-version 7.9.0 --cp-version $OLD` examples). They stay true as written.

Then review what the new version changes for the playground, and fix it in the same PR when needed:

- the release notes of `NEW` (removed or renamed configs, JDK change, KRaft / ZooKeeper changes),
- version gates written for the previous line, such as `version_gt $TAG_BASE "8.2.99"` in `utils_function.sh` and
  `scripts/utils.sh`. They use "greater than", so a newer version is already on the right side: only check gates with an upper bound,
- `CFK_VERSION` in `environment/cfk/start.sh`: check that this CFK version supports CP `NEW` (CFK release notes),
  or bump it.

## 3. Regenerate and validate

```bash
playground bashly-reload                                                  # utils_function.sh is inlined into scripts/cli/playground
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest -no-color .github/workflows/ci.yml   # no new finding on the changed lines
```

Smoke test with the default tag (no `--tag`), then one java client example (it builds with `KAFKA_CLIENT_TAG`):

```bash
playground run -f "$PWD/connect/connect-filestream-sink/filestream-sink.sh"          # logs "💫 Using default CP version $NEW"
playground run -f "$PWD/other/schema-format-avro/start.sh"
```

Ask before running: `playground run` stops the running environment. Give the user a `tail -f` path for each run.

## 4. Issue and PR

Ask the user first (repo `CLAUDE.md`, "Contributing"). Title `👾⬆️ Upgrade playground to default CP <NEW>`,
label `enhancement ✨`, no milestone. Commit only the files above plus the regenerated `scripts/cli/playground`
(never `reproduction-models`). After the merge, the nightly CI runs the whole matrix on `NEW` and
`update-readme` refreshes the badges: watch the 🔥 issues of the next nightly for regressions specific to `NEW`.
