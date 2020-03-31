# Using Mirror Maker 2

![asciinema](asciinema.gif)

## Objective

[Run Mirror Maker 2](https://cwiki.apache.org/confluence/display/KAFKA/KIP-382%3A+MirrorMaker+2.0)

## How to run

With no security in place (PLAINTEXT):

```
$ ./mirrormaker2-plaintext.sh
```

## Details of what the script is doing

Sending sales in Europe cluster

```bash
$ seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --broker-list localhost:9092 --topic sales_EUROPE
```

Sending sales in US cluster

```bash
$ seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i broker-us kafka-console-producer --broker-list localhost:9092 --topic sales_US
```

Consolidating all sales (logs are in /tmp/mirrormaker.log):

```bash
# run in detach mode -d
$ docker exec -d connect-us bash -c '/usr/bin/connect-mirror-maker /etc/kafka/connect-mirror-maker.properties > /tmp/mirrormaker.log 2>&1'
```

Verify we have received the data in topic `US.sales_US` in EUROPE

```bash
$ docker container exec broker-europe kafka-console-consumer --bootstrap-server localhost:9092 --topic "US.sales_US" --from-beginning --max-messages 10
```

```
us_sale_1 7848
us_sale_2 7848
us_sale_3 7848
us_sale_4 7848
us_sale_5 7848
us_sale_6 7848
us_sale_7 7848
us_sale_8 7848
us_sale_9 7848
us_sale_10 7848
Processed a total of 10 messages
```

Verify we have received the data in topic `EUROPE.sales_EUROPE` topics in the US

```bash
$ docker container exec broker-us kafka-console-consumer --bootstrap-server localhost:9092 --topic "EUROPE.sales_EUROPE" --from-beginning --max-messages 10
```

```
european_sale_1 5122
european_sale_2 5122
european_sale_3 5122
european_sale_4 5122
european_sale_5 5122
european_sale_6 5122
european_sale_7 5122
european_sale_8 5122
european_sale_9 5122
european_sale_10 5122
Processed a total of 10 messages
```

Copying mirrormaker logs to `/tmp/mirrormaker.log`

```bash
$ docker cp connect-us:/tmp/mirrormaker.log /tmp/mirrormaker.log
```