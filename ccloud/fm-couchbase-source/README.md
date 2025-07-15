# Fully Managed Couchbase Source connector

## Objective

Quickly test [Fully Managed Couchbase Source](https://docs.confluent.io/cloud/current/connectors/cc-couchbase-db-source/cc-couchbase-db-source.html) connector.

## Prerequisites

See [here](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%8c%a4%ef%b8%8f-confluent-cloud-examples)

You also need to [create a free Couchbase Capella account](https://cloud.couchbase.com/sign-up). And a cluster.

Go to Settings->Allowed IP Addresses and add your confluent cloud cluster egress ip addresses:

![egress](screenshot1.png)

Then go to Security->Cluster Access and create cluster access (allow access to bucket `travel-sample`):

![egress](screenshot2.png)

That will give you environment variable `COUCHBASE_USERNAME` and `COUCHBASE_PASSWORD`

Then go to `Connect` menu and copy the *Public Connection String*:

![connect](screenshot3.png)

That will give you environment variable `COUCHBASE_HOSTNAME`  (remove `couchbases://` to get hostname)

Then go to `Data Tools` menu and import sample data called *travel-sample*:

![travel sample](screenshot4.png)


N.B: After a period of inactivity (72 hours), your [free tier cluster will automatically turn off](https://docs.couchbase.com/cloud/get-started/create-account.html#:~:text=Only%201%20free%20tier%20operational%20cluster%20is%20available%20per%20organization%20and%20it%20automatically%20turns%20off%20after%2072%20hours%20of%20inactivity)

## How to run

Simply run:

```
$ just use <playground run> command and search for couchbase.sh in this folder
```
