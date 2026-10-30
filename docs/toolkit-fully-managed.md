# ☁️ Fully managed connectors

Reproduce what customers do with fully managed connectors: a service account with the least ACLs, or Terraform. Part of the [🧰 Reproduction toolkit](/reusables.md).

> [!TIP]
> The [🍪 deep dive on fully managed connectors](/deep-dive-fully-managed.md) covers the rest: choosing the cluster, the connector commands on Confluent Cloud, costs and cleanup.

## 👤 Fully managed connectors with a service account

By default the fully managed connector examples (`ccloud/fm-*`) use `"kafka.auth.mode": "KAFKA_API_KEY"`, with an API key that can do anything on the cluster. Customers often run them with a [service account](https://docs.confluent.io/cloud/current/connectors/service-account.html) and the least ACLs instead, and that is where a missing ACL or a missing Assigner role shows up.

The `--ccloud-service-account` option of [playground run](/playground%20run) (also a toggle in the run menu) runs any fully managed or custom connector example that way, without changing the example:

```bash
playground run -f ccloud/fm-datagen-source/fully-managed-datagen-source.sh --ccloud-service-account
```

For each connector, [playground connector create-or-update](/playground%20connector%20create-or-update):

* creates a service account `pg-<user>-conn-<connector>-<n>`
* creates the ACLs listed in the documentation, derived from the connector config: `DESCRIBE` on the cluster, the topics of a sink and its `connect-lcc-` consumer group, the dead letter queue, the success and error topics (HTTP, Lambda, Azure Functions…), the output topics or topic prefix of a source, and the internal topics of the JDBC, Debezium (legacy and v2), Oracle CDC and XStream connectors, plus the exactly-once ones when it is enabled
* grants the Assigner role on the service account to the owner of `CONFLUENT_CLOUD_API_KEY` (the principal creating the connector must hold it)
* replaces `kafka.api.key` / `kafka.api.secret` with `"kafka.auth.mode": "SERVICE_ACCOUNT"` and `"kafka.service.account.id"`

Each `confluent` command is logged, ready to be copied, for example:

```
💻 confluent kafka acl create --service-account sa-o2k1pno --operations create,write --allow --topic datagen_pageviews --environment env-519yzz --cluster lkc-ng7qn3
```

The service account and its ACLs are deleted with the connector (`playground connector delete`, the cleanup at the end of the run, [playground cleanup-cloud-resources](/playground%20cleanup-cloud-resources)).

| Option (run menu entry) | What it does |
| --- | --- |
| `--ccloud-service-account-acls docs` (🚦 Service account ACLs) | the ACLs of the documentation (default) |
| `--ccloud-service-account-acls full` | every operation on every topic, group and transactional id: for a connector whose internal topics are not known, or to check that the ACLs are the problem |
| `--ccloud-service-account-acls none` | no ACL at all, add them one by one |
| `--ccloud-service-account-id sa-xxxxx` (🪪 Existing service account) | use an existing service account (for example one set up like the customer's), as is: no ACL created nor deleted |
| `PG_CCLOUD_SERVICE_ACCOUNT_ACL_EXCLUDE="<regex>"` | do not create the ACLs matching the regex, matched on `<OPERATION> <ResourceType>:<name> [prefix]` (e.g. `"READ Group:"`) |

In the run menu, tick *👤 Connector service account* in the options:

![playground run menu: Connector service account toggle](./images/run_menu_ccloud_service_account.png)

Two entries then appear in the confluent cloud section, to pick the ACLs and an existing service account:

![playground run menu: service account entries](./images/run_menu_ccloud_service_account_entries.png)

![playground run menu: service account ACLs](./images/run_menu_ccloud_service_account_acls.png)

### 🚦 Reproduce an authorization error

Once the connector runs, [playground rbac acl](/playground%20rbac%20acl) changes the ACLs of its service account: on a Confluent Cloud run it manages the ACLs of the Confluent Cloud cluster, and `--connector` uses the service account of the connector as principal. Delete an ACL, or add a `--deny` one (deleting it restores the setup), then restart the connector:

```bash
playground rbac acl list   --connector DatagenSource_$USER
playground rbac acl delete --connector DatagenSource_$USER --operation WRITE --resource Topic:datagen_pageviews
playground rbac acl create --connector DatagenSource_$USER --operation DESCRIBE --resource Cluster:kafka-cluster --deny
playground connector restart --connector DatagenSource_$USER
```

The connector fails like the customer's:

```
DatagenSource_vsaboulin        ❌ FAILED   0:💪 USER_ACTIONABLE_ERROR   connector: Your kafka API key does not have the permissions required to access the configured topic
kafka.topic: Missing write permission on topic(s) "datagen_pageviews".
```

[playground connector diagnose](/playground%20connector%20diagnose) compares the ACLs of the service account with the ones of the documentation, and gives the commands to fix them:

```
🚦 service account sa-o2k1pno: ACLs of the documentation (https://docs.confluent.io/cloud/current/connectors/service-account.html)
❌ missing: WRITE Topic:datagen_pageviews
⛔ denied: DESCRIBE Cluster:kafka-cluster
   🔧 to create the missing ACLs:
   playground rbac acl create --connector DatagenSource_vsaboulin --operation WRITE --resource Topic:datagen_pageviews
   🔧 to delete the DENY ACLs:
   playground rbac acl delete --connector DatagenSource_vsaboulin --deny --operation DESCRIBE --resource Cluster:kafka-cluster
```

> An ACL change takes up to a minute to be applied in Confluent Cloud: if the connector still fails right after a fix, restart it again. Resources are `Topic:<name>`, `Group:<name>`, `TransactionalId:<name>` (add `--prefix` for a prefix) and `Cluster:kafka-cluster`.

In a reproduction model, set the variables after the `source ${DIR}/../../scripts/utils.sh` line, so that the model always runs with the customer's setup:

```bash
export PG_CCLOUD_SERVICE_ACCOUNT=true
# the customer did not grant the schema history consumer group
export PG_CCLOUD_SERVICE_ACCOUNT_ACL_EXCLUDE="READ Group:.*-schemahistory"
```

🎬 Bite size session: [A fully managed connector with a service account loses an ACL](/sessions?id=👤-a-fully-managed-connector-with-a-service-account-loses-an-acl)

## 🏗️ Fully managed connectors with Terraform

Customers often manage their fully managed connectors with Terraform. Add `--terraform` to [playground connector create-or-update](/playground%20connector%20create-or-update) to deploy the connector of any fully managed or custom connector example that way. The JSON config stays as is: it is converted to HCL for the [confluentinc/confluent](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_connector) provider, then `terraform init`, `plan` and `apply` run.

```bash
playground connector create-or-update -c DatagenSource_$USER --terraform --wait << EOF
{
  "connector.class": "DatagenSource",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "kafka.topic": "datagen_pageviews",
  "output.data.format": "JSON",
  "quickstart": "PAGEVIEWS",
  "tasks.max": "1"
}
EOF
```

* The keys that look like secrets (`*.secret`, `*.password`, `*.key`, `sasl.jaas.config`...) go to `config_sensitive`. Their values are masked in the output, and Terraform shows `(sensitive value)`.
* The folder of the connector (`.terraform-playground/<connector>-*`, with `connector.tf` and the state) is kept. Running the command again updates the connector in place (the plan shows what changes, for example `~ "max.interval" = "10000" -> "1000"`). A connector created without `--terraform` is imported into the state the first time.
* [playground connector delete](/playground%20connector%20delete) runs `terraform destroy` for a connector deployed with Terraform.
* `connector.tf` is plain HCL: a starting point to reproduce a customer's Terraform code.

> [!NOTE]
> It needs [terraform](https://developer.hashicorp.com/terraform/install) (`brew install hashicorp/tap/terraform`) and a Cloud API key (`CONFLUENT_CLOUD_API_KEY`, `CONFLUENT_CLOUD_API_SECRET`). `--level`, `--offsets` and `--initial-state` are not supported with `--terraform`.

🎬 Bite size session: [Deploy a fully managed connector with Terraform](/sessions?id=🏗️-deploy-a-fully-managed-connector-with-terraform)
