# 🍪 Deep dive: containers (`playground container`)

The commands that work on the containers of the running example without having to remember their names, their users
or their compose files: run a command inside, copy files in and out, read the properties a component really loaded,
restart, crash, freeze or rebuild a container, change its environment variables or its JDK. The same commands work on
Kubernetes pods with the `cfk` environment (`pod` is an alias of `container`). Takes about 15 minutes to read and run.

> [!TIP]
> The video session [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose)
> shows one thing a restart undoes. This page goes further: what each command keeps and loses, its gotchas, a hands-on
> lab and recipes for support repros.

| You want | Command |
| --- | --- |
| what runs, and what is not healthy | `playground status` |
| run one command inside (scripts) | `playground container exec -c connect --command "<cmd>"` (`--root`, `--shell sh`) |
| an interactive shell | `playground container ssh -c connect` |
| copy a file in or out | `playground container cp --source ./f --destination connect:/tmp/f` (and the reverse) |
| the properties file a component loaded | `playground container get-properties -c connect` |
| restart a component, keeping everything | `playground container restart -c connect` |
| simulate a crash / a hung process | `playground container kill -c connect` / `pause` … `resume` |
| apply a changed compose definition | `playground container recreate` |
| add environment variables (JVM options, log4j loggers…) | `playground container set-environment-variables -c connect --env "KAFKA_OPTS: -verbose:class"` |
| edit the compose definition of one service and apply it | `playground container update -c connect` |
| another JDK in the container | `playground container change-jdk -c connect --version 17` |
| the IP addresses on the docker network | `playground container get-ip-addresses` |
| every ERROR of every container | `playground container display-error-all` |

`-c` defaults to `connect` and can be repeated: `-c broker -c connect`.

---

## 1. Mental model (the 3 things to remember)

1. **Restart keeps the container, recreate replaces it, and only recreate applies a definition change.**

   | | `restart` | `kill` + `recreate` | `recreate` after a definition change, `set-environment-variables`, `update` |
   | --- | --- | --- | --- |
   | Docker does | `docker restart` (stop + start) | `docker kill`, then `docker compose up -d` starts the same container again | `docker compose up -d` builds a **new** container from the definition |
   | Files written in the container (`/tmp`, a jar you copied, a package you installed, a JDK from `change-jdk`) | kept | kept (same container id) | **lost** |
   | Logs (`container logs`) | kept | kept | **lost** (a new container has a new log) |
   | Network rules (`debug block-traffic`, `degrade-traffic`) | **lost** (new network namespace) | **lost** | **lost** |
   | Compose definition (image, env, volumes) | unchanged | unchanged | **the new one** |
   | Kafka data, connectors, offsets | kept (stored in topics / volumes) | kept | kept, unless the broker's volume is removed |

   `recreate` replays the docker compose command that started the example (`run.docker_command` in `playground.ini`)
   with `up -d`, **without `--force-recreate`**: Docker Compose only rebuilds the containers whose definition changed
   (an edited compose override, another image tag). A container whose definition didn't change is left as it is, so
   `recreate` alone is **not** a way to start from a clean container (`Container connect Running`: nothing done).

2. **Everything runs as the component's user, inside its container, through `docker exec`.** `exec` is
   `docker exec -i <container> bash -c "<command>"` as the image's user (`appuser` in Confluent images): installing a
   package or reading a root-owned file needs `--root` (`docker exec --privileged --user root`). The command is one
   string run by a shell **inside** the container, so pipes, redirections and `&&` work there, and `$VAR` in double
   quotes is expanded by **your** shell first: use single quotes for container variables. On CFK, the same command
   becomes `kubectl -n confluent exec`, `connect` resolves to the pod `connect-0`, and `--root` patches the CR to run as
   root, then restores it (two pod restarts).

3. **The playground state decides what "the containers" are.** `recreate`, `update` and `set-environment-variables`
   replay `run.docker_command`, and keep the CP version of the running `broker` and `connect` images
   (`--ignore-current-versions` to take the defaults again). `playground status` lists only containers that belong to a
   compose project. `kill-all`, on the other hand, is not scoped to the playground: it removes **every container on
   your machine** and prunes volumes (it runs before each `playground run`, unless
   `playground config container-kill-all-before-run false`).

---

## 2. Looking inside: `status`, `exec`, `ssh`, `get-properties`, `cp`

```bash
playground status                                                     # example, containers, connectors, topics
playground container exec -c connect --command "ls /usr/share/filestream-connectors"
playground container exec -c connect --command "id"                   # uid=1000(appuser)
playground container exec -c connect --root --command "microdnf -y install procps-ng"
playground container exec -c broker -c connect --command "df -h /tmp" # one after the other
playground container ssh -c connect                                    # interactive, -s sh if bash is missing

playground container get-properties -c connect                         # the properties file the JVM was started with
playground container cp --source ./my.jar --destination connect:/tmp/my.jar
playground container cp --source connect:/tmp/output.json --destination /tmp/output.json
```

`playground status` prints:

```text
🐳 Container engine: docker
🚀 Running example
connect-filestream-sink/filestream-sink.sh
🐳 Containers
NAMES                STATUS                      IMAGE
connect              Exited (137) 1 second ago   confluentinc/cp-server-connect:8.3.2
schema-registry      Up 11 minutes               confluentinc/cp-schema-registry:8.3.2
broker               Up 11 minutes               confluentinc/cp-server:8.3.2
…
💀 some containers are not running or not healthy, check them with 'playground container logs --container <container> --errors':
connect (Exited (137) 1 second ago)                                      <- only when one is down
```

followed by the connector versions, status and config, and the topic list.

Gotchas:

- **`exec` is for scripts, `ssh` for you**: `exec` runs one command and returns (stdin is passed with `-i`, no TTY),
  `ssh` opens an interactive shell (`docker exec -it`).
- **The exit code of the command is returned** (`exec … --command "test -f /tmp/x"` fails the script when the file is
  missing), with several `-c` too: a failure on any of them gives exit 1.
- `--shell` accepts `bash` (default), `sh`, `ksh`, `zsh`: use `--shell sh` on images without bash.
- **`get-properties` reads the file from the `java` command line** (the last argument ending in `properties` of
  `ps -ef`), drops blank lines and `None` values, and prints it **as is: passwords included** (`sasl.jaas.config`,
  `ssl.keystore.password`). Don't paste it in a ticket unredacted.
- **`cp` decides by the colon**: a path with `:` is `container:path`, anything else is local. A local file name with a
  colon in it is taken for a container path. Directories are copied recursively (`docker cp`); on CFK, `kubectl cp`
  needs `tar` in the pod, otherwise a single file is streamed with `cat` (no directories).
- **Files you copy in keep your host uid** (`-rw-r--r-- 1 501 root … /tmp/lab-marker.txt` with `docker cp`): readable
  by the component, not writable. `exec --root --command "chown appuser /tmp/my.jar"` if it must write them.

---

## 3. Acting on them: `restart`, `kill`, `pause`, `recreate`

```bash
playground container restart -c connect           # docker restart, then waits for the Connect REST API
playground container kill -c connect              # SIGKILL: a crash, no clean shutdown
playground container recreate                     # docker compose up -d: starts what is stopped, rebuilds what changed
playground container pause -c schema-registry     # frozen: connections stay open, nothing answers
playground container resume -c schema-registry
playground container kill-all                     # every container on the machine, and volumes
```

Gotchas:

- **`restart` of `connect` waits for its REST API** before returning; other containers return as soon as Docker has
  restarted them. Connectors and tasks restart on their own: their config and offsets live in Kafka topics.
- **`kill` is a crash**: no shutdown hook, no final offset commit. A sink restarts from its last commit (duplicates),
  a source from its last flushed offset. The container stays `Exited (137)`: `playground status` flags it, and
  `recreate` starts the same container again (files and log kept).
- **`pause` is a hang, not a crash**: TCP connections stay up, so clients wait for their own timeouts (session timeout,
  `request.timeout.ms`) instead of getting `connection refused`. Closest thing to a long GC pause or a stuck database.
  Not on CFK.
- `recreate` is not supported on CFK (delete the pod with `restart` instead: the StatefulSet recreates it from the CR).
- On CFK, `restart` and `kill` delete the pod (`kill` with `--grace-period=0 --force`): the pod is always a new one,
  so files written in it are lost.

---

## 4. Changing them: `set-environment-variables`, `update`, `change-jdk`

```bash
# JVM options, log4j loggers, any env var of the image: the container is recreated with them
playground container set-environment-variables -c connect --env "KAFKA_OPTS: -verbose:class"
playground container set-environment-variables -c connect --env "CONNECT_LOG4J_LOGGERS: org.reflections=ERROR"
playground container set-environment-variables -c connect --restore-original-values

# edit the full compose definition of one service (image, env, volumes, ports), saved = applied
playground container update -c connect

# Azul Zulu JDK 8, 11, 17, 21, 22 or 25 (UBI images only), then a restart
playground container change-jdk -c connect --version 17
```

How they work:

| Command | Under the hood | Undone by |
| --- | --- | --- |
| `set-environment-variables` | writes a temporary compose override with your variables **plus a random `DUMMY` value** (so the container is always rebuilt), then replays `run.docker_command` with `-f <override>` | `--restore-original-values`, or any later `recreate` (it replays the command **without** the override, so the container is rebuilt without your variables) |
| `update` | `docker compose … config <service>`, opens the YAML in your editor, then `up -d` with that file as an extra `-f` | a later `recreate` |
| `change-jdk` | as root: `yum install zulu<version>-jdk`, `update-alternatives --set java`, then `container restart` and `java -version` | a recreate (the JDK is installed in the container, not in the image) |

Gotchas:

- `--env` values use the compose syntax `"NAME: value"`, not `NAME=value`.
- **`set-environment-variables` and `update` recreate the container**: everything in the "lost" column of the mental
  model goes, including network rules and files you copied in. Apply them first, then copy files and degrade traffic.
- `KAFKA_OPTS` replaces the image's value: keep what the image needs (for example a `-javaagent` of the example).
- **`change-jdk` downloads and installs packages**: it needs internet access from the container and takes a few
  minutes. It survives `restart`, not `recreate`. On CFK, it builds a new Connect image instead and patches the CR
  (Connect pods only, needs the image to be loadable by the cluster: minikube or k3d).
- `update` opens an editor and waits: interactive only.

---

## 5. Hands-on lab (≈10 min)

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh
```

**Step 1: what runs, and who you are inside**

```bash
playground status
# 🐳 Containers: connect, schema-registry, broker, controller (+ control-center, prometheus, alertmanager)   Up …
playground container exec -c connect --command "id"
# 🪄 Executing command in container connect with bash
# uid=1000(appuser) gid=1000(appuser) groups=1000(appuser)
playground container exec -c connect --root --command "id"
# 🪄👑 Executing command as root in container connect with bash
# uid=0(root) gid=0(root) groups=0(root)
playground container exec -c connect --command "ls /usr/share/filestream-connectors"
# connect_file_file-project.jar
playground container exec -c connect --command 'echo $HOSTNAME'     # single quotes: expanded in the container
# connect
playground container exec -c connect --command "test -f /nope"; echo "exit=$?"
# exit=1
```

**Step 2: what Connect really loaded**

```bash
playground container get-properties -c connect
# 📝 Displaying properties file for connect
# bootstrap.servers=broker:9092
# …
# plugin.path=/usr/share/filestream-connectors
# value.converter=io.confluent.connect.avro.AvroConverter       <- the worker default, overridden per connector
```

**Step 3: files in and out**

```bash
playground container cp --source connect:/tmp/output.json --destination /tmp/lab-output.json
wc -l /tmp/lab-output.json
# 5 /tmp/lab-output.json                         <- the 5 records of the example
echo "hello" > /tmp/lab-marker.txt
playground container cp --source /tmp/lab-marker.txt --destination connect:/tmp/lab-marker.txt
playground container exec -c connect --command "ls -l /tmp/lab-marker.txt; cat /tmp/lab-marker.txt"
# -rw-r--r-- 1 501 root 6 Oct 23 11:15 /tmp/lab-marker.txt        <- your host uid
# hello
```

**Step 4: restart keeps, recreate keeps too, a real recreation loses**

```bash
playground container restart -c connect
playground container exec -c connect --command "cat /tmp/lab-marker.txt"
# hello                                         <- restart keeps the container
playground container recreate
playground container exec -c connect --command "cat /tmp/lab-marker.txt"
#  Container connect Running                    <- nothing changed: connect not rebuilt
# hello
playground container set-environment-variables -c connect --env "LAB_VAR: 1"
#  Container connect Recreate … Container connect Started
playground container exec -c connect --command 'echo "LAB_VAR=$LAB_VAR"; cat /tmp/lab-marker.txt'
# LAB_VAR=1
# cat: /tmp/lab-marker.txt: No such file or directory     <- a new container
playground container recreate
playground container exec -c connect --command 'echo "LAB_VAR=$LAB_VAR"'
# LAB_VAR=                                       <- recreate replays the command without your variables
playground connector wait --connector filestream-sink --max-wait 180
# ✅ 🌎onprem connector filestream-sink is RUNNING (1 task(s)) after 6 seconds   <- back on its own
```

**Step 5: a crash, seen by `status`**

```bash
playground container kill -c connect
playground status
# connect              Exited (137) 1 second ago   confluentinc/cp-server-connect:8.3.2
# 💀 some containers are not running or not healthy, check them with … connect (Exited (137) 1 second ago)
playground container recreate
playground connector status
```

**Optional (slow, downloads a JDK): `change-jdk`**

```bash
playground container exec -c connect --command "java -version"
playground container change-jdk -c connect --version 17
# installs Azul Zulu 17 as root, restarts connect, then prints java -version (not run for this page)
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "it only fails with Java 17 / 21" | `container change-jdk -c connect --version 17` (or 21), then re-run the scenario |
| "the worker has these JVM options / loggers" | `container set-environment-variables -c connect --env "KAFKA_OPTS: …"`, before creating the connector |
| "the connector needs a driver / a jar we added" | `container cp --source ./driver.jar --destination connect:/usr/share/…/lib/` then `container restart -c connect` (restart, not recreate: recreate may drop it) |
| "Connect crashed during the night" | `container kill -c connect` while data flows, `recreate`, then `connector show-lag` / `topic consume` to see duplicates |
| "schema registry hangs, it doesn't go down" | `container pause -c schema-registry`, watch the connector, `container resume` |
| "which config did the broker really use?" | `container get-properties -c broker` (redact passwords before sharing) |
| "the customer's worker has this setting in docker-compose" | `container update -c connect`, or a compose override in the repro model (persistent) |
| "get the file the sink wrote" | `container cp --source connect:/tmp/out.json --destination ./out.json` |
| "what is down?" | `playground status` (💀 lines), then `container display-error-all` |

In a repro model, prefer a compose override file (`docker-compose.plaintext.repro-….yml`, generated by
`playground repro bootstrap`) to `set-environment-variables` or `update`: the override is part of the repro and
survives every `recreate` and re-run, the commands above don't.

---

## 7. Cheat sheet

```bash
playground status
playground container exec|ssh [-c <c>]... [--command "<cmd>"] [--root] [--shell bash|sh|ksh|zsh]
playground container cp --source <local|c:path> --destination <local|c:path>
playground container get-properties|get-ip-addresses|display-error-all [-c <c>]
playground container restart|kill|pause|resume [-c <c>]...
playground container recreate [--ignore-current-versions]
playground container set-environment-variables -c <c> --env "NAME: value"... | --restore-original-values
playground container update -c <c>
playground container change-jdk -c <c> --version 8|11|17|21|22|25
playground container kill-all          # every container on the machine + volumes
```

- `restart` keeps the container (files, logs, JDK), loses network rules. A real recreation loses everything in the
  container. `recreate` only rebuilds containers whose definition changed.
- `exec` = one command as the image user, `--root` for root, single quotes for container variables.
- `set-environment-variables` / `update` are undone by the next `recreate`: use a compose override in repro models.
- `get-properties` prints passwords. `kill-all` is not scoped to the playground.
- Sources: [`commands/container/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/container),
  [`commands/status.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/status.sh),
  `resolve_container_name_for_environment` / `open_file_with_editor` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🍪 Deep dives: [network faults](/deep-dive-network-traffic.md) (what a restart undoes),
  [`container logs`](/deep-dive-container-logs.md) (what a recreation loses),
  [`connector create-or-update`](/deep-dive-connector-create-or-update.md)
- 📖 [See properties file](/how-to-use?id=📝-see-properties-file) and [Re-create containers](/how-to-use?id=♻️-re-create-containers) in How to Use
- 🧠 CLI reference: [playground container](/playground%20container), [playground container exec](/playground%20container%20exec),
  [playground container recreate](/playground%20container%20recreate), [playground status](/playground%20status)
