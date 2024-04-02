# GCP BigTable Sink connector



## Objective

Quickly test [GCP BigTable Sink](https://docs.confluent.io/current/connect/kafka-connect-gcp-bigtable/index.html#quick-start) connector.

* Active Google Cloud Platform (GCP) account with authorization to create resources

## GCP BigTable Setup

### Enabling Cloud BigTable Admin API

Go to this [link](https://console.developers.google.com/apis/library/bigtableadmin.googleapis.com) and click `Enable`:

![Enabling Cloud BigTable Admin API](Screenshot5.png)

### Setup Credentials

* Create `Service Account` from IAM & Admin console:

Set `Service account name`:

![Service Account setup](Screenshot1.png)

Choose permission `Cloud BigTable`->`BigTable Administrator`

![Service Account setup](Screenshot2.png)

Create Key:

![Service Account setup](Screenshot3.png)

Download it as JSON:

![Service Account setup](Screenshot4.png)

Rename it to `keyfile.json`and place it in `./keyfile.json` or use environment variable `GCP_KEYFILE_CONTENT` with content generated with `GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`


## How to run

Simply run:

```bash
$ just use <playground run>
```
