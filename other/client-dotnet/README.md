# .NET client (producer)

## Objective

Quickly test basic producer [.NET example](https://github.com/confluentinc/confluent-kafka-dotnet/tree/master/examples/Producer)


## How to run


Simply run:

```
$ just use <playground run> command and search for start<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>  .sh in this folder
```

## Details of what the script is doing

Starting producer

```bash
$ docker exec -i client-dotnet bash -c "dotnet DotNet.dll broker:9092 dotnet-basic-producer"
```

Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])