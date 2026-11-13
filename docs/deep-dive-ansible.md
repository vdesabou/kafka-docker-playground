# 🍪 Deep dive: cp-ansible (`--environment ansible`)

Confluent Platform deployed by the [cp-ansible](https://github.com/confluentinc/cp-ansible) playbooks, with the
customer's inventory, the customer's cp-ansible and ansible-core versions, then the usual `playground` commands and
connector examples on the result. This is how you reproduce "the playbook fails", "this variable renders a wrong
`server.properties`", "the upgrade from 7.9 breaks", or a connector issue on a cluster that cp-ansible deployed. Takes
about 15 minutes to read, and about 12 minutes to run the lab.

| You want | Command |
| --- | --- |
| a cluster deployed by cp-ansible | `playground start-environment --environment ansible` |
| the same with SASL/PLAIN and SSL on every listener, https REST APIs | `--environment ansible-sasl-ssl` |
| the customer's `hosts.yml` | `--ansible-inventory /path/to/hosts.yml` |
| a connector example on it | `playground run -f <connect/ example> --environment ansible [--ansible-inventory …]` |
| other versions | `--tag` (CP), `ANSIBLE_CP_VERSION` (collection), `ANSIBLE_CORE_VERSION`, `ANSIBLE_INSTALLATION_METHOD=package` |
| more hosts | `--enable-multiple-brokers`, `--enable-multiple-controllers`, `--enable-multiple-connect-workers`, `--enable-ksqldb`, `--enable-rest-proxy`, `--enable-control-center` |
| change a variable and deploy again | edit `environment/ansible/inventory/hosts.yml`, then `docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all [--limit connect] [--tags …] [-vvv]` |
| what cp-ansible rendered | `playground container get-properties -c broker`, `docker exec broker systemctl status confluent-server` |
| the playbook output | `/tmp/playground-ansible-playbook.log` |

---

## 1. Mental model (the 3 things to remember)

**1. The hosts are containers that run systemd, nothing else.** `controller`, `broker`, `schema-registry`, `connect`
start empty (Ubuntu 24.04 and a JDK): the image cp-ansible's own molecule tests use. An `ansible-controller` container
runs `confluent.platform.all` against them with the `community.docker.docker` connection (`docker exec`, no SSH). What
runs in the hosts is exactly what the playbook installed: systemd units (`confluent-server`, `confluent-kcontroller`,
`confluent-kafka-connect`…), properties files rendered from the inventory, `/var/log/kafka`.

```text
 playground start-environment --environment ansible [--ansible-inventory customer-hosts.yml]
        ├─ 1. inventory          environment/ansible/inventory/hosts.yml (generated, or the customer's adapted)
        ├─ 2. docker compose up  the hosts + ansible-controller (ansible-core + confluent.platform at the versions of the case)
        ├─ 3. ansible-playbook   confluent.platform.all  →  /tmp/playground-ansible-playbook.log
        └─ 4. hand-over          Kafka tools on the PATH, client.properties per host, CA of the REST APIs
```

**2. The inventory is the thing you change, not the containers.** Every setting goes through cp-ansible variables:
`kafka_broker_custom_properties`, `kafka_connect_service_environment_overrides`, `sasl_protocol`… Edit
`environment/ansible/inventory/hosts.yml` and run the playbook again (it is idempotent: a second run on `connect` takes
about a minute). The commands that recreate containers (`container recreate`, `set-environment-variables`,
`update-version`…) are refused: a recreated host loses what the playbook installed. The hosts stay up when the playbook
fails: fix the variable, run it again with `-vvv`.

**3. The `playground` commands read what cp-ansible rendered.** Logs come from journald (`docker logs` only shows
systemd), the security of the clients from the configuration of each component, the JVM is the MainPID of the service
(PID 1 is systemd), `broker stop` is `systemctl stop`. Nothing is hard-coded for a given inventory, which is what makes
the customer's inventory work too.

---

## 2. What each command does on cp-ansible hosts

| Command | Here |
| --- | --- |
| `container logs` (`--errors`, `--grep`, `--since`, `--wait-for-log`), `display-error-all`, `analyze logs --from-containers` | `journalctl -u <confluent-* units>` of the host |
| `broker stop` / `start` / `rolling-restart` | `systemctl stop` / `start` / `restart` of the broker service; the host stays up. `--kill` is `systemctl kill -s KILL`, and the units have `Restart=no`: a killed broker stays down |
| `container restart` | restarts the host, systemd starts the services again (enabled) |
| `broker metrics`, `connector metrics`, `debug flight-recorder` | JMX: the generated inventory sets `JMX_PORT` with the ports of the other environments (broker 10000, connect 10002…) |
| `debug thread-dump`, `heap-dump` | the MainPID of the service (`jmap -histo 1` would attach to systemd) |
| `topic *`, `schema *`, `consumer-group *`, `connector *` | the Kafka tools of the archive, wrapped into `/usr/local/bin`, with `/etc/kafka/client.properties` of the host |
| `ksqldb sql` | the `ksql` cli on the `ksqldb-server` host |
| `container recreate`, `update`, `set-environment-variables`, `change-jdk`, `get-docker-compose`, `update-version`, `tcp-proxy start` | refused, with the inventory variable to use instead |

**Connector examples.** The example's compose override is translated into inventory variables, with the naming of the
cp images: `CONNECT_PLUGIN_PATH` → `plugin.path` in `kafka_connect_custom_properties`, `KAFKA_OPTS` →
`kafka_connect_custom_java_args`, other variables → `kafka_connect_service_environment_overrides`, `*_LOG4J_*` ignored
with a warning. The image, command and entrypoint of the hosts are removed, their volumes kept; the other services of
the example (databases, http servers) start as they are.

---

## 3. Security: `ansible-sasl-ssl`, or the customer's

`--environment ansible-sasl-ssl` adds `sasl_protocol: plain` and `ssl_enabled: true` to the inventory: SASL_SSL on every
listener, https REST APIs, certificates generated by cp-ansible (`/var/ssl/private/`). After the playbook:

| What | From |
| --- | --- |
| `/etc/kafka/client.properties` of each host | the broker's `client.properties`, else the client settings of the component (connect worker, `kafkastore.*` of Schema Registry, ksqlDB, `client.*` of REST Proxy) |
| `environment/ansible/inventory/ca.pem` | the certificates of the truststore of `connect` |
| https or http | the `listeners=` of each REST API |

The certificates are issued for the host names, not `localhost`: REST calls go to `https://connect:8083` with
`curl --cacert environment/ansible/inventory/ca.pem --resolve connect:8083:127.0.0.1`. `connector create-or-update`
adds the worker's security to the connector's own clients (`confluent.topic.*`, `redo.log.consumer.*`, Debezium history,
`reporter.*`) and switches the converters to the https schema registry.

---

## 4. The customer's inventory

`--ansible-inventory hosts.yml` keeps the customer's variables and changes only what cannot work in containers. Every
change is printed with `✏️`, everything that cannot be reproduced with `⚠️`:

| In the customer inventory | Here |
| --- | --- |
| the hosts of each group | `broker`, `broker2`, `broker3`… (extra hosts left out with a warning; a co-located host becomes two hosts) |
| `ansible_host`, `ansible_user`, `ansible_ssh_*`, `ansible_become*`… | removed |
| the customer's host names in variables (FQDN and short name, `ansible_host` addresses) | the playground host names |
| `!vault` values | `playground-vault-value` |
| `ssl_custom_certs`, `ssl_provided_keystore_and_truststore` | `false`: certificates generated by cp-ansible (check the customer's with `playground tools cert inspect`) |
| package mirrors, archive URLs | removed: public repositories or the archive cache |
| `confluent_package_version`, `installation_method` | used, the cp-ansible collection follows the version (a 7.9 inventory with `zookeeper` gets ZooKeeper hosts and cp-ansible 7.9) |

Only YAML inventories: `ansible-inventory -i hosts.ini --list -y > hosts.yml` converts an INI one.

---

## 5. Gotchas

- **Not reproducible here**: SSH, sudo rules, SELinux, firewalld, real DNS, OS packages, the customer's certificates,
  Kerberos KDC, external LDAP. The hosts are root containers reached with `docker exec`.
- **Memory**: cp-ansible's default heaps are `-Xmx6g` (broker, Control Center), `-Xmx4g` (controller). Lower them with
  `<component>_service_environment_overrides.KAFKA_HEAP_OPTS` if the engine runs out of memory.
- **Connect logs every line twice** with cp-ansible 8.4.0 (its log4j2 configuration), in the file and in journald.
- **Worker defaults**: the generated inventory sets `key.converter=StringConverter` and the `file` config provider, as in
  the other environments (cp-ansible's default key converter is Avro). Not with a customer inventory: theirs is what
  you reproduce.
- **First start**: the CP archive (~1.4 GB) is downloaded once to `~/.playground-ansible-cache`, the controller image
  is built per cp-ansible / ansible-core version. Then about 4 minutes for 4 hosts, 9 for 11.

---

## 6. Hands-on lab (≈12 min)

The lab is the script [`other/deep-dive-labs/ansible.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/deep-dive-labs/ansible.sh):
CI runs it every night and checks the outputs below.

It needs about 12 GB of memory for Docker. Locally (Docker Desktop, arm64), each deployment took about 4 minutes and the
whole lab 11 min 31 s; the CP archive is downloaded once to `~/.playground-ansible-cache` before that.

**Step 1: the FileStream example on hosts deployed by cp-ansible**

```bash
playground start-environment --environment ansible --docker-compose-override-file "$PWD/other/deep-dive-labs/docker-compose.plaintext.yml"
# 🖥️ hosts: controller broker schema-registry connect
# 🧩 translating the example's docker compose override docker-compose.plaintext.yml into inventory variables
#    connect: plugin.path=/opt/confluent/confluent-8.4.1/share/filestream-connectors (kafka_connect_custom_properties)   <- CONNECT_PLUGIN_PATH of the override
# ▶️ Running the playbook (a few minutes): docker exec ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all
# PLAY RECAP *********************************************************************
# broker                     : ok=127  changed=27   unreachable=0    failed=0    skipped=180  rescued=0    ignored=0
# connect                    : ok=125  changed=24   unreachable=0    failed=0    skipped=238  rescued=0    ignored=0
# controller                 : ok=133  changed=27   unreachable=0    failed=0    skipped=161  rescued=0    ignored=0
# schema-registry            : ok=92   changed=22   unreachable=0    failed=0    skipped=155  rescued=0    ignored=0
# 🚦 containers have started! (took 1 seconds)
playground state get run.environment
# ansible
playground topic produce -t filestream --nb-messages 5 --value '{"id": %g, "name": "name-%g"}'
# (then the filestream-sink connector, as in the other labs)
playground container exec -c connect --command "cat /tmp/output.json"
# {name=name-1, id=1}
playground container get-properties -c connect
# key.converter=org.apache.kafka.connect.storage.StringConverter                       <- set by the generated inventory
# plugin.path=/opt/confluent/confluent-8.4.1/share/filestream-connectors
```

**Step 2: the playground commands on cp-ansible hosts**

```bash
playground container logs -c connect --wait-for-log "Finished starting connectors and tasks" --max-wait 30
# The log is there !                                                                   <- journald of confluent-kafka-connect
playground container logs -c connect --errors
# ✅ no ERROR/FATAL record found in 6849 lines
playground broker stop --broker 1
# 🛑 Stopping broker 1 (systemctl stop confluent-server.service on host broker): controlled shutdown, its leaders move to the other replicas first
playground broker start --broker 1
# ▶️ Starting broker 1 (systemctl start confluent-server.service on host broker)
# ✅ cluster is healthy, broker 1 started in 17s
playground debug thread-dump -c connect
# 👻 thread dump is available at /tmp/thread-dump-connect-2026-11-13-19-55-50.log      <- kill -3 on the MainPID of the service
playground container recreate
# ❌ container recreate is not supported in ansible mode: a recreated host loses what the playbook installed, run the playbook again instead
#     docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all
playground container set-environment-variables -c connect --env "KAFKA_OPTS: -verbose:class"
# this command is not available with ansible: the containers are hosts where cp-ansible installed Confluent Platform, recreating them deletes the installation. Change the inventory …
```

**Step 3: change the inventory, run the playbook again**

```bash
yq -i '.all.children.kafka_connect.vars.kafka_connect_custom_properties["consumer.max.poll.records"] = 100' environment/ansible/inventory/hosts.yml
docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all --limit connect
# connect                    : ok=122  changed=7    unreachable=0    failed=0    skipped=242  rescued=0    ignored=0   <- about a minute
playground container get-properties -c connect
# consumer.max.poll.records=100
playground connector status -c filestream-sink
# filestream-sink                ✅ RUNNING  0:🟢 RUNNING                 -
```

**Step 4: the inventory of the customer, with SASL_SSL**

[`ansible-customer-hosts.yml`](https://github.com/vdesabou/kafka-docker-playground/blob/master/other/deep-dive-labs/ansible-customer-hosts.yml)
looks like the `hosts.yml` attached to a case: SSH connection, FQDN host names, a vault value, customer certificates, a
package mirror, `sasl_protocol: plain` and `ssl_enabled: true`.

```bash
playground start-environment --environment ansible --ansible-inventory "$PWD/other/deep-dive-labs/ansible-customer-hosts.yml"
# 📋 reading the customer inventory …/other/deep-dive-labs/ansible-customer-hosts.yml
# ✏️ kc1.prod.example.com -> controller: connection variables removed (ansible_host)
# ✏️ kb1.prod.example.com -> broker: connection variables removed (ansible_host)
# ✏️ sr1.prod.example.com -> schema-registry
# ✏️ kco1.prod.example.com -> connect
# ✏️ all: connection variables removed (ansible_become, ansible_connection, ansible_user)
# ✏️ all: confluent_common_repository_baseurl removed (package repository or file of the customer, the public ones are used)
# ✏️ host names in the variables: kb1.prod.example.com -> broker
# ⚠️ all: ssl_custom_certs set to false, the certificates are generated by cp-ansible (the customer's are files on their controller: use playground tools cert inspect on them)
# ⚠️ 1 vault value(s) replaced by 'playground-vault-value' (no vault password): all.vars.confluent_common_repository_baseurl
# 🖥️ hosts: controller broker schema-registry connect
# broker                     : ok=157  changed=42   unreachable=0    failed=0    skipped=188  rescued=0    ignored=0
# …
# 🔐 security of the cluster: SASL_SSL, CA of the REST APIs in …/environment/ansible/inventory/ca.pem
playground container get-properties -c connect
# producer.bootstrap.servers=broker:9092                                               <- kb1.prod.example.com:9092 in the customer inventory
playground container get-properties -c broker
# num.partitions=6                                                                     <- kafka_broker_custom_properties of the customer
playground topic produce -t customer-orders --nb-messages 3 << 'EOF'
{"type": "record", "name": "order", "fields": [{"name": "id", "type": "int"}]}
EOF
playground topic consume -t customer-orders --min-expected-messages 3 --timeout 60
# CreateTime:2026-11-13 20:02:27.475|Partition:0|Offset:0|Headers:NO_HEADERS|Key:null|Value:{"id":1}|ValueSchemaId:1   <- SASL_SSL + https schema registry
playground connector create-or-update -c lab-rewrites --dry-run << 'EOF'
{ "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector", "confluent.topic.bootstrap.servers": "broker:9092",
  "value.converter": "io.confluent.connect.avro.AvroConverter", "value.converter.schema.registry.url": "http://schema-registry:8081", … }
EOF
#   "confluent.topic.security.protocol": "SASL_SSL",                                  <- the security of the connect worker
#   "value.converter.schema.registry.url": "https://schema-registry:8081"
# 🌵 request: PUT https://connect:8083/connectors/lab-rewrites/config
```

---

## 7. Recipes for support repros

| Case | Recipe |
| --- | --- |
| "the cp-ansible playbook fails on a task" | `playground run -f <connect/ example> --environment ansible --ansible-inventory <their hosts.yml>` with `ANSIBLE_CP_VERSION` / `ANSIBLE_CORE_VERSION` of the case: the error of each host is printed (`❌ <host>: <message>`); then `docker exec -it ansible-controller ansible-playbook -i /inventory/hosts.yml confluent.platform.all -vvv --tags <tag>` |
| "this cp-ansible variable renders a wrong properties file" | `playground container get-properties -c <host>` after deploying their inventory, change the variable in `environment/ansible/inventory/hosts.yml`, `ansible-playbook … --limit <host>`, compare |
| "the cp-ansible upgrade breaks" | `playground run -f <example> --environment ansible --ansible-inventory <hosts.yml>` with the old `confluent_package_version`, then the new one (and `confluent_archive_file_source` to the new archive in `/cache`) and the playbook again |
| "the connector fails on our cluster deployed by cp-ansible" | `playground run -f <example> --environment ansible --ansible-inventory <their hosts.yml>` |
| "is it cp-ansible or Kafka?" | `playground run -f <example>` on `--environment plaintext` (cp images), then `--environment ansible` |
