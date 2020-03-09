# .NET client (producer)

## Objective

Quickly test basic producer [.NET example](https://github.com/confluentinc/confluent-kafka-dotnet/tree/master/examples/Producer)


## How to run


Simply run:

```
$ ./start.sh  <2.2 or 3.1> (Core .NET version, default is 2.1)
```

## Details of what the script is doing

Starting producer

```bash
$ docker exec -i client-dotnet bash -c "dotnet DotNet.dll broker:9092 dotnet-basic-producer"
```

Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])