
# 🚀 How to use

## 3️⃣ Ways to run

### 🌐 In your browser: GitHub Codespaces

Nothing to install: click the button, log in to GitHub, and after about 2 minutes VS Code opens in your browser with a terminal where `playground run` works.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/vdesabou/kafka-docker-playground?quickstart=1)

The codespace is an Ubuntu machine (x86_64, 4 cores, 16 GB) set up by [.devcontainer/devcontainer.json](https://github.com/vdesabou/kafka-docker-playground/blob/master/.devcontainer/devcontainer.json): Docker with compose v2, bash 5, fzf, and `playground` with its completion in the `PATH`. [playground doctor](/playground%20doctor) runs each time it starts. Control Center (port 9021) and Grafana (port 3000) are forwarded to your browser when an example starts them.

| Good to know | |
| --- | --- |
| 💸 Cost | Personal GitHub accounts get a [free monthly quota](https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-codespaces/about-billing-for-github-codespaces) of core hours and storage: on this 4-core machine, the 120 core hours of a Free account make about 30 hours a month, and the pulled images count in the storage. Great to try the playground, less to run it all day. **Stop** the codespace when you are done (it stops by itself after 30 minutes idle) and delete it when you no longer need it. |
| 🐢 First run | The images of a default run (`cp-server`, `cp-server-connect` and `cp-schema-registry` for the default Confluent Platform version) are already in the codespace when it comes from a prebuild. Otherwise they are pulled in the background right after it opens (see **View Creation Log**), and an example started before the end pulls what is still missing. Another `--tag` or an option like Control Center pulls its own images on the first run. |
| 🖥️ ARM64 | The machine is x86_64, so examples marked ![arm64](https://img.shields.io/badge/arm64-not%20working-red) on Apple Silicon work there. |
| 🔐 Credentials | Cloud examples (AWS, GCP, Azure, Confluent Cloud…) need credentials: store them as [Codespaces secrets](https://docs.github.com/en/codespaces/managing-your-codespace/managing-secrets-for-your-codespaces) (they become environment variables), never in a committed file. Do not put customer data in a personal codespace. |
| 🏢 Company policy | Some companies block Codespaces or Docker-in-Docker. Use the [one command install](/how-to-use?id=%e2%9a%a1-install-in-one-command) or [playground ec2](/playground%20ec2) instead. |

> [!TIP]
> `?quickstart=1` in the link reopens your existing codespace instead of creating a new one each time. The same `.devcontainer` also works locally with the VS Code [Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers) extension.

#### 🧠 From the terminal: playground codespace

The same codespaces can be managed from your laptop with [playground codespace](/playground%20codespace), the way [playground ec2](/playground%20ec2) manages EC2 instances. It uses the [GitHub CLI](https://cli.github.com), which needs the `codespace` scope once:

```bash
gh auth refresh -h github.com -s codespace
```

```bash
playground codespace create --suffix 123456        # 👷 pg-<you>-123456 on 4 cores (--machine 8-core), opened in VS Code
playground codespace list                          # 🔘 your codespaces and their state
playground codespace ssh -- playground status      # 🐚 run one command in it (or a shell without --)
playground codespace open --web                    # 🌐 VS Code in the browser
playground codespace push-secrets                  # 🔐 your secrets store, imported into the codespace's own store
playground codespace sync-repro-folder local-to-codespace   # 👉 your reproduction models (codespace-to-local to bring them back)
playground codespace stop                          # 🔴 stop the running ones, 'start' to resume
playground codespace delete                        # ❌ delete them (asks first, shows unpushed work)
```

Without `--codespace`, a command acts on your most recently used codespace (`stop` and `delete` on all of them). Set `PLAYGROUND_CODESPACE_REPO` to create them from your fork.

`playground codespace create --push-secrets --sync-repro-folder` does both once the codespace is available. `push-secrets` resolves your store on your laptop (1Password, macOS Keychain…) and imports it into the store of the codespace (`file` backend), credentials as credentials and plain variables as plain variables: `playground run` there then loads what each example needs, with nothing to install and no 1Password token in the codespace. The values are stored in clear text in the codespace (`secrets.ini`, mode 0600), and **Rebuild Container** empties the home directory: run `push-secrets` again after a rebuild. `reproduction-models` is a private submodule that a codespace cannot clone: run `sync-repro-folder codespace-to-local` before `delete`, nothing else brings back the models written there.

### 💻️ Locally

#### ⚡ Install in one command

Paste this in a terminal (macOS, Linux or Windows WSL 2):

```bash
curl -fsSL https://kafka-docker-playground.io/install.sh | bash
```

It asks before each change, and only does this:

1. **checks** your machine and changes nothing: git, bash 4+, fzf, python3, docker + compose v2 (or Podman), free disk space
2. **installs what is missing** (bash, fzf, git, python3 for the support commands like `playground analyze`, unzip) with Homebrew on macOS or the package manager on Linux, and the [Confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html) used by the Confluent Cloud examples (Homebrew on macOS, else the official installer into `~/.local/bin`)
3. **clones** the repository into `~/kafka-docker-playground` (latest version only), or updates the clone you already have
4. **offers to install a container engine**, only when none is installed at all (see below)
5. **adds one block** to `~/.zshrc` (or `~/.bashrc`, `~/.bash_profile`), with a backup of the file, so that `playground` and its completion are in your `PATH`:

   ```bash
   # >>> kafka-docker-playground >>>
   export PATH="$HOME/kafka-docker-playground/scripts/cli:$PATH"
   source "$HOME/kafka-docker-playground/scripts/cli/completions.zsh"
   # <<< kafka-docker-playground <<<
   ```

6. **runs** [playground doctor](/playground%20doctor) to check that the container engine is ready

Then open a new terminal and run `playground run`.

##### 🐳 Container engine

When no engine answers and none is installed, the installer asks which one to install:

| Platform | Choices | What it runs |
| --- | --- | --- |
| macOS | 🦭 **Podman** (default): free, installed and started for you | `brew install podman docker docker-compose`, links the compose plugin into `~/.docker/cli-plugins`, `podman machine init --rootful --cpus 4 --memory 12288 --disk-size 100` (less memory on a Mac with less than 16GB), then [playground switch-podman](/playground%20switch-podman) |
| macOS | 🐳 **Docker Desktop** | `brew install --cask docker-desktop` and `open -a Docker`: accept its agreement in the window, the installer waits for the engine. Give it at least 8GB of memory in Settings > Resources |
| Linux | 🐳 **Docker Engine**: free | Docker's installer (`https://get.docker.com`, Ubuntu, Debian, Fedora, CentOS, RHEL), `sudo systemctl enable --now docker`, and adds you to the `docker` group (applies to your next login) |
| Windows WSL 2 | none | install [Docker Desktop for Windows with the WSL 2 integration](https://docs.docker.com/desktop/features/wsl/). With systemd enabled in the distribution, Docker Engine is offered as on Linux |

> [!WARNING]
> Docker Desktop needs a [paid subscription](https://www.docker.com/pricing/faq/) in companies with more than 250 employees or more than $10 million revenue: check that yours has one, or pick Podman.

- An engine already installed but stopped (Docker Desktop, OrbStack, Rancher Desktop, Colima, Podman) is never replaced: the installer tells you how to start it.
- `--yes` alone never installs an engine: pass `--engine podman`, `--engine docker-desktop` (macOS), `--engine docker` (Linux) or `--engine none`.
- `--uninstall` leaves the engine installed.

> [!TIP]
> Want to read it first? The script is [docs/install.sh](https://github.com/vdesabou/kafka-docker-playground/blob/master/docs/install.sh). See what it would do without changing anything:
>
> ```bash
> curl -fsSL https://kafka-docker-playground.io/install.sh | bash -s -- --dry-run
> ```

| Option | What it does |
| --- | --- |
| `--dry-run` | show what would be done, change nothing |
| `--yes` | answer yes to every question (no prompt, for scripts) |
| `--dir <path>` | clone somewhere else than `~/kafka-docker-playground` |
| `--no-rc` | do not touch any shell startup file, print the lines to add instead |
| `--no-confluent-cli` | do not install the Confluent CLI (only needed by the Confluent Cloud examples) |
| `--engine <engine>` | container engine to install when none is found, without asking: `podman` or `docker-desktop` on macOS, `docker` on Linux, `none` |
| `--uninstall` | remove the block from your shell startup files, then offer to delete the folder (default: keep it, it may hold your `playground.ini` and reproduction models) |

Pass options after `bash -s --`, for example `curl -fsSL https://kafka-docker-playground.io/install.sh | bash -s -- --uninstall`. Running it again is safe: it updates the clone and leaves the block as it is.

Prefer to do it by hand? Follow the sections below.

#### ☑️ Prerequisites

* You just need to have [docker](https://docs.docker.com/get-docker/) with the [compose v2 plugin](https://docs.docker.com/compose/install/) (`docker compose` 2.0.0 or greater) installed on your machine, or [Podman](/how-to-use?id=%f0%9f%a6%ad-using-podman-instead-of-docker) 5.0 or greater !

* Install the [🧠 CLI](/cli) by following [Setup](/cli?id=%f0%9f%9a%9c-setup). [fzf](https://github.com/junegunn/fzf) is required when using CLI (see installation [instructions](https://github.com/junegunn/fzf#installation))

* bash version 4 or higher is required. Mac users can upgrade bash with [brew](https://brew.sh/) by running `brew install bash` and then make sure it is in PATH (`export PATH=/opt/homebrew/bin:$PATH`)

* python3 (3.9 or later, standard library only) is required by the support commands: `playground analyze`, `schema diff|history|import|compare`, `connector-plugin`, `connector diagnose`, `streams status`, `topic check-format`. macOS has it with the Xcode Command Line Tools (`xcode-select --install`), Linux distributions ship it. `unzip` is also needed (`sudo apt-get install -y unzip` on a minimal Linux)

* You also need internet connectivity when running connect tests as connectors are downloaded from Confluent Hub on the fly.

> [!TIP]
> Run [playground doctor](/playground%20doctor) first: it checks that the container engine is reachable, that compose v2 is there and that there is enough memory. It is the one command that still works when the engine is down.

> [!NOTE]
> Every command used in the playground is using Docker, this includes `jq` (except if you have it on your host already), `aws`, `az`, `gcloud`, etc...Only exceptions are `fzf` and `confluent`
> 
> The goal is to have a consistent behavior and only depends on Docker.

> [!WARNING]
> The playground is only tested on macOS (including with [M1 *arm64* chip](/how-to-use?id=%f0%9f%a7%91%f0%9f%92%bb-m1-chip-arm64-mac-support)) and Linux (Ubuntu and Amazon Linux) . It is not tested on Windows, but it should be working with WSL.

> [!ATTENTION]
> On MacOS, the [Docker memory](https://docs.docker.com/desktop/settings-and-maintenance/settings/#resources) should be set to at least 8Gb.

#### 🧑‍💻 M1 chip (ARM64) Mac Support

Examples in the playground have been tested on best effort (since it is a manual process) on M1 Mac (arm64).

arm64 support results are displayed in **[Content](/content.md)** section:

Example:

![arm64_results](./images/arm64_results.jpg)

The badges are:

* ![arm64](https://img.shields.io/badge/arm64-native%20support-green): example works natively.
* ![arm64](https://img.shields.io/badge/arm64-not%20working-red): example **cannot work at all**. You will need to run it using AWS EC2 instance, see [playground ec2](/playground%20ec2) CLI command, or in your browser with [GitHub Codespaces](/how-to-use?id=%f0%9f%8c%90-in-your-browser-github-codespaces) (x86_64)
* ![arm64](https://img.shields.io/badge/arm64-emulation%20required-orange): example is working but emulation is required. 

Docker Desktop now provides **Rosetta 2** virtualization feature, see detailed steps [here](https://levelup.gitconnected.com/docker-on-apple-silicon-mac-how-to-run-x86-containers-with-rosetta-2-4a679913a0d5) on how to enable it, basically, you need to enable this:

![rosetta](./images/arm64_rosetta.jpg)

#### 🔽 Clone the repository

```bash
git clone --depth 1 https://github.com/vdesabou/kafka-docker-playground.git
```

> [!TIP]
> Specifying `--depth 1` only get the latest version of the playground, which reduces a lot the size of the download.

### ☁️ AWS EC2 instance (using Cloud Formation)

If you want to run the playground on an EC2 instance, you can use the AWS Cloud Formation [template](https://github.com/vdesabou/kafka-docker-playground/blob/master/cloudformation/kafka-docker-playground.yml).

More details [here](https://github.com/vdesabou/kafka-docker-playground/tree/master/cloudformation).

### ✨ AWS EC2 playground ec2 command

The [playground ec2](/playground%20ec2) CLI command creates and manages AWS EC2 instances (using Cloud Formation) to run kafka-docker-playground, and opens them directly in Visual Studio Code using Remote Development (over SSH).

It is what you want for an example that needs far more CPU or memory than you have, one that must run for hours, or one that does not work on arm64.

Main subcommands are `create`, `open`, `list`, `status`, `start`, `stop`, `delete`, `allow-my-ip`, `sync-repro-folder` and `push-secrets`: check [playground ec2](/playground%20ec2) for the full reference.

## 🦭 Using Podman instead of Docker

The playground can run on [Podman](https://podman.io) instead of Docker, with nothing to change in
the examples.

It always drives the container engine through the `docker` CLI and the `docker compose` plugin. With
Podman you keep both, and point them at the **rootful Podman socket** with
[playground switch-podman](/playground%20switch-podman) (or `DOCKER_HOST`). The playground detects it
and adapts on its own:

- image builds use Podman's own builder (`DOCKER_BUILDKIT=0` is set automatically), so images patched
  locally, like the connect image with its extra tools, are used and kept
- bind mounts of `/tmp` use the resolved path, `/private/tmp` on macOS, which a Podman machine shares

Run `playground doctor` to check that your engine is ready. It is the one command that still works
when the engine is down.

```
$ playground doctor
🩺 Checking the container engine
✅ 'docker' CLI found: Docker version 29.8.1
🦭 engine detected: podman
✅ engine is reachable
✅ 'docker compose' is 5.5.1
✅ engine memory is 11GB
✅ builds use the classic builder (DOCKER_BUILDKIT=0)
✅ podman is running rootful
✅ podman network backend is netavark
✅ docker.io is in the podman search registries
✅ the podman machine shares /Users/me
✅ the podman machine shares /private
✅ the podman machine shares /var/folders
🩺 all good, the podman engine is ready for the playground
```

`playground status` also shows which engine is in use.

### 🍏 Setup on macOS

```bash
podman machine init --rootful --cpus 4 --memory 12288 --disk-size 100
podman machine start

playground switch-podman    # points docker and docker compose at the podman socket, ends with playground doctor
```

- The playground needs at least 8GB of memory.
- Do not pass any `-v` to `podman machine init`. The defaults share `/Users`, `/private` and
  `/var/folders`, which is what the playground mounts from, and any `-v` replaces them.
- An existing machine can be switched to rootful with
  `podman machine stop && podman machine set --rootful && podman machine start`.
- Instead of `playground switch-podman`, you can also
  `export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"`.

### 🐧 Setup on Linux

```bash
# podman, plus netavark and aardvark-dns so that containers resolve each other by name
sudo apt-get install -y podman netavark aardvark-dns    # or: sudo dnf install -y podman

# rootful socket, made accessible to your user's group
sudo mkdir -p /etc/systemd/system/podman.socket.d
sudo tee /etc/systemd/system/podman.socket.d/99-playground.conf << EOF
[Socket]
ListenStream=
ListenStream=/run/podman-api/podman.sock
SocketMode=0660
SocketGroup=$(id -gn)
DirectoryMode=0755
EOF
sudo systemctl daemon-reload
sudo systemctl stop podman.service
sudo systemctl enable --now podman.socket
sudo systemctl restart podman.socket

playground switch-podman    # points docker and docker compose at the podman socket, ends with playground doctor
```

- The socket is moved out of `/run/podman`, which Podman creates as `0700 root`: a socket in there
  stays unreachable for a regular user whatever its own permissions.
- Instead of `playground switch-podman`, you can also `export DOCKER_HOST="unix:///run/podman-api/podman.sock"`.
- Use the **real compose v2 plugin**, not `podman-compose`. `podman-compose` is a separate
  reimplementation with only partial support for `profiles:` and `build:`, which the playground relies
  on heavily.
- No `docker` CLI on the machine? Install `docker-ce-cli` and `docker-compose-plugin` from Docker's
  repository; neither needs the Docker daemon.
- On distributions with SELinux enforcing (Fedora, RHEL), add this to
  `/etc/containers/containers.conf`, because the playground's bind mounts are not labelled:

  ```toml
  [containers]
  label = false
  ```

### 🔀 Switching between Docker and Podman

[playground switch-podman](/playground%20switch-podman) creates a `podman` docker context, so the switch applies to your current shell and to new ones, with nothing to export (on macOS, the podman machine is started if needed).

[playground switch-docker](/playground%20switch-docker) restores the docker context that was active before. Both commands end with `playground doctor`.

> [!WARNING]
> Containers are not moved between engines: stop the running example first.

> [!NOTE]
> An exported `DOCKER_HOST` takes precedence over the docker context: while it is set, `playground switch-docker` and `playground switch-podman` have no effect. Run `unset DOCKER_HOST` (and remove it from your shell profile) to use them. `playground doctor` shows `🔌 DOCKER_HOST is …` when it is set.

## 🏎️ Start an example

Check the list of examples in the **[Content](/content.md)** section and simply use [playground run](/playground%20run) CLI command!

🎬 New here? The bite size session [Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) shows both ways and the options, in about 4 minutes.


> [!NOTE]
> When some environment variables are required, it is specified in the corresponding `README` file
> 
> Examples:
> 
> * [AWS S3 sink connector](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-aws-s3-sink#aws-setup): file `~/.aws/credentials` or environment variables `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are required.
> 
> * [Zendesk source connector](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-zendesk-source#how-to-run): arguments `ZENDESK_URL`, `ZENDESK_USERNAME` and `ZENDESK_PASSWORD` are required (you can also pass them as environment variables)
>

If there are missing environment variables, you'll need to fix it: [playground secrets check](/playground%20secrets%20check) tells you which ones, and [playground secrets set](/playground%20secrets%20set) stores them once for all your runs (see [below](/how-to-use?id=🔐-storing-credentials-with-playground-secrets)):

<video src="videos/secrets.mp4" autoplay loop muted playsinline controls width="100%"></video>

### 🕹️ The playground run menu

Running [playground run](/playground%20run) without `-f` opens an interactive menu: pick a category and an example, then select options (use `<tab>` to select several at once) before running it.

<video src="videos/run-menu.mp4" autoplay loop muted playsinline controls width="100%"></video>

* on/off options are toggles, `[x]` when enabled: select one again to disable it
* options that take a value show it once set, for example `🎯 CP version (all components)  --tag  [8.2.0]` (credentials only show `[set]`)
* only the options that apply to the example are shown (for example no connector version for an example without connector, no 🔐 Environment for an example that starts its own environment)
* the preview pane shows the flags that will be used, and warns about combinations that would not work: an error (for example legacy Control Center with CP 8, `--enable-kraft` with CP < 7.4) replaces "🚀 Run the example !" until it is fixed, a warning (for example Control Center with a community image) is only displayed. The same check runs before anything is stopped when not using the menu.
* actions: 🔀 switch to another example in the same folder, keeping the selected options, 🧪 create a reproduction model from the example (see [playground repro bootstrap](/playground%20repro%20bootstrap)), and ⚙️ change the CLI preferences (see below)

Esc or Ctrl-C quits without changing anything. The equivalent `playground run -f <example> <flags>` command is saved in the history ([playground history](/playground%20history), [playground re-run](/playground%20re-run)) and, on macOS, copied to the clipboard (disable with `playground config clipboard false`).

#### ⚙️ CLI preferences

The **⚙️ CLI preferences (playground config)** action opens a submenu with every [playground config](/playground%20config) preference and its current value (`default: …` when it was never set):

![playground run menu: CLI preferences entry](./images/run_menu_config_entry.png)

![playground run menu: CLI preferences submenu](./images/run_menu_config_preferences.png)

* editor used to open files, folders searched for connector zip or jar, copy of the connector config to the clipboard (macOS only)
* kill all containers before each run, deletion of the Confluent Cloud resources left by the last run (`ask`, `true` or `false`), check that the repository is up to date
* masked run log of each run, and its folder (see [📄 Sharing a run](/how-to-use?id=📄-sharing-a-run-the-masked-run-log))
* whether fully managed connectors and Grafana are opened in the browser, and in which browser

Pick a preference, then its new value: `true`/`false`, or a list of suggestions for the editor and the browser (type another one and use `<option+enter>`). The change is saved right away, exactly as the matching `playground config` command would, and the submenu stays open until 🔙 Back to the example menu.

#### 📄 Sharing a run: the masked run log

Every `playground run` also writes its output to a text file, with passwords, api keys and tokens masked, ready to attach to a ticket or to send to a colleague or engineering. Its path is the last line of the run:

```
📄 masked log of this run (4 secrets masked), to share with a colleague: /tmp/playground-run-logs/filestream-sink-20261026-151903.log
```

The file starts with a header (the command to re-run, environment, CP and connector versions, playground commit, host and container engine, duration and result), then the whole output of the run without colors and, for a failure, the errors of the connect container (`playground container logs -c connect --errors`):

```
# 📄 playground run log
command:      playground run -f connect/connect-filestream-sink/filestream-sink.sh --tag=8.3.2
environment:  plaintext
CP version:   8.3.2
connector:    default
playground:   1d95feddf
host:         Darwin 27.0.0, docker 29.8.2
started:      2026-10-26T14:19:03Z, duration 0min 23sec
result:       FAILURE (exit code 1)
masking:      secrets are masked with ********, best-effort: review this file before sharing it outside Confluent
```

What is masked: the values of the credentials exported for the example (loaded from `playground secrets`, or variables named `*PASSWORD*`, `*SECRET*`, `*TOKEN*`, `*KEY*`, `*CREDS*`…), the api keys of `playground.ini`, `~/.aws/credentials`, the value of secret-looking keys (`"connection.password": "…"`, `password=…` in properties, JDBC urls and JAAS configs, `password: …` in yaml), private keys, AWS access key ids, JWTs, `Bearer` tokens and `user:password@` in urls. A secret that the example builds itself is not known in advance: **the masking is best-effort, read the file before sharing it outside Confluent**.

* `--run-log-file <file>` writes it to that file, `--no-run-log` skips it for one run
* `playground config run-log false` never writes it, `playground config run-log-folder <folder>` changes the folder (default `/tmp/playground-run-logs`, the last 50 files are kept, readable by you only)
* the example still runs in a terminal (it is run under `script`), so colors, prompts and HTML reports behave as before
* nothing is written in CI, which already keeps the output of each run

### 🔐 Storing credentials with playground secrets

Instead of exporting variables in every shell, store them once with [playground secrets](/playground%20secrets): `playground run` then loads automatically the ones the example declares.

```bash
playground secrets set SALESFORCE_PASSWORD    # 🔐 store it, prompted
playground secrets check -f <example>         # ✅ what is still missing
playground run -f <example>                   # 🚀 loaded for you
```

They are stored in `~/.config/kafka-docker-playground` (never in the repository), with credential values kept in a backend such as macOS Keychain, secret-tool, pass, 1Password or HashiCorp Vault (see [playground secrets backend](/playground%20secrets%20backend)).

> [!TIP]
> 🍪 The deep dive [Credentials and the 1Password setup](/deep-dive-secrets.md) explains the store, the backends, profiles, and how to set up 1Password (desktop app, service account, shared team vault), with a hands-on lab.

> [!TIP]
> ☁️ The Salesforce examples need a configured Salesforce org: [Salesforce examples: set up an org](/salesforce.md) does it with `playground salesforce setup` (and `playground salesforce check` when a login fails).

## 🌤️ Confluent Cloud examples

Simply use [playground run](/playground%20run) command ! Below, the menu shows the Confluent Cloud options of a fully managed connector example (it quits before running it):

<video src="videos/ccloud-run-menu.mp4" autoplay loop muted playsinline controls width="100%"></video>

All you have to do is to be already logged in with [confluent CLI](https://docs.confluent.io/confluent-cli/current/overview.html#confluent-cli-overview).

By default, a new Confluent Cloud environment with a Cluster will be created.

You can configure the new cluster by using flags with [playground run](/playground%20run) command or just by setting environment variables:

* `--cluster-type` (or `CLUSTER_TYPE` environment variable): the type of cluster (possible values: `basic`, `standard` and `dedicated`, default `basic`)
* `--cluster-cloud` (or `CLUSTER_CLOUD` environment variable): The Cloud provider (possible values: `aws`, `gcp` and `azure`, default `aws`)
* `--cluster-region` (or `CLUSTER_REGION` environment variable): The Cloud region (use `confluent kafka region list` to get the list, default `eu-west-2` for aws, `westeurope` for azure and `europe-west2` for gcp)
* `--cluster-environment` (or `ENVIRONMENT` environment variable) (optional): The environment id where want your new cluster (example: `txxxxx`) 

In case you want to use your own existing cluster, you need to setup, in addition to previous ones:

* `--cluster-name` (or `CLUSTER_NAME` environment variable): The cluster name
* `--cluster-creds` (or `CLUSTER_CREDS` environment variable): The Kafka api key and secret to use, it should be separated with colon (example: `<API_KEY>:<API_KEY_SECRET>`)
* `--cluster-schema-registry-creds` (or `SCHEMA_REGISTRY_CREDS` environment variable) (optional, if not set, new one will be created): The Schema Registry api key and secret to use, it should be separated with colon (example: `<SR_API_KEY>:<SR_API_KEY_SECRET>`)

🤖 For [Fully Managed connectors](/content?id=%f0%9f%a4%96-fully-managed-connectors), as examples are [dependent of cloud providers](https://docs.confluent.io/cloud/current/connectors/index.html#cloud-platforms-support), you have the possibility to define specific existing clusters per cloud provider:

* AWS:

```bash
AWS_CLUSTER_NAME
AWS_CLUSTER_REGION
AWS_CLUSTER_CLOUD
AWS_CLUSTER_CREDS
```

* GCP:

```bash
GCP_CLUSTER_NAME
GCP_CLUSTER_REGION
GCP_CLUSTER_CLOUD
GCP_CLUSTER_CREDS
```

* AZURE:

```bash
AZURE_CLUSTER_NAME
AZURE_CLUSTER_REGION
AZURE_CLUSTER_CLOUD
AZURE_CLUSTER_CREDS
```

For example, if you're running an AZURE Fully Managed connector example and `AZURE_CLUSTER_NAME` is set, then this cluster will be used even if you have `CLUSTER_NAME` set.

### 👤 Fully managed connectors with a service account

Add `--ccloud-service-account` (or tick *👤 Connector service account* in the run menu) to run the fully managed connectors of an example with a [service account](https://docs.confluent.io/cloud/current/connectors/service-account.html) (`kafka.auth.mode=SERVICE_ACCOUNT`) and the ACLs of the documentation, instead of an API key. Then remove or deny ACLs with `playground rbac acl --connector <connector>` to reproduce authorization errors: see [Fully managed connectors with a service account](/toolkit-fully-managed?id=%f0%9f%91%a4-fully-managed-connectors-with-a-service-account).

![playground run menu: Connector service account toggle](./images/run_menu_ccloud_service_account.png)

## 🪄 Specify versions

[playground run](/playground%20run) command allows you to do that very easily !

![specify versions](./images/versions.jpg)

### 🎯 For Confluent Platform (CP)

By default, the latest Confluent Platform version supported by the playground is used (currently CP 8.4.0, which is [KRaft](/how-to-use?id=📡-kraft-mode) only). Use `--tag` option of [playground run](/playground%20run) (or `TAG` environment variable) to run with another version.

> [!TIP]
> You can also change cp version while running an example using [playground update-version](/playground%20update-version)

### 🔗 For Connectors

By default, for each connector, the latest available version on [Confluent Hub](https://www.confluent.io/hub/) is used. 

The only 2 exceptions are:

* replicator which is using same version as CP (but you can force a version using `REPLICATOR_TAG` environment variable)
* JDBC which is using same version as CP (but only for CP version lower than 6.x)

Each latest version used is specified on the [Connectors list](/content?id=%f0%9f%94%97-connectors).

The playground has 3 different ways to use different connector version when running a connector example:

1. Specify the connector version (`--connector-tag` using [playground run](/playground%20run) command)

2. Specify a connector ZIP file (`--connector-zip` using [playground run](/playground%20run) command)

3. Specify a connector JAR file (`--connector-jar` using [playground run](/playground%20run) command)

*Example:*

```bash
00:33:47 ℹ️ 🎯 CONNECTOR_JAR is set with /tmp/kafka-connect-http-1.3.1-SNAPSHOT.jar
/usr/share/confluent-hub-components/confluentinc-kafka-connect-http/lib/kafka-connect-http-1.2.4.jar
00:33:48 ℹ️ 👷 Building Docker image confluentinc/cp-server-connect-base:cp-6.2.1-kafka-connect-http-1.2.4-kafka-connect-http-1.3.1-SNAPSHOT.jar
00:33:48 ℹ️ Remplacing kafka-connect-http-1.2.4.jar by kafka-connect-http-1.3.1-SNAPSHOT.jar
```

When jar to replace cannot be found automatically, the user is able to select the one to replace automatically:

```bash
11:02:43 ℹ️ 🎯 CONNECTOR_JAR is set with /tmp/debezium-connector-postgres-1.4.0-SNAPSHOT.jar
ls: cannot access '/usr/share/confluent-hub-components/debezium-debezium-connector-postgresql/lib/debezium-connector-postgresql-1.4.0.jar': No such file or directory
11:02:44 ❗ debezium-debezium-connector-postgresql/lib/debezium-connector-postgresql-1.4.0.jar does not exist, the jar name to replace could not be found automatically
11:02:45 ℹ️ Select the jar to replace:
1) debezium-api-1.4.0.Final.jar
2) debezium-connector-postgres-1.4.0.Final.jar
3) debezium-core-1.4.0.Final.jar
```

> [!WARNING]
> You can use both `--connector-tag` and `--connector-jar` at same time (along with `--tag`), but `--connector-tag` and `--connector-zip` are mutually exclusive.

> [!NOTE]
> For more information about the Connect image used, check [here](/how-it-works?id=🔗-connect-image-used).

> [!TIP]
> You can also change connector(s) version(s) while running an example using [playground update-version](/playground%20update-version)

## 🐳 Overriding Confluent Platform Docker images and tags

Community images can be selected with [playground run](/playground%20run) options (or in the menu):

* `--connect-community-image`: connect runs `confluentinc/cp-kafka-connect` instead of `confluentinc/cp-server-connect` (monitoring interceptors are disabled)
* `--kafka-community-image`: broker and controller run `confluentinc/cp-kafka` instead of `confluentinc/cp-server` (Confluent Metrics Reporter and Telemetry Reporter are disabled)

Docker images being used can also be overridden by exporting following environment variables:

* zookeeper (`CP_ZOOKEEPER_IMAGE`) (CP < 8 only)
* kafka (`CP_KAFKA_IMAGE`)
* connect (`CP_CONNECT_IMAGE`)
* schema-registry (`CP_SCHEMA_REGISTRY_IMAGE`)
* control-center (`CP_CONTROL_CENTER_IMAGE`)
* ksqlDb (`CP_KSQL_IMAGE`)
* ksqlDB CLI (`CP_KSQL_CLI_IMAGE`)
* rest-proxy (`CP_REST_PROXY_IMAGE`)

Docker images tags being used can be overridden by exporting following environment variables (or with the [playground run](/playground%20run) option, when there is one):

* zookeeper (`CP_ZOOKEEPER_TAG`) (CP < 8 only)
* kafka (`CP_KAFKA_TAG`)
* connect (`CP_CONNECT_TAG`, `--connect-tag`)
* schema-registry (`CP_SCHEMA_REGISTRY_TAG`, `--schema-registry-tag`, not for ccloud examples)
* control-center (`CP_CONTROL_CENTER_TAG`, `--control-center-tag`): a Control Center Next Gen version (for example `2.6.1`, default `latest`), or a CP version with legacy Control Center
* ksqlDb (`CP_KSQL_TAG`) and ksqlDB CLI (`CP_KSQL_CLI_TAG`): `--ksqldb-tag` sets both
* rest-proxy (`CP_REST_PROXY_TAG`)

The java applications that some examples build (Kafka Streams, producers, consumers) use the Apache Kafka clients matching the CP version (`KAFKA_CLIENT_TAG`, CP 8.2 → 4.2.0). `--client-version 3.7.1` (`CLIENT_VERSION`) pins another version, a patch version included, for example the customer's Kafka Streams version. For the client examples (`other/client-*`, `ccloud/client-*`), it is the version of their client (librdkafka, confluent-kafka-python…). Press <kbd>TAB</kbd> after `--client-version` (with `-f` typed before it, otherwise the last example run is used) to pick one of the published versions of that client in fzf, releases first; the interactive menu offers the same list.

*Example:* schema registry 7.9.1 with everything else on 8.3.2:

```bash
playground run -f datagen-source<tab> --schema-registry-tag 7.9.1
```

## 📡 Kraft mode

[Kraft](https://docs.confluent.io/platform/current/kafka-metadata/kraft.html) is enabled by default when used with CP 8+. For CP 7.4 to 7.9, you can force it with `--enable-kraft` option of [playground run](/playground%20run) (or by setting environment variable `ENABLE_KRAFT`). It is refused for CP < 7.4, and has no effect with CP 8+.

In Kraft mode, a `controller` container replaces the `zookeeper` container (its JMX port is `10005`). ZooKeeper is only used with CP < 8 when `ENABLE_KRAFT` is not set.

## ⛳ Options

Selecting options is really easy with [playground run](/playground%20run) menu:

![options](./images/options.jpg)

> [!NOTE]
> The `ENABLE_*` environment variables below (`ENABLE_KSQLDB=1`, `ENABLE_CONTROL_CENTER=1`…) are the same as the matching `--enable-*` option: when one is exported in your shell, [playground run](/playground%20run) prints `🌱 ENABLE_CONTROL_CENTER is set in your shell: same as --enable-control-center` and adds the option to the run, so that `playground history`, `playground re-run` and the run log replay it. Unset it (`unset ENABLE_CONTROL_CENTER`) to stop enabling the component on every run.

### 🚀 Enabling ksqlDB

By default, `ksqldb-server` and `ksqldb-cli` containers (see [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml)) are not started for every test.

You can enable this with `--enable-ksqldb` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_KSQLDB=1` in your shell.

🧮 Then run ksqlDB statements and inspect the streams, tables and queries with [playground ksqldb](/playground%20ksqldb), instead of `docker exec ksqldb-cli ksql` or `curl` on the REST API (`http://127.0.0.1:8088`):

```bash
# one ksql cli session: SET 'auto.offset.reset' applies to the statements that follow it in the same call
playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM orders (id INT, product VARCHAR) WITH (kafka_topic='orders', value_format='json', partitions=1);
CREATE TABLE orders_by_product AS SELECT product, COUNT(*) AS nb FROM orders GROUP BY product EMIT CHANGES;
INSERT INTO orders (id, product) VALUES (1, 'foo');
EOF

playground ksqldb wait                                   # the persistent queries are RUNNING and have no lag (instead of a sleep)
playground ksqldb sql <<< "SELECT * FROM orders_by_product WHERE product = 'foo';"
playground ksqldb list                                   # streams, tables, queries and their state
playground ksqldb describe --source orders_by_product    # fields, queries with their lag, statistics, errors
```

A failing statement makes `playground ksqldb sql` exit with code 1 (the other statements are still run): add `--ignore-errors` when the failure is expected. A push query (`EMIT CHANGES`) needs a `LIMIT` or `--query-timeout`, otherwise it is stopped after `--max-wait` seconds.

### 💠 Enabling Control Center

By default, `control-center` container (see [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml)) is not started for every test.

You can enable this with `--enable-control-center` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_CONTROL_CENTER=1` in your shell.

Control Center "Next Gen" (image `confluentinc/cp-enterprise-control-center-next-gen`) is used by default. If you want to use the legacy image, use `--enable-legacy-control-center` option of [playground run](/playground%20run) (it also enables Control Center), or set environment variable `ENABLE_LEGACY_CONTROL_CENTER=1` in your shell. Legacy Control Center is only available for CP < 8.

Use `--control-center-tag` to select the Control Center version (see [above](/how-to-use?id=🐳-overriding-confluent-platform-docker-images-and-tags)).

Control Center is reachable at http://127.0.0.1:9021

### 🐺 Enabling Conduktor Platform

By default, [`Conduktor Platform`](https://www.conduktor.io) container is not started for every test. 

You can enable this with `--enable-conduktor` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_CONDUKTOR=1` in your shell.

Conduktor is reachable at [http://127.0.0.1:8080/console](http://127.0.0.1:8080/console) (`admin`/`admin`).

### 🧲 Enabling REST Proxy

By default, `rest-proxy` container is not started for every test.

You can enable this with `--enable-rest-proxy` option of [playground run](/playground%20run).

### 🔢 Enabling multiple brokers

By default, there is only one kafka node enabled. To enable three nodes, select it in menu or use `--enable-multiple-brokers` option of [playground run](/playground%20run).

With three nodes, the internal topics (`__consumer_offsets`, `__transaction_state`, `connect-offsets`, `connect-configs`, `connect-status`, `_confluent-license`, `_confluent-link-metadata`…) are created with 3 replicas and a min ISR of 2, like in production: a broker can be stopped (`playground broker stop`) or restarted (`playground broker rolling-restart`) without making them unavailable. With one node, they have 1 replica. See the [brokers and transactions deep dive](/deep-dive-broker.md).

### 🗳️ Enabling multiple controllers

By default, there is only one KRaft controller (or, with CP < 8 in ZooKeeper mode, one ZooKeeper node). To get a quorum of three, select it in menu or use `--enable-multiple-controllers` option of [playground run](/playground%20run):

| Mode | Containers | Settings |
| --- | --- | --- |
| KRaft (CP ≥ 8, or `--enable-kraft`) | `controller`, `controller2`, `controller3` (node ids 4, 5 and 6, JMX ports 10005, 12005, 13005) | `controller.quorum.voters=4@controller:9093,5@controller2:9093,6@controller3:9093` |
| ZooKeeper | `zookeeper`, `zookeeper2`, `zookeeper3` (JMX ports 9999, 12999, 13999) | `zookeeper.connect=zookeeper:2181,zookeeper2:2181,zookeeper3:2181` |

One node of the quorum can then be stopped (`playground container kill -c controller2`) without making the cluster unavailable: `playground broker health` shows the KRaft quorum, its leader and the lag of each voter. It works with every environment except the `mdc-*` ones (one ZooKeeper / controller per cluster), where it is ignored. On `cfk` and `cfk-rbac`, the `KRaftController` CR gets 3 replicas (pods `kraftcontroller-0`, `kraftcontroller-1`, `kraftcontroller-2`; `-c controller2` resolves to `kraftcontroller-1`), or the `Zookeeper` CR with `cfk` in ZooKeeper mode (pods `zookeeper-0`, `-1`, `-2`). Combine it with `--enable-multiple-brokers` for a cluster without any single point of failure.

### 🥉 Enabling multiple connect workers

By default, there is only one connect node enabled. To enable three connect nodes, select it in menu or use `--enable-multiple-connect-workers` option of [playground run](/playground%20run).

`connect2` and `connect3` get the `connect` configuration of the example: the playground generates a copy of the example's docker-compose override file with them under `/tmp/playground-connect-workers/`, the example's own file is not modified.

### 🌀 Enabling SQL Datagen

For the JDBC, Debezium, Oracle CDC and XStream source examples (Oracle, MySQL, MariaDB, PostgreSQL, SQL Server, self-managed and fully managed), the `--enable-sql-datagen` option of [playground run](/playground%20run) keeps inserting rows once the example is done: the `benchmark-load.bash` of the example, one row per transaction, in 5 parallel sessions, for 10 minutes (`SQL_DATAGEN_SESSIONS`, `SQL_DATAGEN_DURATION`). See [Databases: keep a load running](/toolkit-performance?id=%f0%9f%8c%aa%ef%b8%8f-databases-keep-a-load-running-with-enable-sql-datagen).

### 🎯 Starting only some services

Set environment variable `START_SERVICES` with a space-separated list of services (example: `START_SERVICES="broker schema-registry connect"`) to start only those services of the environment.

### 📊 Enabling JMX Grafana

By default, Grafana dashboard using JMX metrics is not started for every test.

You can enable this with `--enable-jmx-grafana` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_JMX_GRAFANA=1` in your shell.

📊 Grafana is reachable at [http://127.0.0.1:3000](http://127.0.0.1:3000)
🛡️ Prometheus is reachable at [http://127.0.0.1:9090](http://127.0.0.1:9090) (it scrapes the JMX exporters every 15 s)
📛 [Pyroscope](https://pyroscope.io/docs/) is reachable at [http://127.0.0.1:4040](http://127.0.0.1:4040)

It works with the single-cluster environments and with the multi data center environment `mdc-plaintext`: there, the `env` variable of the dashboards picks the cluster (`europe` or `us`), and the Kafka Lag Exporter watches both clusters (see [environment/mdc-plaintext](https://github.com/vdesabou/kafka-docker-playground/tree/master/environment/mdc-plaintext)).

> [!TIP]
> [playground connector benchmark](/toolkit-performance?id=%f0%9f%93%8a-grafana) annotates its measure on the Kafka Connect, connector and Kafka cluster dashboards, and links to them at the time of the run.

#### Grafana dashboards

List of provided dashboards:
 - Confluent Platform overview
 - Zookeeper cluster (CP < 8 only)
 - Kafka cluster
 - Kafka topics
 - Kafka quotas
 - Schema Registry cluster
 - Kafka Connect cluster
 - ksqlDB cluster
 - Kafka streams RocksDB
 - Kafka Clients
 - Oracle CDC source Connector
 - Oracle XStream CDC source Connector
 - Debezium CDC source Connectors
 - Mongo source and sink Connector
 - Kafka lag exporter (no screenshot)
 - Cluster Linking (no screenshot): with the `mdc-plaintext` environment, for example `playground run -f multi-data-center/cluster-linking/start-plaintext.sh --enable-jmx-grafana`
 - Flink (no screenshot)


<!-- tabs:start -->

#### **Confluent Platform overview**

![Confluent Platform overview](images/confluent-platform-overview.png)

#### **Zookeeper cluster (CP < 8 only)**

![Zookeeper cluster dashboard](images/zookeeper-cluster.png)

#### **Kafka cluster**

![Kafka cluster dashboard 0](images/kafka-cluster-0.png)
![Kafka cluster dashboard 1](images/kafka-cluster-1.png)

#### **Kafka topics**

![Kafka topics](images/kafka-topics.png)

#### **Kafka quotas**

For Kafka to output quota metrics, at least one quota configuration is necessary.

A quota can be configured using:

```bash
playground quota set --user unknown --client-id unknown --producer-byte-rate 10000 --consumer-byte-rate 30000 --request-percentage 0.2
```

See [playground quota](/playground%20quota) to display (`quota get`) and remove (`quota delete`) quotas, or to set one on the tasks of a connector (`--connector`).

![Kafka quotas](images/kafka-quotas.png)

#### **Schema Registry cluster**

![Schema Registry cluster](images/schema-registry-cluster.png)

#### **Kafka Connect cluster**

![Kafka Connect cluster dashboard 0](images/kafka-connect-cluster-0.png)
![Kafka Connect cluster dashboard 1](images/kafka-connect-cluster-1.png)

#### **ksqlDB cluster**

![ksqlDB cluster dashboard 0](images/ksqldb-cluster-0.png)
![ksqlDB cluster dashboard 1](images/ksqldb-cluster-1.png)

#### **Kafka streams RocksDB**

![kafkastreams-rocksdb 0](images/kafkastreams-rocksdb.png)

#### **Kafka Clients**

![Kafka Producer](images/kafka-producer.png)

![Kafka Consumer](images/kafka-consumer.png)

#### **Oracle CDC source Connector**

![oraclecdc](images/oraclecdc.jpg)

#### **Oracle XStream CDC source Connector**

![oraclexstreamcdc](images/oraclexstreamcdc.jpg)

#### **Debezium CDC source Connectors**

![debezium](images/debezium.png)

#### **Mongo source and sink Connector**

![mongo](images/mongo.png)

<!-- tabs:end -->


### 🐈‍⬛ Enabling kcat

By default, [edenhill/kcat](https://github.com/edenhill/kcat) is not started for every test. 

You can enable this with `--enable-kcat` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_KCAT=1` in your shell.

Then you can use it with:

```bash
playground container exec -c kcat --command "kcat -b broker:9092 -L"
```

### 🐹 Enabling Flink

By default, Flink task/jobmanager is not started for every test. 

You can enable Flink for any connector using plaintext deployment with `--enable-flink` option of [playground run](/playground%20run) or by setting environment variable `ENABLE_FLINK=1` in your shell. 

Once enabled, the CLI will ask if you need to download any connectors. Based on the response, you can download one or more connectors from Flink's [maven](https://repo.maven.apache.org/maven2/org/apache/flink/) repository. To skip the question (in a script or CI), set `FLINK_URL` to the jar(s) to download.

🐹 Flink UI and REST API are reachable using [http://127.0.0.1:18081](http://127.0.0.1:18081).

Then run Flink SQL and manage the jobs with [playground flink](/playground%20flink) (see the [Flink SQL with Kafka](https://github.com/vdesabou/kafka-docker-playground/tree/master/flink/flink-sql-kafka) example):

```bash
# one SQL client session: CREATE TABLE and the INSERT INTO that uses it go in the same call
playground flink sql << 'EOF'
CREATE TABLE orders (id INT, product STRING) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
CREATE TABLE sink (id INT, product STRING) WITH ('connector' = 'print');
INSERT INTO sink SELECT * FROM orders;
EOF

playground flink list-jobs            # state, start time, duration, root cause of FAILED jobs
playground flink cancel --all         # or --job <id>
```

The same commands manage the statements of a **Confluent Cloud** Flink compute pool with `--environment ccloud` (the default after a ccloud example): see the [Flink SQL on Confluent Cloud](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/flink-sql-kafka) example and the [deep dive](/deep-dive-flink?id=_6-confluent-cloud-flink-environment-ccloud).

## 🔢 JMX Metrics

JMX metrics are available locally on those ports:

* broker: `10000` (`broker2`: `12000`, `broker3`: `13000` with multiple brokers)
* schema-registry: `10001`
* connect: `10002` (`connect2`: `10022`, `connect3`: `10032` with multiple connect workers)
* ksqldb-server: `10003`
* controller: `10005` (Kraft mode)
* zookeeper: `9999` (CP < 8 only)

For a digest instead of raw MBeans, one command per component, with ⚠️ on the values to look at:

| Component | Command |
| --- | --- |
| brokers, and the controllers (KRaft) | [playground broker metrics](/playground%20broker%20metrics) (`--topic <t>`, `--controller` for the controller section only, `--json`) |
| a connector, one column per task | [playground connector metrics](/playground%20connector%20metrics) (`--connector <c>`, `--watch 10s`, `--json`) |
| the connect workers | `playground connector metrics --worker` |
| Schema Registry | [playground schema metrics](/playground%20schema%20metrics) |
| ksqlDB | [playground ksqldb metrics](/playground%20ksqldb%20metrics) |

For the raw MBeans, use [playground get-jmx-metrics](/playground%20get-jmx-metrics). `--container` (`-c`) can be repeated (default is `connect`). Without a filter, it lists the JMX domains of the container: then `--domain` (`-d`) dumps one or several domains, `--mbean` (`-m`, repeatable) only the MBeans matching a name (a `*` is allowed in a value: `"kafka.server:type=ReplicaManager,*"`), and `--all` every MBean. `--open` (`-o`) saves the output to `/tmp/jmx_metrics-<container>.log` and opens it with your editor. It works with any container that exposes JMX (its port is read from the `*_JMX_PORT` environment variable of the container: `broker2`, `ksqldb-server`, `broker-us` in `mdc-*` environments…) and with the pods of `cfk`, and jmxterm runs inside the container: no local Java needed.

```bash
playground get-jmx-metrics -c connect                                          # the domains of the container
playground get-jmx-metrics -c connect -c broker --domain "kafka.server"
playground get-jmx-metrics -c broker --mbean "kafka.server:type=ReplicaManager,*"
playground get-jmx-metrics -c connect --all --open                             # everything, in your editor
```

Example (specifying domain):

```bash
$ playground get-jmx-metrics -c connect -d "kafka.connect kafka.consumer kafka.producer"
####### domain kafka.connect ########
…
####### domain kafka.consumer ########
…
```

The [observability deep dive](/deep-dive-observability.md) maps each support question to its metric.

## 📝 See properties file

Because the playground uses **[Docker override](/how-it-works?id=🐳-docker-override)**, not all configuration parameters are in same `docker-compose.yml` file.

In order to easily see the end result properties file, you can use [playground container get-properties](/playground%20container%20get-properties) command

*Example:*

```bash
$ playground get-properties -c connect
bootstrap.servers=broker:9092
config.providers.file.class=org.apache.kafka.common.config.provider.FileConfigProvider
config.providers=file
config.storage.replication.factor=1
config.storage.topic=connect-configs
connector.client.config.override.policy=All
consumer.confluent.monitoring.interceptor.bootstrap.servers=broker:9092
consumer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor
group.id=connect-cluster
internal.key.converter.schemas.enable=false
internal.key.converter=org.apache.kafka.connect.json.JsonConverter
internal.value.converter.schemas.enable=false
internal.value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter=org.apache.kafka.connect.storage.StringConverter
log4j.appender.stdout.layout.conversionpattern=[%d] %p %X{connector.context}%m (%c:%L)%n
log4j.loggers=org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR
offset.storage.replication.factor=1
offset.storage.topic=connect-offsets
plugin.path=/usr/share/confluent-hub-components/confluentinc-kafka-connect-http
producer.client.id=connect-worker-producer
producer.confluent.monitoring.interceptor.bootstrap.servers=broker:9092
producer.interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor
rest.advertised.host.name=connect
rest.port=8083
status.storage.replication.factor=1
status.storage.topic=connect-status
topic.creation.enable=true
value.converter.schema.registry.url=http://schema-registry:8081
value.converter.schemas.enable=false
value.converter=io.confluent.connect.avro.AvroConverter
```

## ♻️ Re-create containers

Because the playground uses **[Docker override](/how-it-works?id=🐳-docker-override)**, not all configuration parameters are in same `docker-compose.yml` file and also `docker-compose` files in the playground depends on environment variables to be set.

For these reasons, if you want to make a change in one of the `docker-compose` files (without restarting the example from scratch), it is not simply a matter of doing `docker compose up -d` 😅!

However, when you execute an example, you get in the output the [playground container recreate](/playground%20container%20recreate) in order to easily re-create modified container(s) 🥳.

*Example:*

```bash
12:02:18 ℹ️ ✨If you modify a docker-compose file and want to re-create the container(s),
 run cli command playground container recreate
```

So you can modify one of the `docker-compose` files (in that case either [`environment/plaintext/docker-compose.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/environment/plaintext/docker-compose.yml) or [`connect/connect-http-sink/docker-compose.plaintext.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/docker-compose.plaintext.yml)), and then run [playground container recreate](/playground%20container%20recreate) command:

```bash
playground container recreate
```

Only the containers whose definition changed (for example `connect` and `http-service-no-auth` after editing [`connect/connect-http-sink/docker-compose.plaintext.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-http-sink/docker-compose.plaintext.yml)) are re-created, the others are left running.
