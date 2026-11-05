// Confluent Go client (confluent-kafka-go v2, on librdkafka) with the Avro serializer for Schema Registry.
//
// usage: client produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]
//
// The config file has one librdkafka property per line (bootstrap.servers, security.protocol, sasl.*...), plus
// the schema.registry.url and schema.registry.basic.auth.user.info properties of the Schema Registry client.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/confluentinc/confluent-kafka-go/v2/schemaregistry"
	"github.com/confluentinc/confluent-kafka-go/v2/schemaregistry/serde"
	"github.com/confluentinc/confluent-kafka-go/v2/schemaregistry/serde/avrov2"
)

// Payment is the value of the Avro records: avrov2 derives the schema from the struct and its avro tags.
type Payment struct {
	ID     string  `avro:"id"`
	Amount float64 `avro:"amount"`
}

const consumeTimeout = 60 * time.Second

func usage() {
	fmt.Fprintln(os.Stderr, "usage: client produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]")
	os.Exit(1)
}

func fail(format string, a ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", a...)
	os.Exit(1)
}

// loadConfig splits the config file into the librdkafka properties and the schema.registry.* properties.
func loadConfig(path string) (kafka.ConfigMap, map[string]string) {
	file, err := os.Open(path)
	if err != nil {
		fail("cannot read config file %s: %v", path, err)
	}
	defer file.Close()
	kafkaConfig := kafka.ConfigMap{}
	srConfig := map[string]string{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, found := strings.Cut(line, "=")
		if !found {
			continue
		}
		key, value = strings.TrimSpace(key), strings.TrimSpace(value)
		if strings.HasPrefix(key, "schema.registry.") {
			srConfig[key] = value
		} else {
			kafkaConfig[key] = value
		}
	}
	if err := scanner.Err(); err != nil {
		fail("cannot read config file %s: %v", path, err)
	}
	return kafkaConfig, srConfig
}

func schemaRegistryClient(srConfig map[string]string) schemaregistry.Client {
	url := srConfig["schema.registry.url"]
	if url == "" {
		fail("schema.registry.url is missing in the config file")
	}
	config := schemaregistry.NewConfig(url)
	if userInfo := srConfig["schema.registry.basic.auth.user.info"]; userInfo != "" {
		user, password, _ := strings.Cut(userInfo, ":")
		config = schemaregistry.NewConfigWithBasicAuthentication(url, user, password)
	}
	client, err := schemaregistry.NewClient(config)
	if err != nil {
		fail("cannot create the Schema Registry client: %v", err)
	}
	return client
}

func produce(topic string, kafkaConfig kafka.ConfigMap, nbMessages int, value func(i int) []byte) {
	kafkaConfig["acks"] = "all"
	producer, err := kafka.NewProducer(&kafkaConfig)
	if err != nil {
		fail("cannot create the producer: %v", err)
	}
	defer producer.Close()

	deliveries := make(chan kafka.Event, nbMessages)
	for i := 0; i < nbMessages; i++ {
		err := producer.Produce(&kafka.Message{
			TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
			Key:            []byte(fmt.Sprintf("key-%d", i)),
			Value:          value(i),
		}, deliveries)
		if err != nil {
			fail("cannot produce record %d: %v", i, err)
		}
	}

	nbProduced := 0
	for i := 0; i < nbMessages; i++ {
		m := (<-deliveries).(*kafka.Message)
		if m.TopicPartition.Error != nil {
			fail("delivery failed: %v", m.TopicPartition.Error)
		}
		fmt.Printf("Produced record to %s [%d] at offset %v\n", *m.TopicPartition.Topic, m.TopicPartition.Partition, m.TopicPartition.Offset)
		nbProduced++
	}
	fmt.Printf("%d records were produced to topic %s\n", nbProduced, topic)
}

func consume(topic string, kafkaConfig kafka.ConfigMap, nbMessages int, display func(m *kafka.Message) string) {
	group := topic + "-group"
	kafkaConfig["group.id"] = group
	kafkaConfig["auto.offset.reset"] = "earliest"
	kafkaConfig["enable.auto.commit"] = false
	consumer, err := kafka.NewConsumer(&kafkaConfig)
	if err != nil {
		fail("cannot create the consumer: %v", err)
	}
	if err := consumer.SubscribeTopics([]string{topic}, nil); err != nil {
		fail("cannot subscribe to %s: %v", topic, err)
	}

	deadline := time.Now().Add(consumeTimeout)
	nbConsumed := 0
	for nbConsumed < nbMessages {
		if time.Now().After(deadline) {
			consumer.Close()
			fail("Timeout: consumed %d records out of %d after %v", nbConsumed, nbMessages, consumeTimeout)
		}
		m, err := consumer.ReadMessage(time.Second)
		if err != nil {
			if kafkaErr, ok := err.(kafka.Error); ok && kafkaErr.IsTimeout() {
				continue
			}
			consumer.Close()
			fail("consume error: %v", err)
		}
		fmt.Printf("Consumed record from %s [%d] at offset %v: key=%s value=%s\n", *m.TopicPartition.Topic, m.TopicPartition.Partition, m.TopicPartition.Offset, string(m.Key), display(m))
		if _, err := consumer.CommitMessage(m); err != nil {
			consumer.Close()
			fail("commit failed: %v", err)
		}
		nbConsumed++
	}
	// leave the group now: without Close(), the member stays in the group until its session times out
	consumer.Close()
	fmt.Printf("%d records were consumed from topic %s by group %s\n", nbConsumed, topic, group)
}

func main() {
	if len(os.Args) < 4 || len(os.Args) > 5 {
		usage()
	}
	mode, topic := os.Args[1], os.Args[2]
	nbMessages := 10
	if len(os.Args) == 5 {
		n, err := strconv.Atoi(os.Args[4])
		if err != nil || n <= 0 {
			usage()
		}
		nbMessages = n
	}
	kafkaConfig, srConfig := loadConfig(os.Args[3])

	_, libVersion := kafka.LibraryVersion()
	fmt.Printf("confluent-kafka-go with librdkafka %s\n", libVersion)

	switch mode {
	case "produce":
		produce(topic, kafkaConfig, nbMessages, func(i int) []byte {
			return []byte(fmt.Sprintf(`{"id":"payment-%d","amount":%d.5}`, i, i))
		})
	case "consume":
		consume(topic, kafkaConfig, nbMessages, func(m *kafka.Message) string { return string(m.Value) })
	case "produce-avro":
		serializer, err := avrov2.NewSerializer(schemaRegistryClient(srConfig), serde.ValueSerde, avrov2.NewSerializerConfig())
		if err != nil {
			fail("cannot create the Avro serializer: %v", err)
		}
		produce(topic, kafkaConfig, nbMessages, func(i int) []byte {
			payload, err := serializer.Serialize(topic, &Payment{ID: fmt.Sprintf("payment-%d", i), Amount: float64(i) + 0.5})
			if err != nil {
				fail("cannot serialize record %d: %v", i, err)
			}
			return payload
		})
	case "consume-avro":
		deserializer, err := avrov2.NewDeserializer(schemaRegistryClient(srConfig), serde.ValueSerde, avrov2.NewDeserializerConfig())
		if err != nil {
			fail("cannot create the Avro deserializer: %v", err)
		}
		consume(topic, kafkaConfig, nbMessages, func(m *kafka.Message) string {
			var payment Payment
			if err := deserializer.DeserializeInto(*m.TopicPartition.Topic, m.Value, &payment); err != nil {
				fail("cannot deserialize the record at offset %v: %v", m.TopicPartition.Offset, err)
			}
			return fmt.Sprintf("%+v", payment)
		})
	default:
		usage()
	}
}
