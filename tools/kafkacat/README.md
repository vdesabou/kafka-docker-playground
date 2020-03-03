# Kafkacat

## Objective

Quickly test [edenhill/kafkacat](https://github.com/edenhill/kafkacat)

## How to run

Simply run:

```
$ ./start.sh
```

## Details of what the script is doing

Metadata Listing Mode

```bash
$ docker exec kafkacat kafkacat -b broker:9092 -L
```

Metadata Listing Mode (JSON)

```bash
$ docker exec kafkacat kafkacat -b broker:9092 -L -J | jq .
```

Producer mode with file

```bash
$ cat >> orders.txt << EOF
1:{"order_id":1,"order_ts":1534772501276,"total_amount":10.50,"customer_name":"Bob Smith"}
2:{"order_id":2,"order_ts":1534772605276,"total_amount":3.32,"customer_name":"Sarah Black"}
3:{"order_id":3,"order_ts":1534772742276,"total_amount":21.00,"customer_name":"Emma Turner"}
EOF
```

```
$ docker exec -it kafkacat kafkacat -P -b broker:9092 -t orders -K: -T  -l /data/orders.txt
```

Consumer Mode

```bash
$ docker exec -it kafkacat kafkacat -C -b broker:9092 -t orders -K: -f '\nKey (%K bytes): %k\t\nValue (%S bytes): %s\n\Partition: %p\tOffset: %o\n--\n' -c 3
```

Producer mode input

```bash
$ docker exec -i kafkacat kafkacat -P -b broker:9092 -t orders -K: -T << EOF
4:{"order_id":4,"order_ts":1534772801276,"total_amount":11.50,"customer_name":"Alina Smith"}
5:{"order_id":5,"order_ts":1534772905276,"total_amount":13.32,"customer_name":"Alex Black"}
6:{"order_id":6,"order_ts":1534773042276,"total_amount":31.00,"customer_name":"Emma Watson"}
EOF
```

Query Mode

```bash
$ docker exec -it kafkacat kafkacat -Q -b broker:9092 -t orders:0:-1
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
