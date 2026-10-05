# Fully Managed Microsoft Dynamics 365 CRM Source connector



## Objective

Quickly test [Fully Managed Microsoft Dynamics 365 CRM Source](https://docs.confluent.io/cloud/current/connectors/cc-dynamics-365-crm-source.html) connector.

The script:

* unless an existing environment is provided (see below), creates everything that is needed, using your `az login` user:
  * a Power Platform `Developer` environment with Dataverse in macro region `eu-efta` or location `europe`, depending on the tenant provisioning mode (environment variables `DYNAMICS365_ENVIRONMENT_SKU`, `DYNAMICS365_ENVIRONMENT_MACRO_REGION` and `DYNAMICS365_ENVIRONMENT_LOCATION` to override, for example `DYNAMICS365_ENVIRONMENT_SKU=Trial`), using the [Power Platform API](https://api.bap.microsoft.com). Provisioning takes a few minutes
  * an Entra app/service principal with a client secret
  * a Dataverse application user for this app, with `System Administrator` security role
* checks with the Dataverse Web API whether change tracking is enabled on table `account` (if not, the connector uses the `versionnumber` column as watermark and deletes are not captured)
* creates an account `playground-account-...-1` using the Dataverse Web API
* creates the connector for entity `accounts` with topic prefix `crm`, and verifies that the account is in topic `crmaccounts` (initial load)
* creates a second account `playground-account-...-2` and verifies that it is also in topic `crmaccounts` (incremental load)
* deletes the environment and the Entra app at the end of the run (or only the created accounts when using an existing environment)

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

Your user must be able to sign in to [Power Apps](https://make.powerapps.com) and to create developer environments (tenant setting `disableDeveloperEnvironmentCreationByNonAdminUsers` set to `false`). Note there is a limit of 3 developer environments per user.

Automatic provisioning requires an interactive user login, so it is not used in CI: CI uses an existing environment (see below), passed with GitHub variables `DYNAMICS365_URL`, `DYNAMICS365_TENANT_ID`, `DYNAMICS365_CLIENT_ID` and secret `DYNAMICS365_CLIENT_SECRET`.

To create such a long-lived environment, run the example once with `DYNAMICS365_KEEP_RESOURCES=1`: the environment and the Entra app are not deleted at the end, and the 4 values to use are displayed.

### Using an existing environment

If you already have a Dynamics 365 (Dataverse) environment, set the following environment variables and the script will use it instead of creating one:

```bash
export DYNAMICS365_URL="https://<org>.crm.dynamics.com"
export DYNAMICS365_TENANT_ID="<tenant-id>"
export DYNAMICS365_CLIENT_ID="<client-id>"
export DYNAMICS365_CLIENT_SECRET="<client-secret>"
```

The app `DYNAMICS365_CLIENT_ID` must be registered as an application user in the environment (Power Platform admin center → Environments → your environment → Settings → Users + permissions → Application users → New app user), with a security role that grants organization-level read access to the selected tables (the script also creates and deletes accounts).

## How to run

```
$ just use <playground run> command and search for fully-managed-microsoft-dynamics-365-crm-source.sh in this folder
```
