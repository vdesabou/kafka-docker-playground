# cp-ansible

## Description

Confluent Platform installed by [cp-ansible](https://github.com/confluentinc/cp-ansible) (the `confluent.platform`
collection), for the cases where **the playbook is the problem**: a playbook run that fails, a variable that renders a
wrong properties file, an upgrade that breaks. Then the `playground` commands and the connector examples work on the
cluster cp-ansible deployed, as on the other environments.

It uses the same recipe as cp-ansible's own molecule tests: the hosts are **containers running systemd**, and Ansible
reaches them with the `community.docker.docker` connection (`docker exec`), not SSH.

- `controller`, `broker`, `schema-registry`, `connect`: empty Ubuntu 24.04 hosts (systemd as PID 1, a JDK, no Kafka)
- `ansible-controller`: python, ansible-core and the `confluent.platform` collection at the versions of the case
- `start.sh` generates the inventory `inventory/hosts.yml`, runs `confluent.platform.all` from `ansible-controller`, then
  hands the cluster over to the `playground` commands

This is a deployment with no security:

* 1 KRaft controller
* 1 broker
* 1 connect
* 1 schema-registry

The `--enable-*` flags of `playground run` add hosts (same names and ports as in the other environments):

| Flag | Hosts | cp-ansible group |
| --- | --- | --- |
| `--enable-multiple-brokers` | `broker2`, `broker3` | `kafka_broker` |
| `--enable-multiple-controllers` | `controller2`, `controller3` | `kafka_controller` |
| `--enable-multiple-connect-workers` | `connect2` (`localhost:8283`), `connect3` (`localhost:8383`) | `kafka_connect` |
| `--enable-ksqldb` | `ksqldb-server` (`localhost:8088`) | `ksql` |
| `--enable-rest-proxy` | `rest-proxy` (`localhost:8082`) | `kafka_rest` |
| `--enable-control-center` | `control-center` (`http://localhost:9021`, Control Center Next Gen with its Prometheus and Alertmanager) | `control_center_next_gen` |

`--enable-flink`, `--enable-jmx-grafana`, `--enable-kcat`, `--enable-conduktor` and `--enable-sql-datagen` are ignored,
with a warning. 11 hosts (all the flags above) take about 9 minutes to deploy.

## How to run

Start it on its own:

```bash
playground start-environment --environment ansible
```

or run a connector example on it:

```bash
playground run -f connect/connect-jdbc-mysql-source/mysql.sh --environment ansible
```

Versions:

| What | How to choose it | Default |
| --- | --- | --- |
| Confluent Platform (`confluent_package_version`) | `--tag` | the playground default tag |
| cp-ansible (`confluent.platform` collection, from Ansible Galaxy) | `export ANSIBLE_CP_VERSION=8.1.6` | latest patch of the same major.minor as the CP version |
| ansible-core | `export ANSIBLE_CORE_VERSION=2.16.*` | `2.17.*` |
| `installation_method` | `export ANSIBLE_INSTALLATION_METHOD=package` | `archive` |
| extra `ansible-playbook` arguments | `export ANSIBLE_PLAYBOOK_EXTRA_ARGS="-vvv"` | none |

With `installation_method: archive`, the Confluent Platform archive (~1.4 GB) is downloaded once to
`~/.playground-ansible-cache` (`ANSIBLE_ARCHIVE_CACHE_DIR`), and every host unpacks it from there.

The playbook output goes to `/tmp/playground-ansible-playbook.log`. A first start takes a few minutes (images, archive
download), then about 4 minutes.

### What the generated inventory sets

On top of the cp-ansible defaults, so that the `playground` commands and the examples behave as on the other
environments:

| Variable | Value | Why |
| --- | --- | --- |
| `<component>_service_environment_overrides` | `JMX_PORT` / `KAFKA_JMX_PORT` (or `SCHEMA_REGISTRY_JMX_PORT`): controller 10005, broker 10000, schema-registry 10001, connect 10002 | JMX metrics (`broker metrics`, `connector metrics`…). cp-ansible enables JMX without a port |
| `kafka_connect_custom_properties` | `key.converter=org.apache.kafka.connect.storage.StringConverter`, `config.providers=file` | the worker settings the examples rely on (cp-ansible's default key converter is Avro) |
| `custom_java_path` | `/usr/lib/jvm/default-java` | the JDK of the hosts, so the playbook doesn't install one |

### Connector examples (`playground run --environment ansible`)

The example's docker compose override is translated, because the hosts are not cp images:

| In the override | Becomes |
| --- | --- |
| `CONNECT_*` on `connect` (`KAFKA_*` on `broker` and `controller`, `SCHEMA_REGISTRY_*` on `schema-registry`) | `<component>_custom_properties`, with the naming of the cp images: `CONNECT_PLUGIN_PATH` → `plugin.path`, `___` → `-`, `__` → `_` |
| `KAFKA_OPTS`, `SCHEMA_REGISTRY_OPTS` | `<component>_custom_java_args` (appended to the java arguments cp-ansible builds) |
| `KAFKA_HEAP_OPTS`, `KAFKA_DEBUG`, other variables (`AWS_ACCESS_KEY_ID`…) | `<component>_service_environment_overrides` |
| `*_LOG4J_*` | ignored, with a warning: use `<component>_custom_log4j2`, or `playground debug log-level` / `connector log-level` |
| `image`, `command`, `entrypoint`… of the hosts | removed (they would replace the host); their `volumes` and `ports` are kept |
| the other services (databases, http servers…) | started as they are |

Plugin paths of the cp images (`/usr/share/filestream-connectors`, `/usr/share/java/…`) point to the archive
(`/opt/confluent/confluent-<version>/share/…`). The connector plugins installed by `playground run` are in
`confluent-hub/`, mounted at `/usr/share/confluent-hub-components` in `connect`, as in the other environments.

## Working with it

Run the playbook again, after editing `environment/ansible/inventory/hosts.yml` (the hosts keep running when the
playbook fails):

```bash
docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all
docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all --tags kafka_broker -vvv
docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all --limit connect
```

Example, a connector plugin: cp-ansible's default `plugin.path` doesn't include the connectors of the archive (creating
a `FileStreamSink` fails with `Failed to find any class that implements Connector and which name matches
FileStreamSink`). Add the folder in the inventory, or plugins from Confluent Hub with
`kafka_connect_confluent_hub_plugins`, then run the playbook again on connect only (about 1 minute):

```yaml
    kafka_connect:
      hosts:
        connect:
      vars:
        kafka_connect_custom_properties:
          plugin.path: /opt/confluent/confluent-8.4.1/share/java/connect_plugins,/usr/share/java/connect_plugins,/opt/confluent/confluent-8.4.1/share/filestream-connectors
```

Upgrade: set a new `confluent_package_version` in the inventory (and the matching archive in
`confluent_archive_file_source`), then run the playbook again.

What cp-ansible generated (archive install: under `/opt/confluent/etc`, package install: under `/etc`):

```bash
playground container get-properties -c broker
docker exec broker systemctl status confluent-server
docker exec broker cat /opt/confluent/etc/kafka/server.properties
```

### The playground commands on cp-ansible hosts

| Command | On this environment |
| --- | --- |
| `container logs` (`--errors`, `--grep`, `--since`, `--wait-for-log`), `container display-error-all`, `analyze logs --from-containers` | read journald of the `confluent-*` services of the host (`docker logs` only shows systemd) |
| `broker stop` / `start` / `rolling-restart` | `systemctl stop` / `start` / `restart` of the broker service, the host stays up (`--kill`: `systemctl kill -s KILL`, and the cp-ansible units have `Restart=no`) |
| `container restart` | restarts the host, systemd starts the services again (they are enabled) |
| `broker metrics`, `connector metrics`, `debug thread-dump` / `heap-dump` / `flight-recorder` | JMX on the ports of the generated inventory, JDK of the hosts |
| `ksqldb sql` | runs the `ksql` cli of the archive on the `ksqldb-server` host (there is no `ksqldb-cli` container) |
| `topic *`, `schema *`, `connector *`, `consumer-group *`, `broker health` / `describe` / `config` | as on the other environments: the Kafka tools of the archive are wrapped into `/usr/local/bin`, and admin tools use the `client.properties` cp-ansible writes on the broker |
| `container recreate`, `update`, `set-environment-variables`, `change-jdk`, `get-docker-compose`, `update-version`, `tcp-proxy start` | refused: they recreate containers, which deletes what the playbook installed. Change the inventory and run the playbook again |

## Limitations

- With `--enable-multiple-connect-workers`, a check of an example that reads a file in `connect` fails when the task
  runs on `connect2` or `connect3` (`cat: /tmp/output.json: No such file or directory` in the filestream examples): the
  same happens on the other environments.
- When the playbook fails, the error of each host is printed (`❌ <host>: <message>`), and the hosts keep running: fix
  the inventory and run the playbook again.

- Every log line of Connect appears twice in its log (`/var/log/kafka/connect.log` and journald): that is how
  cp-ansible 8.4.0 configures log4j2 for Connect, not a playground issue.
- The default heaps of cp-ansible are large for a laptop (`-Xmx6g` for the broker, `-Xmx4g` for the controller): lower
  them with `<component>_service_environment_overrides` (`KAFKA_HEAP_OPTS`) if the engine runs out of memory.
- Failures tied to real hosts (SSH, sudo, SELinux, firewalld, DNS, OS packages) can't be reproduced: the hosts are root
  containers reached with `docker exec`.
