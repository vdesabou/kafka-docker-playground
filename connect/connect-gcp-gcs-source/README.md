# GCS Source connector



## Objective

Quickly test [GCS Source](https://docs.confluent.io/current/connect/kafka-connect-gcs/source/index.html#quick-start) connector.

* Active Google Cloud Platform (GCP) account with authorization to create resources

## Prepare a Bucket

[Instructions](https://docs.confluent.io/current/connect/kafka-connect-gcs/index.html#prepare-a-bucket)

* Create `Service Account` from IAM & Admin console:

Set `Service account name`:

![Service Account setup](Screenshot1.png)

Choose permission `Storage Admin` (probably not required to have all of them):

![Service Account setup](Screenshot2.png)

Create Key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json`and place it in `./keyfile.json` or use environment variable `GCP_KEYFILE_CONTENT` with content generated with `GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')


## How to run

For [Backup and Restore GCS Source](https://docs.confluent.io/kafka-connect-gcs-source/current/backup-and-restore/overview.html):

```bash
$ just use <playground run> command and search for gcs-source-backup-and-restore<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> .sh in this folder
```

For [Generalized GCS Source](https://docs.confluent.io/kafka-connect-gcs-source/current/generalized/overview.html) (it requires version 2.1.0 at minimum):

```bash
$ just use <playground run> command and search for gcs-source-generalized<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path> .sh in this folder
```

Note: you can also export these values as environment variable
