// Copyright 2019 Confluent Inc.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

using Confluent.Kafka;
using Confluent.Kafka.Admin;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Prometheus;


namespace CCloud
{
    class Program
    {
        static async Task<ClientConfig> LoadConfig(string configPath, string certDir)
        {
            try
            {
                var cloudConfig = (await File.ReadAllLinesAsync(configPath))
                    .Where(line => !line.StartsWith("#"))
                    .ToDictionary(
                        line => line.Substring(0, line.IndexOf('=')),
                        line => line.Substring(line.IndexOf('=') + 1));
                var clientConfig = new ClientConfig
                {
                    BootstrapServers = cloudConfig["bootstrap.servers"].Replace("\\", ""),
                    SaslMechanism = SaslMechanism.Plain,
                    SecurityProtocol = SecurityProtocol.SaslSsl,
                    SaslUsername = cloudConfig["sasl.username"],
                    SaslPassword = cloudConfig["sasl.password"],
                    // MetadataRequestTimeoutMs = 30000,
                    // TopicMetadataRefreshIntervalMs = 210000,
                    // MetadataMaxAgeMs = 210000,
                    // SocketTimeoutMs = 60000,
                    SocketKeepaliveEnable = true
                    // Debug = "broker,topic,msg"
                };

                if (certDir != null)
                {
                    clientConfig.SslCaLocation = certDir;
                }

                return clientConfig;
            }
            catch (Exception e)
            {
                Console.WriteLine($"An error occured reading the config file from '{configPath}': {e.Message}");
                System.Environment.Exit(1);
                return null; // avoid not-all-paths-return-value compiler error.
            }
        }

        static async Task CreateTopicMaybe(string name, int numPartitions, short replicationFactor, ClientConfig cloudConfig)
        {
            using (var adminClient = new AdminClientBuilder(cloudConfig).Build())
            {
                try
                {
                    await adminClient.CreateTopicsAsync(new List<TopicSpecification> {
                        new TopicSpecification { Name = name, NumPartitions = numPartitions, ReplicationFactor = replicationFactor } });
                }
                catch (CreateTopicsException e)
                {
                    if (e.Results[0].Error.Code != ErrorCode.TopicAlreadyExists)
                    {
                        Console.WriteLine($"An error occured creating topic {name}: {e.Results[0].Error.Reason}");
                    }
                    else
                    {
                        Console.WriteLine("Topic already exists");
                    }
                }
            }
        }

        static async Task Produce(string topic, ClientConfig config)
        {
            using (var producer = new ProducerBuilder<string, string>(config).SetErrorHandler((_, e) => Console.WriteLine($"Error: {e.Reason}")).Build())
            {
                int numProduced = 0;
                while(true)
                {
                    var key = "alice";
                    var val = JObject.FromObject(new { count = numProduced }).ToString(Formatting.None);

                    Console.WriteLine($"Producing record: {key} {val}");

                    producer.Produce(topic, new Message<string, string> { Key = key, Value = val },
                        (deliveryReport) =>
                        {
                            if (deliveryReport.Error.Code != ErrorCode.NoError)
                            {
                                Console.WriteLine($"Failed to deliver message: {deliveryReport.Error.Reason}");
                            }
                            else
                            {
                                Console.WriteLine($"Produced message to: {deliveryReport.TopicPartitionOffset}");
                                numProduced += 1;
                            }
                        });

                    producer.Flush(TimeSpan.FromSeconds(10));
                    Thread.Sleep(new Random().Next(1000));

                }
            }
        }


        static async Task Consume(string topic, ClientConfig config)
        {
            var consumerConfig = new ConsumerConfig(config);
            consumerConfig.GroupId = "dotnet-consumer-group-1";
            consumerConfig.AutoOffsetReset = AutoOffsetReset.Earliest;
            consumerConfig.EnableAutoCommit = false;
            consumerConfig.BrokerVersionFallback = "0.10.0.0";
            consumerConfig.ApiVersionFallbackMs = 0;
            consumerConfig.SocketKeepaliveEnable = true;
            consumerConfig.StatisticsIntervalMs = 1000;
            // consumerConfig.Debug = "consumer, cgrp, protocol";

            CancellationTokenSource cts = new CancellationTokenSource();
            Console.CancelKeyPress += (_, e) => {
                e.Cancel = true; // prevent the process from terminating.
                cts.Cancel();
            };

            using (var consumer = new ConsumerBuilder<string, string>(consumerConfig)
                // Note: All handlers are called on the main .Consume thread.
                .SetErrorHandler((_, e) => Console.WriteLine($"Error: {e.Reason}"))
                .SetStatisticsHandler((_, json) =>
                {
                    Console.WriteLine($"Statistics: {json}");
                    var statistics = JsonConvert.DeserializeObject<ConsumerStatistics>(json);

                    foreach(var mytopic in statistics.Topics)
                    {
                        foreach(var partition in mytopic.Value.Partitions)
                        {
                            var gauge = Metrics.CreateGauge("librdkafka_consumer_lag", "store consumer lags", new GaugeConfiguration{
                                LabelNames = new []{"topic", "partition", "consumerGroup"}
                            });

                            gauge.WithLabels(mytopic.Key, partition.Key, "dotnet-consumer-group-1").Set(partition.Value.ConsumerLag);
                        }
                    }
                })
                .SetPartitionsAssignedHandler((c, partitions) =>
                {
                    Console.WriteLine($"Assigned partitions: [{string.Join(", ", partitions)}]");
                    // possibly manually specify start offsets or override the partition assignment provided by
                    // the consumer group by returning a list of topic/partition/offsets to assign to, e.g.:
                    //
                    // return partitions.Select(tp => new TopicPartitionOffset(tp, externalOffsets[tp]));
                })
                .SetPartitionsRevokedHandler((c, partitions) =>
                {
                    Console.WriteLine($"Revoking assignment: [{string.Join(", ", partitions)}]");
                }).Build())
            {
                consumer.Subscribe(topic);
                var totalCount = 0;

                try
                {
                    while (true)
                    {
                        var cr = consumer.Consume(cts.Token);
                        Thread.Sleep(new Random().Next(100));

                        if (cr.IsPartitionEOF)
                        {
                            Console.WriteLine(
                                $"Reached end of topic {cr.Topic}, partition {cr.Partition}, offset {cr.Offset}.");

                            continue;
                        }
                        totalCount += JObject.Parse(cr.Value).Value<int>("count");
                        Console.WriteLine($"Consumed record with key {cr.Key} and value {cr.Value}, and updated total count to {totalCount}");
                    }
                }
                catch (OperationCanceledException)
                {
                    // Ctrl-C was pressed.
                    Console.WriteLine("Ctrl-C was pressed");
                }
                catch (ConsumeException e)
                {
                    Console.WriteLine($"Consume error: {e.Error.Reason}");
                }
                finally
                {
                    consumer.Close();

                    Console.WriteLine("closing consumer");
                }
            }
        }

        static void PrintUsage()
        {
            Console.WriteLine("usage: .. produce|consume <topic> <configPath> [<certDir>]");
            System.Environment.Exit(1);
        }

        static async Task Main(string[] args)
        {
            if (args.Length != 3 && args.Length != 4) { PrintUsage(); }

            var mode = args[0];
            var topic = args[1];
            var configPath = args[2];
            var certDir = args.Length == 4 ? args[3] : null;

            var config = await LoadConfig(configPath, certDir);

            switch (mode)
            {
                case "produce":
                    await CreateTopicMaybe(topic, 1, 3, config);
                    Task.Run(() =>  Produce(topic, config));

                    var metricServerProducer = new MetricServer(port: 7074);
                    metricServerProducer.Start();
                    Console.WriteLine("start");
                    Console.ReadLine();

                    // sleeping
                    Thread.Sleep(TimeSpan.FromSeconds(86400));
                    break;
                case "consume":
                    Console.WriteLine("Consume");
                    Task.Run(() =>  Consume(topic, config));

                    var metricServerConsumer = new MetricServer(port: 7075);
                    metricServerConsumer.Start();
                    Console.WriteLine("start");
                    Console.ReadLine();
                    // sleeping
                    Thread.Sleep(TimeSpan.FromSeconds(86400));
                    break;
                default:
                    PrintUsage();
                    break;
            }
            Console.WriteLine("exiting...");
        }
    }
}