# Fully Managed Microsoft Dynamics 365 CRM Source connector

## Objective

Quickly test the [Fully Managed Microsoft Dynamics 365 CRM Source](https://docs.confluent.io/cloud/current/connectors/cc-dynamics-365-crm-source.html) connector.

## Prerequisites

See [Confluent Cloud examples](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples).

Unless an existing environment is provided (see below), the script creates everything that is needed using your `az login` user. Your user must be able to sign in to [Power Apps](https://make.powerapps.com) and to create developer environments (tenant setting `disableDeveloperEnvironmentCreationByNonAdminUsers` set to `false`). Note there is a limit of 3 developer environments per user.

| Variable | Description |
| --- | --- |
| `DYNAMICS365_ENVIRONMENT_SKU` | Optional: Power Platform environment SKU (default `Developer`, e.g. `Trial`) |
| `DYNAMICS365_ENVIRONMENT_MACRO_REGION` | Optional: macro region, used when the tenant provisions by macro region (default `eu-efta`) |
| `DYNAMICS365_ENVIRONMENT_LOCATION` | Optional: location, used when the tenant provisions by location (default `europe`) |
| `DYNAMICS365_KEEP_RESOURCES` | Optional: set to `1` to keep the created environment and Entra app; the 4 values to re-use them are displayed |
| `AZURE_SUBSCRIPTION_NAME` | Optional: Azure subscription to select after `az login` |

Automatic provisioning requires an interactive user login, so it is not used in CI: CI uses an existing environment (see below), passed with GitHub variables `DYNAMICS365_URL`, `DYNAMICS365_TENANT_ID`, `DYNAMICS365_CLIENT_ID` and secret `DYNAMICS365_CLIENT_SECRET`. To create such a long-lived environment, run the example once with `DYNAMICS365_KEEP_RESOURCES=1`.

### Using an existing environment

If you already have a Dynamics 365 (Dataverse) environment, set the following environment variables and the script will use it instead of creating one:

```bash
export DYNAMICS365_URL="https://<org>.crm.dynamics.com"
export DYNAMICS365_TENANT_ID="<tenant-id>"
export DYNAMICS365_CLIENT_ID="<client-id>"
export DYNAMICS365_CLIENT_SECRET="<client-secret>"
```

The app `DYNAMICS365_CLIENT_ID` must be registered as an application user in the environment (Power Platform admin center -> Environments -> your environment -> Settings -> Users + permissions -> Application users -> New app user), with a security role that grants organization-level read access to the selected tables (the script also creates and deletes accounts).

## How to run

```bash
playground run -f fully-managed-microsoft-dynamics-365-crm-source.sh
```

| Script | Description |
| --- | --- |
| `fully-managed-microsoft-dynamics-365-crm-source.sh` | Captures Dataverse table `account` (initial and incremental load) |

## What the script does

1. Unless an existing environment is provided, creates, using the [Power Platform API](https://api.bap.microsoft.com):
   * a Power Platform environment with Dataverse (provisioning takes a few minutes)
   * an Entra app/service principal with a client secret
   * a Dataverse application user for this app, with the `System Administrator` security role
2. Checks with the Dataverse Web API whether change tracking is enabled on table `account` (if not, the connector uses the `versionnumber` column as watermark and deletes are not captured).
3. Creates account `playground-account-...-1` with the Dataverse Web API.
4. Creates the `MicrosoftDynamics365CRMSource` fully managed connector for entity `accounts` with topic prefix `crm`, and verifies that the account is in topic `crmaccounts` (initial load).
5. Creates a second account `playground-account-...-2` and verifies that it is also in `crmaccounts` (incremental load).
6. Asks before deleting the connector; on exit, deletes the environment and the Entra app (or only the created accounts when using an existing environment).
