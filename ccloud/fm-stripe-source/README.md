# Fully Managed Stripe Source connector

## Objective

Quickly test the [Fully Managed Stripe Source](https://docs.confluent.io/cloud/current/connectors/cc-stripe-source/cc-stripe-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

| Variable | Description |
| --- | --- |
| `STRIPE_API_KEY` | Stripe **sandbox** (test mode) secret key `sk_test_...`, or a restricted key `rk_test_...` with write access to customers and read access to events (required, can also be passed as first argument). Live mode keys are refused: the script creates and deletes a customer |

```bash
export STRIPE_API_KEY=sk_test_xxx
```

or store it once with [`playground secrets`](https://kafka-docker-playground.io/#/deep-dive-secrets), `playground run` then loads it for you:

```bash
playground secrets set STRIPE_API_KEY
```

### Set up a free Stripe sandbox

A Stripe account is free, and its sandbox (test mode) needs neither a credit card nor business details: it only holds test data and never moves money.

1. Sign up at [dashboard.stripe.com/register](https://dashboard.stripe.com/register) (email, name, password) and verify your email address.
2. Skip the "activate payments" / business details steps: they are only needed to accept real payments.
3. Check that you are in a sandbox (or test mode): the dashboard shows a sandbox / test mode banner. Create one from the account menu (`Sandboxes` > `Create`) if needed.
4. Go to [Developers > API keys](https://dashboard.stripe.com/test/apikeys) and copy the **Secret key** (`sk_test_...`).

Optional, a restricted key instead of the secret key: on the same page, click `Create restricted key` and give it:

| Resource | Permission | Why |
| --- | --- | --- |
| `Customers` | `Write` | the script creates and deletes a customer, the connector reads them |
| `Events` | `Read` | the connector reads the changes of the resources from the events (`stripe-customers_events` topic) |

To read other resources (`charges`, `invoices`, `subscriptions`…), add them to `stripe.resources` (7 maximum per connector) and give the key `Read` access to them.

> [!NOTE]
> The connector only reads the data of the mode of the key: a sandbox key reads sandbox data. Stripe keeps events for 30 days, so `stripe.initial.start.timestamp` older than that does not replay older changes.

You can see the customer created by the script in the dashboard, in `Customers` (it is deleted at the end of the run).

## How to run

```bash
playground run -f fully-managed-stripe-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-stripe-source.sh` | Creates a Stripe customer and reads the `customers` resource |

## What the script does

1. Bootstraps the Confluent Cloud environment and recreates topics `stripe-customers` and `stripe-customers_events`.
2. Creates a customer `playground-<user>-...@example.com` with the Stripe API.
3. Creates the `StripeSource` fully managed connector (resource `customers`, `stripe.initial.start.timestamp` one minute before the customer creation, topic prefix `stripe-`, Avro output).
4. Verifies that the customer is in topic `stripe-customers` (`playground topic consume --grep <customer id>`).
5. Deletes the Stripe customer on exit.
