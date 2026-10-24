# 🍪 Deep dive: credentials (`playground secrets`) and the 1Password setup

Examples that talk to a real service need credentials: a Salesforce password, a ServiceNow instance, a Datadog API key,
a Confluent license. `playground secrets` stores them **once, outside the repository**, with the values in a real
secret manager (macOS Keychain, 1Password, pass…), and `playground run` loads exactly the ones the example at hand
declares. This page explains the store, the backends, and how to set up 1Password step by step: with the desktop app,
with a service account for headless use, and with a shared vault for team credentials. Takes about 20 minutes to read
and run.

> [!TIP]
> The video session [🕹️ Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags)
> ends on `playground secrets set`, and the short clip in [Start an example](/how-to-use?id=🏎️-start-an-example) shows
> `secrets check` and `secrets set`. This page goes further: where the values really are, the 1Password setup, the
> gotchas, a hands-on lab and recipes for support repros.

| You want | Command |
| --- | --- |
| what an example needs, and what is missing | `playground secrets check -f <example>` |
| store a credential (prompted, never in the shell history) | `playground secrets set <NAME>` |
| what is stored, without printing values | `playground secrets list` (`--show-source` for the references) |
| move an old `secret.properties` into the store | `playground secrets import --file <file> --shred` |
| use 1Password | `playground secrets backend op` (+ `playground config set secrets.op-vault <vault>`) |
| reuse a secret you already have, in any vault | `playground secrets link <NAME> op://<vault>/<item>/<field>` |
| one set of credentials per support case | `playground secrets profile case-123456` |
| the variables of an example in the current shell | `source <(playground secrets env -f <example>)` |
| check that no stored value was pasted in the repository | `playground secrets scan` (`--staged` before a commit) |

---

## 1. Mental model (the 3 things to remember)

1. **The store holds references, the backend holds values.** Everything lives in `~/.config/kafka-docker-playground`
   (`PLAYGROUND_SECRETS_DIR` to change it), never in the repository: it survives `git clean -fdx`, it can't be
   committed, and it never ends up in a `playground repro export` bundle. Two files, one `[profile]` section each:

   | File | Mode | Holds |
   | --- | --- | --- |
   | `secrets.ini` | `0600` | `NAME = <reference>`: `op://kafka-docker-playground/kdp-default-SALESFORCE_PASSWORD/password`, `keychain:default:SALESFORCE_PASSWORD`… (the value itself only with the `file` backend) |
   | `env.ini` | `0644` | non sensitive variables in clear text: `SERVICENOW_URL`, `GCP_PROJECT`, `AWS_REGION`, user names |

   The **name** decides which file a variable goes to: a name containing `PASSWORD`, `PASSPHRASE`, `SECRET`, `TOKEN`,
   `KEY`, `CREDS`, `PWD` or `LICENSE` is a credential, anything else a plain variable. `--secret` / `--plain` on
   `secrets set` and `secrets import` override the guess.

2. **An exported variable always wins.** A value is resolved in this order:

   1. an exported environment variable (`export FOO=bar`, `source secret.properties`, a GitHub Actions secret)
   2. the active profile
   3. the `default` profile

   So nothing breaks for whoever still exports their credentials, and **a value rotated in the store is ignored as long
   as an old `export` is still in the shell**. `secrets list` flags it with `⚠️ overridden by the environment`.

3. **Only what the example declares is loaded.** `playground run` reads the list from the example itself: every
   variable checked with the standard error string `<NAME> is not set. Export it as environment variable or pass it as
   argument`, plus a few read by shared helpers (Confluent Cloud cluster and API key for ccloud examples,
   `AWS_ACCESS_KEY_ID`… for `handle_aws_credentials`, `NGROK_AUTH_TOKEN` / `BORE_SERVER`, Azure service principal).
   It resolves those in one parallel batch and exports them into the example's process only, never the whole store
   into your shell:

   ```text
   🔐 Loaded from secrets profile default: SERVICENOW_PASSWORD SERVICENOW_URL
   ```

---

## 2. What an example needs: `check`, and the run pre-flight

```bash
playground secrets check -f connect/connect-servicenow-sink/servicenow-sink.sh
```

```text
🔍 connect/connect-servicenow-sink/servicenow-sink.sh (secrets profile: default)

❌ SERVICENOW_PASSWORD missing        👉 playground secrets set SERVICENOW_PASSWORD
❌ SERVICENOW_URL missing        👉 playground secrets set SERVICENOW_URL

❌ 2 variable(s) missing, the example would fail
```

Exit code 1 when something is missing, so it fails in a second instead of several minutes into the environment
startup. Once stored, each line says where the value comes from (the reference for a secret, the value for a plain
variable, `environment` for an exported one):

```text
🔐 SERVICENOW_PASSWORD set (op: op://kafka-docker-playground/kdp-default-SERVICENOW_PASSWORD/password)
🔐 SERVICENOW_URL set (plain: https://dev12345.service-now.com/)

✅ Everything this example needs is available
```

AWS and GCP examples also get `~/.aws/credentials` (or `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) and the
example's `keyfile.json` (or `GCP_KEYFILE_CONTENT`) checked.

`playground run` does the same check before anything is stopped:

- **with the menu**, a missing variable replaces 🚀 with a prompt for its value, then asks
  `Save SERVICENOW_PASSWORD for next time? (playground secrets)`: answer yes and it is stored with the current backend.
- **with `-f`**, it refuses to start, and your running environment is left alone:

  ```text
  ❌ Cannot run …/connect/connect-servicenow-sink/servicenow-sink.sh, missing environment variable(s): SERVICENOW_PASSWORD SERVICENOW_URL
  👉 playground secrets set SERVICENOW_PASSWORD
  👉 playground secrets set SERVICENOW_URL
  ```

- **in CI** (`GITHUB_RUN_NUMBER` set) the pre-flight is skipped, so that the example keeps control of its exit code
  (`111` for an unsupported combination).

> [!NOTE]
> A variable an example reads without the standard error string is invisible to `check`, `run` and `env`. A new example
> must use it (`playground secrets lint`, a private command, lists the examples that don't).

---

## 3. Storing: `set`, `import`, `list`, `get`, `unset`

```bash
playground secrets set SERVICENOW_URL --value https://dev12345.service-now.com/
playground secrets set SERVICENOW_PASSWORD          # prompted, input hidden
```

```text
📝 SERVICENOW_URL=https://dev12345.service-now.com/ stored in profile default as a plain variable
🎓 SERVICENOW_URL does not look like a credential, so it is kept in clear text in ~/.config/kafka-docker-playground/env.ini
👉 playground secrets set SERVICENOW_URL --secret to put it in op instead
🔐 Enter value for SERVICENOW_PASSWORD (input hidden):
🔐 SERVICENOW_PASSWORD stored in profile default (backend: op)
```

- **Prefer the prompt to `--value`**: `--value` lands in the shell history. A value can't contain a newline: point the
  example at a file for a PEM or a key file.
- **Running `set` again rotates the value where the existing reference points**, not in the backend currently
  configured: a password stored in 1Password stays in 1Password after you switch to keychain, and a linked item is
  edited in place (see the 1Password gotchas).
- **Changing `--plain` / `--secret` moves the variable**: promoted to `--secret`, its clear text copy is removed from
  `env.ini`; demoted to `--plain`, the backend item is deleted.

`list` and `get` never print a value. A secret is shown as a **fingerprint**: the last 4 characters, the length and a
sha256 prefix, enough to tell "is this the token I rotated yesterday?":

```text
🔐 Secrets in profile default (~/.config/kafka-docker-playground)

NAME                                          BACKEND        VALUE
----                                          -------        -----
DD_API_KEY                                    file           ****cdef (23 chars, sha256:69705789)
DD_SITE                                       plain          datadoghq.eu
SERVICENOW_PASSWORD                           file           ****1234 (18 chars, sha256:6d910ac4)  ⚠️ overridden by the environment
SERVICENOW_URL                                plain          https://dev12345.service-now.com/
```

| Marker | Means |
| --- | --- |
| `⚠️ overridden by the environment` | an exported variable is what the example will get, not the store. The fingerprint is the stored value; `secrets get` shows the one that wins |
| `❌ cannot be resolved` | the reference is there, the backend returned nothing: locked or expired session, deleted item, a vault you can't read |

`get --reveal` prints the value (it stays in your scrollback). `list` shows one profile at a time: a variable that
comes from the `default` fallback is listed under `default`, not under the active profile.

**Migrating from `secret.properties`.** `import` sorts each `KEY=value` line into the right store. It understands
`export`, comments, blank lines and one level of quotes, and skips (with a warning) anything that isn't an uppercase
variable name. It does **not** run the shell: `"$(cat ~/key)"` or `$HOME/x` would be stored as is.

```bash
playground secrets import --file ~/secret.properties --shred     # --shred deletes the file once imported
```

```text
📥 Importing ~/secret.properties into profile default (backend: op)
🔐 DD_API_KEY stored in profile default (backend: op)
🔐 DD_APP_KEY stored in profile default (backend: op)
📝 DD_SITE=datadoghq.eu stored in profile default as a plain variable
⏭️ skipping <lowercase>, not an uppercase environment variable name
✅ Imported 2 secret(s) and 1 plain variable(s), 1 skipped
🔥 Securely deleting ~/secret.properties
```

Then **remove the old `export` lines and `source …/secret.properties` from your shell profile, and open a new
terminal**: until then, the exported values keep winning (3 things to remember, #2).

`unset` removes the variable **and its value**: the keychain entry is deleted, the 1Password item archived. A linked
reference is only forgotten, see the 1Password gotchas for the exception. `secrets edit` opens `secrets.ini` (`--plain`
for `env.ini`) in your editor, to rename a variable or move it between profiles.

---

## 4. Backends: where the values are

| Backend | Uses | Writes | Reference in `secrets.ini` |
| --- | --- | --- | --- |
| `keychain` | macOS Keychain (`security`) | yes | `keychain:<profile>:<NAME>` |
| `secret-tool` | GNOME Keyring / KWallet | yes | `secret-tool:<profile>:<NAME>` |
| `pass` | the standard unix password manager | yes | `pass:kafka-docker-playground/<profile>/<NAME>` |
| `op` | 1Password, through the `op` CLI | yes, items `kdp-<profile>-<NAME>` | `op://<vault>/<item>/<field>` |
| `vault` | HashiCorp Vault, through the `vault` CLI | **no**, reference only | `vault://<path>#<field>` |
| `file` | `secrets.ini` itself, in clear text (mode 0600) | yes | the value |

- **With no configuration** the first available of `keychain` (macOS), `secret-tool` and `pass` is used, and `file` is
  the fallback. **`op` and `vault` are never picked automatically**, so that an example never blocks halfway on an
  unlock prompt: choose them with `playground secrets backend op`.
- **The backend only applies to new values.** What is already stored keeps being read from, and rotated in, the
  backend its reference points to. Several backends can coexist in one store.
- **`link` works with every backend** (`op://`, `vault://`, `keychain:`, `secret-tool:`, `pass:`): the store then
  holds a reference to a secret you already have, safe to back up or share, and `vault` can only be used that way.
- `PLAYGROUND_SECRETS_BACKEND`, `PLAYGROUND_SECRETS_PROFILE`, `PLAYGROUND_OP_VAULT` and `PLAYGROUND_SECRETS_DIR`
  override the configuration for a single command.

---

## 5. The 1Password setup

1Password is the backend to use when you want the same credentials on several machines, an audit trail of who read
what, or credentials shared with your team. The playground talks to it through the `op` CLI only:
`op item create` / `op item edit` to store, `op read op://…` to resolve, `op item delete --archive` to remove.

### 5.1 Two ways for `op` to authenticate

| | Desktop app integration | Service account |
| --- | --- | --- |
| Setup | 1Password app > Settings > Developer > **Integrate with 1Password CLI** | an admin-granted service account, its token in `OP_SERVICE_ACCOUNT_TOKEN` |
| Unlock | Touch ID / password prompt when the app is locked | none: the token is the credential |
| Works headless (ssh, ec2, scheduled jobs, CI, a terminal recorder) | no | **yes** |
| Sees your `Private` vault | yes | **no**, only the vaults granted at creation |
| `op whoami` says | `User Type: HUMAN` | `User Type: SERVICE_ACCOUNT` |

Start with the desktop app. Move to a service account when you run the playground where nobody can press Touch ID,
or when the prompts get in the way. When `OP_SERVICE_ACCOUNT_TOKEN` is set, `op` uses it and ignores the app.

### 5.2 Setup A: desktop app (5 minutes)

```bash
brew install 1password-cli          # Linux: https://developer.1password.com/docs/cli/get-started/
# 1Password app > Settings > Developer > enable "Integrate with 1Password CLI"
op whoami                           # Touch ID the first time
playground secrets backend op
```

```text
🔐 Secrets backend set to op
🏦 1Password items will be created in vault Private
🎓 change it with: playground config set secrets.op-vault <vault>
🎓 you can also point a variable at an item you already have:
   playground secrets link SALESFORCE_PASSWORD op://Private/salesforce/password
```

Items go to `Private` by default. A vault of their own (`op vault create kdp-<you>`, then
`playground config set secrets.op-vault kdp-<you>`) keeps them apart from your personal items, and is what a service
account will need later anyway. Then move your credentials in: `playground secrets import --file … --shred`.

### 5.3 Setup B: service account (headless)

**1. A vault for your playground items.** A service account can never read `Private`, so create one (name it without
spaces, so that the `op://` references need no quoting):

```bash
op vault create kdp-jdoe
```

**2. The service account**, with read and write on that vault (and read only on a team vault, see 5.5). In
1Password.com > Developer > Service Accounts, or:

```bash
op service-account create "kdp-jdoe-playground" --expires-in 90d \
  --vault kdp-jdoe:read_items,write_items \
  --vault kdp-shared:read_items
```

- Creating one is a permission an admin grants; without it the page says `You need additional permissions to create
  service accounts`. Ask your 1Password administrators, or stay on Setup A.
- **Its vaults and permissions can't be changed after creation**: to change them, create a new one and swap the token.
- The `ops_…` token is shown **once**, and reads every granted vault: treat it like a password.

**3. The token in the OS keychain, not in your shell profile.** Prompted, so it never lands in the history:

```bash
security add-generic-password -a "$USER" -s op-service-account -w        # Linux: secret-tool store --label="op service account" service op-service-account
```

and read from there in `~/.zshrc` (or `~/.bashrc`):

```bash
export OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -s op-service-account -w 2>/dev/null)
# Linux: export OP_SERVICE_ACCOUNT_TOKEN=$(secret-tool lookup service op-service-account)
```

To keep your interactive `op` on the desktop app (and your `Private` vault), give the token to the playground only:
`alias playground='OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -s op-service-account -w 2>/dev/null) playground'`.

**4. Point the playground at the vault.** Mandatory: the default `Private` is invisible to a service account.

```bash
op whoami                                         # User Type: SERVICE_ACCOUNT
playground secrets backend op
playground config set secrets.op-vault kdp-jdoe
```

**5. Check with a throwaway value:**

```bash
playground secrets set DEMO_PASSWORD
playground secrets list --show-source
playground secrets unset DEMO_PASSWORD
```

```text
🔐 DEMO_PASSWORD stored in profile default (backend: op)

NAME                                          BACKEND        VALUE
----                                          -------        -----
DEMO_PASSWORD                                 op             op://kdp-jdoe/kdp-default-DEMO_PASSWORD/password

🗑️ DEMO_PASSWORD removed from profile default
```

**Token expiry or leak:** create a new service account, update the keychain entry
(`security add-generic-password -U -a "$USER" -s op-service-account -w`), revoke the old one. Nothing changes in
`secrets.ini`: the `op://` references stay valid.

### 5.4 What the playground does in 1Password

| Command | In 1Password |
| --- | --- |
| `secrets set NAME` (new) | `op item create --category Password --vault <secrets.op-vault> --title kdp-<profile>-<NAME> --tags kafka-docker-playground password=…`, then stores `op://<vault>/kdp-<profile>-<NAME>/password` |
| `secrets set NAME` (existing) | `op item edit <item> --vault <vault> <field>=…` on the item **of the reference**, wherever it is |
| `secrets link NAME op://…` | nothing is written: the reference is stored, then resolved once to report a typo or a locked session |
| `run`, `check`, `env`, `list`, `get` | `op read op://…`, one per variable, in parallel (the first one alone, so that a locked app shows one authorization prompt and not sixteen) |
| `secrets unset NAME` | `op item delete <item> --archive` when the item title starts with `kdp-`, nothing otherwise |

Measured with a service account: about 3 s per `secrets set` (`op whoami`, `op vault get`, then the create or edit),
about 1.5 s per `op read`, and an example needing a handful of variables resolves them in one parallel round trip.
The items are of category Password with the tag `kafka-docker-playground`, so they are easy to find in the app.

The real round trip, in a throwaway store and profile `lab` (vault `kafka-docker-playground`):

```text
$ playground secrets set DEMO_PASSWORD --value 'Op-Demo-Value-0001'
🔐 DEMO_PASSWORD stored in profile lab (backend: op)
$ playground secrets list --show-source
DEMO_PASSWORD                                 op             op://kafka-docker-playground/kdp-lab-DEMO_PASSWORD/password
$ playground secrets set DEMO_PASSWORD --value 'Op-Demo-Value-0002'      # rotation: same item, same reference
🔐 DEMO_PASSWORD stored in profile lab (backend: op)
$ playground secrets get DEMO_PASSWORD
🔐 DEMO_PASSWORD ****0002 (18 chars, sha256:15cdf910)
$ playground secrets link TYPO_PASSWORD op://Private/does-not-exist/password
🔗 TYPO_PASSWORD linked to op://Private/does-not-exist/password in profile lab
⚠️ the reference does not resolve right now (not logged in to op ?)
$ playground secrets list
DEMO_PASSWORD                                 op             ****0002 (18 chars, sha256:15cdf910)
TYPO_PASSWORD                                 op             ❌ cannot be resolved
$ playground secrets unset TYPO_PASSWORD
🔗 op://Private/does-not-exist/password was linked, not created by playground: the 1Password item is left untouched
🗑️ TYPO_PASSWORD removed from profile lab
```

### 5.5 Team credentials: a shared vault and `secrets link`

Some credentials are the same for the whole team (a Marketo sandbox, a shared ServiceNow instance). Keep them in **one
shared vault**, and have each colleague **link** to them instead of copying them: a rotation then happens in one
place, and someone who loses access to the vault simply can't run the example any more, with nothing left on disk.

1. A 1Password admin creates a shared vault, e.g. `kdp-shared`: the team gets *View items*, 1 or 2 maintainers get
   *Edit items*.
2. A maintainer creates **one item per service** with **one field per variable**, lowercase labels without spaces:

   ```bash
   op item create --vault kdp-shared --category "API Credential" --title marketo \
     'endpoint_url[text]=https://xxx-xxx-xxx.mktorest.com' 'client_id[text]=<client id>' \
     'client_secret[password]=<client secret>' 'munchkin_id[text]=xxx-xxx-xxx'
   ```

3. Each colleague links the variables once, in the `default` profile so that every profile sees them:

   ```bash
   for pair in ENDPOINT_URL:endpoint_url CLIENT_ID:client_id CLIENT_SECRET:client_secret MUNCHKIN_ID:munchkin_id
   do
     playground secrets link --profile default "MARKETO_${pair%%:*}" "op://kdp-shared/marketo/${pair#*:}"
   done
   playground secrets check -f ccloud/fm-marketo-sink/fully-managed-marketo-sink.sh
   ```

   ```text
   🔗 MARKETO_CLIENT_SECRET linked to op://kdp-shared/marketo/client_secret in profile default
   ✅ reference resolves: ****<last 4 characters> (<length> chars, sha256:<prefix>)
   ```

4. **Rotation**: a maintainer edits the field in `kdp-shared`; every colleague gets the new value on their next run.
   `playground secrets set MARKETO_CLIENT_SECRET` on a linked name also works, and changes the value **for the whole
   team** (it needs *Edit items*; a read-only service account gets `👉 a service account token needs write_items on that
   vault to rotate a password`).

With a service account, grant it `kdp-shared:read_items` at creation (5.3, step 2).

### 5.6 Gotchas

- **Never set `secrets.op-vault` to the shared vault.** Item titles are `kdp-<profile>-<NAME>`, with no user in them:
  two colleagues running `secrets set AWS_SECRET_ACCESS_KEY` write to the same item, and the second silently overwrites
  the first for everyone. Keep `secrets.op-vault` personal and use `link` for shared credentials.
- **`unset` archives any item whose title starts with `kdp-`**, even when the variable was added with `link`: it
  decides from the title, not from how the reference got there. Linking a colleague's (or another profile's)
  `kdp-…` item and then unsetting it archives that item for everyone. Link to items you named yourself (`marketo`,
  `servicenow`), never to `kdp-…` ones.
- **`link` stores the reference even when it doesn't resolve** (it warns): a typo shows up later as `❌ cannot be
  resolved` in `list`. Copy the reference from the app (item > field > Copy Secret Reference) rather than typing it.
- **A service account can't see `Private`**: with the default vault every write fails with
  `❌ 1Password vault Private is not readable with your current session`.
- **An exported variable wins, also over 1Password**: after rotating, look for `⚠️ overridden by the environment` in
  `secrets list`, and remove the `export` lines from your shell profile.
- **Rate limits**: service accounts are rate limited per hour and per day. `run` does one `op read` per declared
  variable, `secrets env --all` and `repro check` one per stored credential. `op service-account ratelimit` shows the
  usage.
- **`op` takes the value on its command line** (`op item create … password=…`): it is briefly visible in `ps` on a
  multi-user machine. A limitation of the `op` CLI (and of `security`, `pass`), not of the store.

### 5.7 Troubleshooting

| Message | Cause | Fix |
| --- | --- | --- |
| `❌ the 1Password CLI (op) is not installed` | | `brew install 1password-cli` |
| `❌ not signed in to 1Password` | app integration off or app locked, or `OP_SERVICE_ACCOUNT_TOKEN` empty or invalid in this shell | `op whoami`; enable the integration, or open a new terminal after fixing the token |
| `❌ 1Password vault <vault> is not readable with your current session` | `secrets.op-vault` is a vault this session can't see (`Private` with a service account) | `playground config set secrets.op-vault <vault>`; `op vault list` shows the ones you can |
| `❌ could not create 1Password item kdp-… in vault …` | no write permission on the vault | a service account with `write_items` on it |
| `❌ could not update 1Password item … 👉 a service account token needs write_items on that vault to rotate a password` | `secrets set` on a linked item of a read-only vault | rotate it in the vault (a maintainer) |
| `❌ cannot be resolved` in `secrets list` | expired token, item deleted or archived, vault not granted | `op read "<reference>"` shows 1Password's own error |
| `⚠️ the reference does not resolve right now (not logged in to op ?)` after `link` | typo in the reference, or no access | `op read "<reference>"` |

---

## 6. Profiles: one set of credentials per case

A profile is an independent set of variables, typically one per customer or support case, so last week's customer
credentials never leak into this week's reproduction model. A variable missing from the active profile is looked up
in `default`, where the shared ones (`CONFLUENT_LICENSE`, `NGROK_AUTH_TOKEN`) are stored once.

```bash
playground secrets profile case-123456          # persistent: config key secrets.profile
playground secrets set SERVICENOW_PASSWORD      # the customer's password, in case-123456 only
playground secrets profile
```

```text
🗂️ Active secrets profile: case-123456

👉 case-123456 (1 variable(s))
   default (2 variable(s))
```

`secrets check` then shows `SERVICENOW_PASSWORD` from `case-123456` and `SERVICENOW_URL` from `default`. Every
`secrets` command takes `--profile <name>` to use another one just once, and `PLAYGROUND_SECRETS_PROFILE` does the
same for any command, `playground run` included. With 1Password, items of a profile are named `kdp-<profile>-<NAME>`.
`playground secrets profile default` switches back.

---

## 7. Getting values out, safely

| Need | Command | Safety net |
| --- | --- | --- |
| an example's variables in the current shell, to paste parts of its script | `source <(playground secrets env -f <example>)` (`--all` for the whole profile) | refuses to print to a terminal (`❌ stdout is a terminal, every value would be printed in clear on screen`), values single quoted so nothing is interpreted, only the example's variables |
| a properties file for another tool | `playground secrets export --file ~/x.properties --yes-i-want-plaintext` (`--only plain\|secret`) | refused inside the repository, mode `0600`; prefer `env` |
| an ec2 playground instance | `playground ec2 push-secrets` | values sent over ssh to `~/.playground-secrets.properties` (`umask 077`), read from the store, not from your shell |
| GitHub Actions secrets of a repository you maintain | `playground secrets push-github` (private) | credentials become secrets, plain variables become variables, values piped to `gh` on stdin; `--dry-run` first |

`secrets env` prints the exports on stdout and everything else on stderr, which is what makes sourcing it safe:

```text
export SERVICENOW_PASSWORD='Customer-Pass-9876'
export SERVICENOW_URL='https://dev12345.service-now.com/'
🔐 2 variable(s) exported for servicenow-sink.sh (profile case-123456)
```

With the config key `secrets.github-repo` (`OWNER/REPO`), every `secrets set` is also pushed to that repository's
GitHub Actions configuration, which keeps CI in sync for its maintainer. It is skipped in CI and when
`PLAYGROUND_SECRETS_DIR` points at another store (`🐙 not pushed to <repo>: PLAYGROUND_SECRETS_DIR points at another
store`), so a test or a demo never overwrites the real values.

**Leaks in the repository.** Pattern based scanners don't recognise a password pasted into a reproduction model;
`secrets scan` resolves every stored credential (8 characters or more) and greps the working tree for the values
themselves, tracked and untracked files:

```text
🔎 Scanning the working tree for values of profile default
🚨 the value of SERVICENOW_PASSWORD appears in:
     reproduction-models/connect-servicenow-sink/servicenow-sink-repro-123456-timeout.sh

🚨 1 secret(s) found in clear text — do not commit
```

`playground repro check` and `repro export` read the same store (every credential known to the machine) on top of
their own patterns. The pre-commit hook of `reproduction-models` runs `repro check --staged --skip-secrets-store`,
patterns only so that a commit never waits on 1Password: `playground secrets scan --staged` covers the stored values.

---

## 8. Hands-on lab (≈10 min)

No container needed. The lab uses a throwaway store with the `file` backend, so that it doesn't touch your real
credentials, nor 1Password (5.4 shows the same steps against 1Password):

```bash
export PLAYGROUND_SECRETS_DIR=$(mktemp -d) PLAYGROUND_SECRETS_BACKEND=file
unset SERVICENOW_URL SERVICENOW_PASSWORD
```

**Step 1: what does the example need?**

```bash
playground secrets check -f connect/connect-servicenow-sink/servicenow-sink.sh
# ❌ SERVICENOW_PASSWORD missing        👉 playground secrets set SERVICENOW_PASSWORD
# ❌ SERVICENOW_URL missing        👉 playground secrets set SERVICENOW_URL
# ❌ 2 variable(s) missing, the example would fail      (exit code 1)
```

**Step 2: store them, the name decides where**

```bash
playground secrets set SERVICENOW_URL --value https://dev12345.service-now.com/
# 📝 SERVICENOW_URL=https://dev12345.service-now.com/ stored in profile default as a plain variable
playground secrets set SERVICENOW_PASSWORD --value 'Demo-Passw0rd-1234'
# 🔐 SERVICENOW_PASSWORD stored in profile default (backend: file)
ls -l $PLAYGROUND_SECRETS_DIR
# -rw-r--r--  env.ini
# -rw-------  secrets.ini
```

**Step 3: values are never printed**

```bash
playground secrets list
# SERVICENOW_PASSWORD                           file           ****1234 (18 chars, sha256:6d910ac4)
# SERVICENOW_URL                                plain          https://dev12345.service-now.com/
playground secrets get SERVICENOW_PASSWORD
# 🔐 SERVICENOW_PASSWORD ****1234 (18 chars, sha256:6d910ac4)
playground secrets check -f connect/connect-servicenow-sink/servicenow-sink.sh
# 🔐 SERVICENOW_PASSWORD set (file: secrets.ini)
# 🔐 SERVICENOW_URL set (plain: https://dev12345.service-now.com/)
# ✅ Everything this example needs is available
```

**Step 4: an exported variable always wins**

```bash
SERVICENOW_PASSWORD=from-my-shell-1234 playground secrets list
# SERVICENOW_PASSWORD   file   ****1234 (18 chars, sha256:6d910ac4)  ⚠️ overridden by the environment
SERVICENOW_PASSWORD=from-my-shell-1234 playground secrets get SERVICENOW_PASSWORD
# 🔐 SERVICENOW_PASSWORD ****1234 (18 chars, sha256:f1e0ed75)      <- another sha256: the value of the shell
```

**Step 5: one profile per case, falling back to default**

```bash
playground secrets profile case-123456
# 🗂️ Active secrets profile is now case-123456 (0 variable(s))
playground secrets set SERVICENOW_PASSWORD --value 'Customer-Pass-9876'
playground secrets profile
# 👉 case-123456 (1 variable(s))
#    default (2 variable(s))
source <(playground secrets env -f connect/connect-servicenow-sink/servicenow-sink.sh)
# 🔐 2 variable(s) exported for servicenow-sink.sh (profile case-123456)
echo $SERVICENOW_PASSWORD $SERVICENOW_URL
# Customer-Pass-9876 https://dev12345.service-now.com/        <- the password of the case, the URL of default
unset SERVICENOW_URL SERVICENOW_PASSWORD
playground secrets profile default
```

**Step 6: `secrets env` refuses to print to a terminal**

```bash
playground secrets env -f connect/connect-servicenow-sink/servicenow-sink.sh
# ❌ stdout is a terminal, every value would be printed in clear on screen
# 👉 source <(playground secrets env)
```

**Step 7: import an old `secret.properties`**

```bash
mkdir -p /tmp/secrets-lab-files
cat > /tmp/secrets-lab-files/secret.properties << 'EOF'
# my old secret.properties
export DD_API_KEY="dd-api-0123456789abcdef"
DD_APP_KEY='dd-app-fedcba9876543210'
DD_SITE=datadoghq.eu
lowercase=skipped
EOF
playground secrets import --file /tmp/secrets-lab-files/secret.properties --shred
# ⏭️ skipping <lowercase>, not an uppercase environment variable name
# ✅ Imported 2 secret(s) and 1 plain variable(s), 1 skipped
# 🔥 Securely deleting /tmp/secrets-lab-files/secret.properties
```

**Step 8: a stored password pasted in the repository**

```bash
echo 'curl -u admin:Demo-Passw0rd-1234 https://dev12345.service-now.com/' > other/deep-dive-labs/secrets-lab-leak.txt
playground secrets scan
# 🚨 the value of SERVICENOW_PASSWORD appears in:
#      other/deep-dive-labs/secrets-lab-leak.txt
# 🚨 … secret(s) found in clear text — do not commit           (exit code 1)
rm other/deep-dive-labs/secrets-lab-leak.txt
```

The lab script finds the values it writes itself too: it scans a profile of its own, with a random value.

**Step 9: export, only outside the repository**

```bash
playground secrets export --file ./x.properties --yes-i-want-plaintext
# ❌ refusing to write credentials inside the repository (…/kafka-docker-playground)
playground secrets export --file /tmp/secrets-lab-files/plain.properties --only plain --yes-i-want-plaintext
cat /tmp/secrets-lab-files/plain.properties
# DD_SITE=datadoghq.eu
# SERVICENOW_URL=https://dev12345.service-now.com/
```

**Step 10: unset**

```bash
playground secrets unset DD_APP_KEY
# 🗑️ DD_APP_KEY removed from profile default
playground secrets unset DD_APP_KEY
# 🤔 DD_APP_KEY is not stored in profile default
```

```bash
rm -rf $PLAYGROUND_SECRETS_DIR /tmp/secrets-lab-files
unset PLAYGROUND_SECRETS_DIR PLAYGROUND_SECRETS_BACKEND
```

---

## 9. Recipes for support repros

| Situation | Command |
| --- | --- |
| a case needs the customer's credentials (their sandbox, their instance) | `playground secrets profile case-<n>`, `secrets set` the few that differ, everything else falls back to `default`; `secrets profile default` once the case is closed, `secrets unset <NAME> --profile case-<n>` for each of them to clean up (the 1Password items are archived) |
| "the example failed after 5 minutes on a missing variable" | `playground secrets check -f <example>` first: it fails in a second |
| a teammate shares a sandbox for the case | they put it in the shared vault, you `secrets link` it: nothing to copy, nothing to clean |
| the repro model reads a credential | declare it with the standard error string (`<NAME> is not set. Export it as environment variable or pass it as argument`) so that `run` loads it, never hardcode the value; `playground repro check` before committing |
| you pasted a password while debugging | `playground secrets scan` (or `--staged`) before the commit |
| copy-pasting parts of an example script into a terminal | `source <(playground secrets env -f <example>)` |
| "it still uses the old password" after a rotation | `playground secrets list`: `⚠️ overridden by the environment` means an `export` wins |
| run on an ec2 instance, or anywhere without Touch ID | service account (5.3), then `playground ec2 push-secrets` for an ec2 playground instance |

---

## 10. Cheat sheet

```bash
playground secrets check [-f <example>]                  # what is needed, what is missing (exit 1)
playground secrets set <NAME> [--value v] [--secret|--plain] [--profile p]
playground secrets get <NAME> [--reveal]
playground secrets list [--show-source] [--profile p]
playground secrets unset <NAME>
playground secrets import --file <file> [--shred] [--secret|--plain]
playground secrets link <NAME> op://<vault>/<item>/<field> | vault://<path>#<field> | keychain:<profile>:<NAME> | pass:<path>
playground secrets backend [keychain|secret-tool|pass|op|vault|file]
playground config set secrets.op-vault <vault>
playground secrets profile [<name>]
source <(playground secrets env [-f <example>] [--all])
playground secrets export --file <outside the repo> --yes-i-want-plaintext [--only plain|secret]
playground secrets scan [--staged]
```

- `~/.config/kafka-docker-playground`: `secrets.ini` (0600, references), `env.ini` (0644, plain values).
- Name with `PASSWORD`, `PASSPHRASE`, `SECRET`, `TOKEN`, `KEY`, `CREDS`, `PWD`, `LICENSE` = credential.
- Resolution: exported variable > active profile > `default`. Only the variables the example declares are loaded.
- `op` and `vault` are never picked automatically. `vault` is reference only.
- 1Password: items `kdp-<profile>-<NAME>` in `secrets.op-vault` (default `Private`), field `password`, tag
  `kafka-docker-playground`. Service account = a dedicated vault, `OP_SERVICE_ACCOUNT_TOKEN` from the keychain.
  Team credentials = `link` to a shared vault, never `secrets.op-vault` on it.
- Sources: [`secrets_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/secrets_function.sh)
  (store, backends, resolution), the commands in
  [`commands/secrets/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/secrets),
  `load_secrets_for_example` in [`run.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/run.sh).

---

**Links**

- 🎬 Video session: [🕹️ Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) (`playground secrets set` at the end)
- 🍪 Deep dives: [Running examples and changing versions](/deep-dive-run-and-versions.md), [Reproduction models](/deep-dive-reproduction-models.md) (`repro check` and the pre-commit hook), [Fully managed connectors](/deep-dive-fully-managed.md) (the Confluent Cloud API key in the store)
- 📖 [Storing credentials with playground secrets](/how-to-use?id=🔐-storing-credentials-with-playground-secrets), 1Password docs: [CLI app integration](https://developer.1password.com/docs/cli/app-integration/), [service accounts](https://developer.1password.com/docs/service-accounts/), [secret references](https://developer.1password.com/docs/cli/secret-references/)
- 🧠 CLI reference: [playground secrets](/playground%20secrets), [playground secrets set](/playground%20secrets%20set),
  [playground secrets link](/playground%20secrets%20link), [playground secrets backend](/playground%20secrets%20backend),
  [playground secrets env](/playground%20secrets%20env), [playground ec2 push-secrets](/playground%20ec2%20push-secrets)
