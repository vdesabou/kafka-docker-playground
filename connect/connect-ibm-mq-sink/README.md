# IBM MQ Sink connector



## Objective

Quickly test [IBM MQ Sink](https://docs.confluent.io/current/connect/kafka-connect-ibmmq/sink/index.html#quick-start) connector.

Using IBM MQ Docker [image](https://hub.docker.com/r/ibmcom/mq/)

N.B: if you're a Confluent employee, please check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900).

Download [IBM-MQ-Install-Java-All.jar](https://ibm.biz/mq92javaclient) (for example `9.2.0.3-IBM-MQ-Install-Java-All.jar`) and place it in `./IBM-MQ-Install-Java-All.jar`

![IBM download page](Screenshot1.png)

## How to run

Without SSL:

```
$ playground run -f ibm-mq-sink<tab>
```

with SSL encryption:

```
$ playground run -f ibm-mq-sink-ssl<tab>
```

with SSL encryption + Mutual TLS authentication:

```
$ playground run -f ibm-mq-sink-mtls<tab>
```
