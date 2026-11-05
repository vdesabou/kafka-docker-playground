# Fully Managed Webhook Source connector

## Objective

Quickly test the [Fully Managed Webhook Source](https://docs.confluent.io/cloud/current/connectors/cc-webhook-source.html) connector: an HTTPS endpoint, exposed by Confluent Cloud, that external systems call with a JSON `POST` to produce records to a Kafka topic.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

* The Webhook Source connector is a **Limited Availability** feature: it must be enabled for your organization by Confluent Support or your account team. Without it, connector creation fails with `403 access denied to connect`.
* It requires a **Dedicated cluster on AWS** with public networking, in a region of the LA program. To use an existing one, set `CLUSTER_NAME`, `ENVIRONMENT`, `CLUSTER_CLOUD`, `CLUSTER_REGION` and `CLUSTER_CREDS` (see the Confluent Cloud examples link above). The script exits with code `111` (skipped) when the cluster is not a Dedicated cluster on AWS, before creating anything.
* `CONFLUENT_CLOUD_API_KEY` must be owned by a principal that can create service accounts, ACLs and Global API keys (OrgAdmin).

## How to run

```bash
playground run -f fully-managed-webhook-source.sh
```

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topic `webhook-topic`.
2. The connector only supports `kafka.auth.mode` `SERVICE_ACCOUNT`, so it creates:
   * a service account `pg-<user>-webhook-...`, with the `Assigner` role binding for the owner of `CONFLUENT_CLOUD_API_KEY`,
   * its ACLs: `DESCRIBE` on the cluster, `CREATE` and `WRITE` on `webhook-topic` and on the prefix `error-lcc-` (the default error topic `error-<lcc-id>`),
   * a **Global** API key of that service account (`confluent api-key create --resource global --service-account <sa>`), set in `webhook.api.key` / `webhook.api.secret`: callers use it for HTTP Basic authentication on the endpoint.
3. Creates the `WebhookSource` fully managed connector (`output.data.format` `JSON_SR`, `schema.enforcement.mode` `EVOLVE`, `tasks.max` `2`, the minimum).
4. Gets the webhook endpoint URL from `confluent connect cluster describe <lcc-id>`.
5. Sends one record, then a batch (JSON array) of two records, the last one with a new field `carrier`:

   ```bash
   curl -X POST "$webhook_url" -u "$webhook_api_key:$webhook_api_secret" \
       -H "Content-Type: application/json" \
       -d '{"id": 1, "event": "order_created", "amount": 10.5}'
   ```

   A successful call returns:

   ```json
   {
     "status": "success",
     "status_code": 200,
     "message": "Records successfully committed to Kafka.",
     "timestamp": 1789461533555,
     "records_processed": 1
   }
   ```

6. Verifies that the 3 records are in `webhook-topic`.
7. Asks before deleting the connector; on exit, deletes the connector, the API key, the ACLs and the service account.
