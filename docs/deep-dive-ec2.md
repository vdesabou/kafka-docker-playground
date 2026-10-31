# 🍪 Deep dive: run the playground on an AWS EC2 instance (`playground ec2`)

Some examples need more than a laptop: 32 GB of memory for a multi-broker CFK cluster, an Oracle database and a connect
worker side by side, a soak test that must run all night, or an image that does not exist for arm64. `playground ec2`
gives you a remote Ubuntu machine with docker and the playground already installed, created with one command through AWS
Cloud Formation, and opens it in VS Code over SSH so that it feels like working locally. This page explains what
`create` really builds, how access works (a pem file and your IP address only), how to move reproduction models and
credentials back and forth, and how not to pay for an instance you forgot. Takes about 15 minutes to read; the lab is
free unless you opt in to create an instance (a few cents).

| You want | Command |
| --- | --- |
| a remote machine with the playground installed, opened in VS Code | `playground ec2 create` (`--instance-type`, `--size`, `--suffix <case>`) |
| your instances and their state | `playground ec2 list` |
| work on it again (starts it when it is stopped) | `playground ec2 open` (`--enable-sync-repro-folder`) |
| your IP changed, ssh times out | `playground ec2 open` (or the private `playground ec2 allow-my-ip`) |
| send your credentials to it, over ssh | `playground ec2 push-secrets` (`--dry-run`, `--profile`) |
| copy reproduction models there / bring them back | `playground ec2 sync-repro-folder local-to-ec2` / `ec2-to-local` |
| pause the billing of the compute | `playground ec2 stop`, later `playground ec2 start` |
| stop paying for good | `playground ec2 sync-repro-folder ec2-to-local`, then `playground ec2 delete` |
| check that nothing is still running | `playground status` (💸 reminder), `playground ec2 list` |
| what it cost | `playground cloud-resources aws costs` / `costs-history` |

---

## 1. Mental model (the 3 things to remember)

1. **One instance = one Cloud Formation stack named `pg-<you>-<suffix>`.** `playground ec2 create` creates a key pair
   and a stack from [`cloudformation/kafka-docker-playground.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/kafka-docker-playground.yml):
   an amd64 Ubuntu instance with a gp2 root volume, a security group that opens port 22 to your IP only, and a bootstrap
   that installs docker, the AWS / Azure / Confluent CLIs, `kubectl`, `k3d`, `helm`, zsh with the playground `.zshrc`, and
   clones the public repository. `<you>` is your local `whoami`, which is also the Linux user created on the instance;
   `<suffix>` is `--suffix` (lowercased, spaces to dashes) or 6 random characters. Every `ec2` command only sees the
   instances whose `Name` tag starts with `pg-<you>-`, in the current AWS region.

2. **Access is a pem file at the root of the repository, and your current IP.** The private key is written to
   `<repo>/pg-<you>-<suffix>.pem` (mode 400), and a `Host pg-<you>-<suffix>` entry is added to `~/.ssh/config`
   (public DNS name, `IdentityFile`, your user). `open`, `start`, `sync-repro-folder` and `push-secrets` first run the
   private `allow-my-ip`: it **revokes every ingress rule** of the security group, allows `<your public IP>/32` on port
   22 again, rewrites the `HostName` (it changes at every start), and **starts the instance when it is stopped**. Lose the
   pem file and the instance is unreachable: `delete` it and create another one.

3. **It is billed until you delete it, and the reminder is local.** A running instance bills compute and its volume; a
   stopped one still bills its volume (`--size`, 1000 GB by default). `create` / `open` / `start` add the instance to
   `ec2.running_list` in the `[ec2]` section of `playground.ini`, `stop` / `delete` remove it, and `playground status`
   and the end of every `playground run` print `🤑 you have an ec2 instance <name> running !` for each name in that
   list. Nothing else (`cloud-resources aws list`, `cleanup-cloud-resources`) knows about these instances.

---

## 2. `create`: what happens, and how long it takes

```bash
playground ec2 create --suffix 123456                       # t3.2xlarge, 1000 GB, region of your aws CLI
playground ec2 create --instance-type m4.4xlarge --size 200 --suffix 123456-big
```

What it prints:

```text
🔐 creating pem file <repo>/pg-<you>-123456.pem (make sure to create backup)
👷 creating t3.2xlarge instance pg-<you>-123456 in <region> region (1000 Gb)
🌀 cloud formation file used: <repo>/cloudformation/kafka-docker-playground.yml
🔐 ec2 pem file used: <repo>/pg-<you>-123456.pem
⌛ waiting up to 300 seconds for ec2 instance pg-<you>-123456 to be running
🟢 ec2 instance pg-<you>-123456 is running
👷 ec2 instance pg-<you>-123456 is created and accesible via SSH, it will be opened with visual studio code in 3 minutes...
🌀 cloud formation is still in progress (installing docker, etc...) and can be reverted after 10 minutes (i.e removing ec2 instance) in case of issue. You can check progress by checking log file output.log in root folder of ec2 instance
👨‍💻 Open EC2 instance pg-<you>-123456 using Visual Studio code
⌛ waiting up to 900 seconds for ec2 cloudformation stack pg-<you>-123456 to be in status CREATE_COMPLETE
🟢 ec2 cloudformation pg-<you>-123456 is in status CREATE_COMPLETE
🔐 Sending … variable(s) of profile default to pg-<you>-123456 (~/.playground-secrets.properties)
🎉 ec2 instance pg-<you>-123456 is ready!
🐚 make sure to use zsh in order to have everything working out of the box
```

The steps, in order: the key pair and the pem file; the stack (parameters `InstanceType`, `Ec2RootVolumeSize`,
`KeyName`, `InstanceName`, `IPAddressRange=<your IP>/32`, `LinuxUserName=<you>`, tags `cflt_managed_by=user` and
`cflt_managed_id=$USER`); a wait for the instance to run; 3 minutes of sleep, then `ec2 open` (VS Code); a wait for the
stack to reach `CREATE_COMPLETE` (the bootstrap signals the end of its install, 10 minutes at most); `sync-repro-folder
local-to-ec2`; `push-secrets`. Count about 15 minutes.

Gotchas:

- **The region is the one of your aws CLI**: `AWS_REGION`, else `aws configure get region`
  (`❌ either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!`). The other
  commands use the default region of the aws CLI too: an instance created in another region is invisible to
  `ec2 list`, and keeps billing.
- **`ec2` uses the credentials of your aws CLI** (`~/.aws/credentials`, `AWS_PROFILE`, exported `AWS_ACCESS_KEY_ID`…),
  and needs broad EC2 and Cloud Formation rights: every `ec2` command first runs `aws ec2 describe-instances --dry-run`
  and stops with `aws ec2 describe-instances command got an error` / `please make sure to have AdministratorAccess in aws`
  when it is refused.
- **VS Code opens before the install is finished.** The window comes up after 3 minutes, while Cloud Formation is still
  installing docker: wait for `🟢 ec2 cloudformation … is in status CREATE_COMPLETE` before running an example, and
  read `~/output.log` on the instance to see where the install is. `open` needs the `code` command (`❌ code command is
  not found - this command requires vscode to be installed`) and the Remote - SSH extension.
- **A stack that fails rolls back** (`❌ ec2 cloudformation stack … is in state ROLLBACK_…`): the instance is terminated,
  but the stack, the key pair and the pem file stay. `playground ec2 delete --instance pg-<you>-<suffix>` cleans them:
  without `--instance`, `delete` only finds stacks through `ec2 list`, which lists instances, not stacks.
- **`--suffix` must be new**: `❌ ec2 instance pg-<you>-<suffix> already exists`, `use playground ec2 delete --instance
  … to delete it`. Use the case number, it makes `ec2 list` readable.
- **`--instance-type` is a fixed list** (bashly `allowed`, a subset of what the template accepts): `t3.2xlarge`
  (8 vCPU, 32 GiB, the default) and smaller `t2` / `t1` / `m1` / `m3`, or the bigger `m4.4xlarge` (64 GiB),
  `m4.10xlarge` (160 GiB), `c3.8xlarge` (60 GiB)…
- **Use zsh** on the instance: the playground `.zshrc` puts `scripts/cli` in the `PATH`, loads the completions and
  `cd`s into `~/kafka-docker-playground`.

---

## 3. Working on it: `open`, `list`, `start`, `stop`, and the `--instance` value

```bash
playground ec2 list
# 🔘 listing all your ec2 instances
# pg-<you>-123456/✅running/ec2-….compute.amazonaws.com/i-…
# pg-<you>-abc123/🛑stopped//i-…                     <- no public DNS name while stopped
playground ec2 open                                  # every instance (VS Code window each), or --instance <TAB>
# 🛂 ip <your IP> is now allowed to connect to ec2 instance pg-<you>-123456
# 👨‍💻 Open EC2 instance pg-<you>-123456 using Visual Studio code
playground ec2 stop                                  # 🔴 stopping ec2 instance pg-<you>-123456
playground ec2 start                                 # 🟢 starting the ec2 instance pg-<you>-123456
```

The states are `✅running`, `🛑stopped`, `⌛pending` and `⌛stopping`; the last two have no address or id, and every
command skips them (`ec2 instance … is in state … (not stopped and not running), skipping it`).

Gotchas:

- **Without `--instance`, a command applies to all your instances** (`✨ --instance flag was not provided, applying
  command to all ec2 instances`); only `delete` asks to confirm first (when you have several).
- **`--instance` takes a bare name or the value of the completion**: `pg-<you>-<suffix>`, or
  `<name>/<state>/<dns>/<id>` (TAB completion writes `<what you typed>@<that>`, the part before `@` is dropped). A bare
  name is looked up in `ec2 list` (`❌ ec2 instance <name> not found` when it isn't one of yours).
- **`ec2 list` prints a log line first**: `playground --output-level WARN ec2 list` gives only the instances, which is
  what the commands use internally. `ec2 status --instance <name>` (private) prints the state alone, `--all` the
  whole line, and nothing when there is no such instance.
- **The public DNS name changes at every start**: use `ec2 open`, or `ssh pg-<you>-<suffix>` once `open` / `start`
  rewrote `~/.ssh/config`; never a bookmarked `ssh ubuntu@ec2-…`.
- **`allow-my-ip` keeps one IP**: the one `dig @resolver4.opendns.com myip.opendns.com` returns (needs `dig`; behind a
  VPN it is the VPN exit). Any rule added by hand for a colleague is revoked by the next `open`.
- **`open`, `allow-my-ip` and both `sync-repro-folder` start a stopped instance** (`push-secrets` skips it instead:
  `… (not running), skipping it`). Opening it "just to look" resumes the compute billing.

---

## 4. Moving files and credentials: `sync-repro-folder` and `push-secrets`

```bash
playground ec2 sync-repro-folder local-to-ec2       # 👉 Sync local reproduction-models folder to ec2 instance pg-<you>-…
playground ec2 sync-repro-folder ec2-to-local       # 👈 Sync ec2 instance pg-<you>-… reproduction-models folder to local
playground ec2 push-secrets --dry-run               # 🔍 … variable(s) of profile default would be written to ~/.playground-secrets.properties on:
playground ec2 push-secrets                         # ✅ ~/.playground-secrets.properties written on pg-<you>-…
```

- **The public repository is cloned on the instance, without the private `reproduction-models`** (its `.git` is removed):
  `local-to-ec2` copies your local folder to `~/kafka-docker-playground/reproduction-models`, `ec2-to-local` brings the
  remote one back into your repository. Both use `rsync -cauv` over the pem file, skip `.git` and what `.gitignore`
  lists, and need `rsync` locally. `create` runs `local-to-ec2` once; `open --enable-sync-repro-folder` runs it at every
  open.
- **rsync never deletes and never overwrites a newer file** (`-u`, no `--delete`): a model removed on one side comes
  back on the next sync, and a file edited on both sides keeps the newer copy. The instance clone has no git history
  for the models: commit them from your laptop after `ec2-to-local`.
- **`ec2-to-local` before `delete`, every time**: nothing else brings back what you wrote on the instance.
- **`push-secrets` sends the secrets store, not your shell**: every value of the profile (`--profile`, default the
  active one) is read from the store and piped over ssh into `~/.playground-secrets.properties` (`umask 077`, mode
  0600, values single quoted), so no clear text copy lands on your disk. `aws_credentials_with_assuming_iam_role`,
  `aws_credentials_aws_account_with_assume_role` and `github_ssh_key_file` at the root of the repository are sent too
  when they exist (`⚠️ <file> does not exist, it will not be sent` otherwise). An empty profile stops it:
  `❌ profile <profile> is empty, there is nothing to send`. See the [secrets deep dive](/deep-dive-secrets.md).
- **The instance loads the file on demand**: a new zsh prints
  `secrets are present in ~/.playground-secrets.properties, use pgenv to load them in shell`, and `pgenv` exports them.
  `playground run` on the instance reads its own store like anywhere else: run `pgenv` before an example that expects
  exported variables.

---

## 5. Costs and cleanup

```bash
playground status                                   # ends with the 💸 reminder for each instance of ec2.running_list
playground ec2 list                                 # the truth, from AWS: anything not 🛑stopped bills compute
playground ec2 stop                                 # volume still billed
playground ec2 sync-repro-folder ec2-to-local && playground ec2 delete --instance pg-<you>-<suffix>
playground cloud-resources aws costs --start-date <day before> --end-date <day after>
```

What `playground status` (and the end of `playground run`) prints while an instance is in the list:

```text
💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸
🤑 you have an ec2 instance pg-<you>-123456 running !
💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸💸
```

`delete` deletes the stack (instance, volume, security group), removes the name from `ec2.running_list`, and when the
pem file is there, deletes it and the key pair on AWS:

```text
❌ deleting ec2 cloudformation pg-<you>-123456 in state ✅running
🔐 deleting pem file <repo>/pg-<you>-123456.pem
🔐 deleting pem pg-<you>-123456 on aws
```

Gotchas:

- **The order of magnitude** (us-east-1 on-demand list prices, check the AWS pricing page for yours): a `t3.2xlarge`
  is about $0.33 an hour, so about $8 a day left running; a 1000 GB gp2 volume is about $100 a month, **running or
  stopped**. For a short repro, `--size 100` and `delete` when done cost far less than `stop` for weeks. `t3` instances
  run in unlimited CPU credit mode by default: a CPU-bound soak test adds a surcharge.
- **The reminder is only as good as `playground.ini`**: an instance created from another laptop, or started from the
  AWS console, is not in it; one stopped or deleted from the console stays in it. `ec2 list` asks AWS, trust it.
- **`cloud-resources aws list` and `cleanup-cloud-resources` don't cover EC2 instances**: they look for the Kinesis
  streams, SQS queues, Lambda functions, Redshift clusters… that the examples create. Only `ec2 delete` removes an
  instance.
- **`cloud-resources aws costs` / `costs-history` do show what it cost**: they report the spend of the resources tagged
  `cflt_managed_id=$USER`, the tag `create` puts on the stack, grouped by service (the EC2 lines). Costs arrive with a
  delay of a few days (the default range ends 3 days ago).
- **`delete` doesn't wait** for the stack to be gone: `ec2 list` can still show the instance shutting down for a minute.

---

## 6. Hands-on lab (≈5 min, free; ≈25 min and a few cents with an instance)

You need the aws CLI with credentials that can describe EC2 instances. Steps 1 to 3 create nothing on AWS; step 4
creates a small instance, and only runs when you ask for it.

**Step 1: what you have, read-only**

```bash
playground ec2 list
# 🔘 listing all your ec2 instances
# pg-<you>-…/✅running/ec2-….compute.amazonaws.com/i-…              <- one line per instance, nothing when you have none
playground --output-level WARN ec2 list                             # the same lines, without the log line
playground ec2 status --instance "pg-$(whoami)-nothing-here"        # prints nothing: no such instance
```

**Step 2: what `push-secrets` would send, without contacting anything**

A throwaway store with the `file` backend, and a made-up instance value: `--dry-run` stops before ssh.

```bash
export PLAYGROUND_SECRETS_DIR=$(mktemp -d) PLAYGROUND_SECRETS_BACKEND=file
playground secrets set LAB_EC2_PASSWORD --value 'Demo-Passw0rd-1234'
playground ec2 push-secrets --instance "pg-$(whoami)-lab/✅running/ec2-lab.example.com/i-lab" --dry-run
# ⚠️ <repo>/aws_credentials_with_assuming_iam_role does not exist, it will not be sent     <- and the 2 other files
# 🔍 1 variable(s) of profile default would be written to ~/.playground-secrets.properties on:
#    👉 pg-<you>-lab
```

**Step 3: the reminder of `playground status`**

```bash
playground state set ec2.running_list "pg-$(whoami)-lab"
playground status
# …
# 🤑 you have an ec2 instance pg-<you>-lab running !
playground state del ec2.running_list                               # or put back what was there
```

**Step 4 (optional, billed): a small instance, end to end**

```bash
playground ec2 create --instance-type t2.large --size 50 --suffix deep-dive-lab
# 🔐 creating pem file <repo>/pg-<you>-deep-dive-lab.pem (make sure to create backup)
# 👷 creating t2.large instance pg-<you>-deep-dive-lab in <region> region (50 Gb)
# …
# 🎉 ec2 instance pg-<you>-deep-dive-lab is ready!
playground ec2 status --instance "pg-$(whoami)-deep-dive-lab"
# ✅running
playground ec2 stop --instance "$(playground ec2 status --instance "pg-$(whoami)-deep-dive-lab" --all)"
# 🔴 stopping ec2 instance pg-<you>-deep-dive-lab
playground ec2 delete --instance "pg-$(whoami)-deep-dive-lab"
# ❌ deleting ec2 cloudformation pg-<you>-deep-dive-lab in state …
# 🔐 deleting pem file <repo>/pg-<you>-deep-dive-lab.pem
```

The lab script runs step 4 only with `PLAYGROUND_LAB_EC2_CREATE=1`, and deletes the instance on exit whatever happens.

---

## 7. Recipes for support repros

| Situation | Command |
| --- | --- |
| the example needs 32 GB (CFK, several brokers, Oracle + connect) | `playground ec2 create --suffix <case>` (t3.2xlarge, 32 GiB), then `playground run -f …` in the VS Code terminal |
| it needs more than 32 GB | `playground ec2 create --instance-type m4.4xlarge --suffix <case>` (64 GiB), `m4.10xlarge` for 160 GiB |
| the example is marked arm64 "not working" (`❌💻 this example is not working with ARM64 !`) | an ec2 instance is amd64: `ec2 create`, run it there |
| it must run overnight | run it in `tmux` on the instance (closing VS Code or your laptop then doesn't stop it), `ec2 stop` in the morning once the results are pulled back |
| my IP changed (VPN, other network), ssh / VS Code times out | `playground ec2 open` (re-allows your new IP, rewrites `~/.ssh/config`) |
| after `ec2 start`, `ssh` to the old address fails | the public DNS name changed: `ec2 open` or `ssh pg-<you>-<suffix>` |
| I wrote the repro model on my laptop, I want to run it there | `playground ec2 sync-repro-folder local-to-ec2`, or `open --enable-sync-repro-folder` |
| I wrote it on the instance, I'm done | `playground ec2 sync-repro-folder ec2-to-local`, commit from the laptop, then `ec2 delete` |
| the example needs credentials on the instance | `playground ec2 push-secrets` (`--profile case-<n>` for the case profile), then `pgenv` in a new shell |
| share the repro machine with a colleague | prefer a repro model they run on their own instance (`repro export`); otherwise they need the pem file (sent privately) and their IP allowed by hand, which your next `open` revokes |
| the stack failed, `ec2 list` shows nothing | `playground ec2 delete --instance pg-<you>-<suffix>` (deletes the stack, the key pair and the pem file) |
| "did I leave something running?" | `playground ec2 list`, then `playground cloud-resources aws costs` a few days later |

---

## 8. Cheat sheet

```bash
playground ec2 create [--instance-type t3.2xlarge] [--size 1000] [--suffix <case>]
playground ec2 list                                       # name/state/dns/id, only pg-<you>-*, current region
playground ec2 open [--instance <TAB>] [--enable-sync-repro-folder]
playground ec2 stop|start [--instance <TAB>]
playground ec2 sync-repro-folder local-to-ec2|ec2-to-local [--instance <TAB>]
playground ec2 push-secrets [--instance <TAB>] [--profile <p>] [--dry-run]
playground ec2 delete [--instance pg-<you>-<suffix>]      # stack + key pair + pem file
playground ec2 status --instance <name> [--all]           # private: state, or the full --instance value
playground status                                         # 💸 reminder from playground.ini [ec2] running_list
playground cloud-resources aws costs|costs-history
```

- One stack per instance, `pg-<whoami>-<suffix>`, amd64 Ubuntu with docker and the playground; about 15 minutes to be
  ready, `~/output.log` on the instance.
- Access: `<repo>/pg-<you>-<suffix>.pem` + your current IP only (`open` re-allows it, starting a stopped instance).
- Billed while it exists: `stop` keeps paying for the volume, `delete` stops it all; `ec2-to-local` before `delete`.
- Sources: the commands in [`commands/ec2/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/ec2),
  `ec2_instance_list`, `wait_for_ec2_*` and `check_for_ec2_instance_running` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh),
  the template [`cloudformation/kafka-docker-playground.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/kafka-docker-playground.yml)
  and the instance [`.zshrc`](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/dotfiles/zshrc).

---

**Links**

- 🍪 Deep dives: [credentials and the 1Password setup](/deep-dive-secrets.md) (`push-secrets`, the store),
  [reproduction models](/deep-dive-reproduction-models.md) (what `sync-repro-folder` moves),
  [Confluent for Kubernetes](/deep-dive-cfk.md) (the memory-hungry environment), [fully managed connectors](/deep-dive-fully-managed.md)
  (costs of Confluent Cloud)
- 📖 [AWS EC2 instance (using Cloud Formation)](/how-to-use?id=☁️-aws-ec2-instance-using-cloud-formation) and
  [AWS EC2 playground ec2 command](/how-to-use?id=✨-aws-ec2-playground-ec2-command) in How to Use
- 🧠 CLI reference: [playground ec2](/playground%20ec2), [playground ec2 create](/playground%20ec2%20create),
  [playground ec2 open](/playground%20ec2%20open), [playground ec2 sync-repro-folder](/playground%20ec2%20sync-repro-folder),
  [playground ec2 push-secrets](/playground%20ec2%20push-secrets), [playground ec2 delete](/playground%20ec2%20delete),
  [playground cloud-resources](/playground%20cloud-resources)
