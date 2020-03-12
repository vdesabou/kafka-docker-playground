// =============================================================================
//
// Produce messages to Confluent Cloud
// Using Confluent Golang Client for Apache Kafka
//
// =============================================================================

package main

/**
 * Copyright 2019 Confluent Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import (
	"context"
	"encoding/json"
	"gopkg.in/confluentinc/confluent-kafka-go.v1/kafka"
	"fmt"
	"os"
	"time"
	"bufio"
	"flag"
	"strings"
)

// RecordValue represents the struct of the value in a Kafka message
type RecordValue struct {
	Count int
}
// CreateTopic creates a topic using the Admin Client API
func CreateTopic(p *kafka.Producer, topic string) {

	a, err := kafka.NewAdminClientFromProducer(p)
	if err != nil {
		fmt.Printf("Failed to create new admin client from producer: %s", err)
		os.Exit(1)
	}
	// Contexts are used to abort or limit the amount of time
	// the Admin call blocks waiting for a result.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	// Create topics on cluster.
	// Set Admin options to wait up to 60s for the operation to finish on the remote cluster
	maxDur, err := time.ParseDuration("60s")
	if err != nil {
		fmt.Printf("ParseDuration(60s): %s", err)
		os.Exit(1)
	}
	results, err := a.CreateTopics(
		ctx,
		// Multiple topics can be created simultaneously
		// by providing more TopicSpecification structs here.
		[]kafka.TopicSpecification{{
			Topic:             topic,
			NumPartitions:     1,
			ReplicationFactor: 3}},
		// Admin options
		kafka.SetAdminOperationTimeout(maxDur))
	if err != nil {
		fmt.Printf("Admin Client request error: %v\n", err)
		os.Exit(1)
	}
	for _, result := range results {
		if result.Error.Code() != kafka.ErrNoError && result.Error.Code() != kafka.ErrTopicAlreadyExists {
			fmt.Printf("Failed to create topic: %v\n", result.Error)
			os.Exit(1)
		}
		fmt.Printf("%v\n", result)
	}
	a.Close()

}

func main() {

	// Initialization
	configFile, topic := ParseArgs()
	conf := ReadCCloudConfig(*configFile)

	// Create Producer instance
	p, err := kafka.NewProducer(&kafka.ConfigMap{
		"bootstrap.servers": conf["bootstrap.servers"],
		"sasl.mechanisms": conf["sasl.mechanisms"],
		"security.protocol": conf["security.protocol"],
		"sasl.username":     conf["sasl.username"],
		"sasl.password":     conf["sasl.password"]})
	if err != nil {
		fmt.Printf("Failed to create producer: %s", err)
		os.Exit(1)
	}

	// Create topic if needed
	CreateTopic(p, *topic)

	// Go-routine to handle message delivery reports and
	// possibly other event types (errors, stats, etc)
	go func() {
		for e := range p.Events() {
			switch ev := e.(type) {
			case *kafka.Message:
				if ev.TopicPartition.Error != nil {
					fmt.Printf("Failed to deliver message: %v\n", ev.TopicPartition)
				} else {
					fmt.Printf("Successfully produced record to topic %s partition [%d] @ offset %v\n",
						*ev.TopicPartition.Topic, ev.TopicPartition.Partition, ev.TopicPartition.Offset)
				}
			}
		}
	}()

	for n := 0; n < 10; n++ {
		recordKey := "alice"
		data := &RecordValue{
			Count: n}
		recordValue, _ := json.Marshal(&data)
		fmt.Printf("Preparing to produce record: %s\t%s\n", recordKey, recordValue)
		p.Produce(&kafka.Message{
			TopicPartition: kafka.TopicPartition{Topic: topic, Partition: kafka.PartitionAny},
			Key:            []byte(recordKey),
			Value:          []byte(recordValue),
		}, nil)
	}

	// Wait for all messages to be delivered
	p.Flush(15 * 1000)

	fmt.Printf("10 messages were produced to topic %s!", *topic)

	p.Close()

}

// ParseArgs parses the command line arguments and
// returns the config file and topic on success, or exits on error
func ParseArgs() (*string, *string) {

	configFile := flag.String("f", "", "Path to Confluent Cloud configuration file")
	topic := flag.String("t", "", "Topic name")
	flag.Parse()
	if *configFile == "" || *topic == "" {
		flag.Usage()
		os.Exit(2) // the same exit code flag.Parse uses
	}

	return configFile, topic

}

// ReadCCloudConfig reads the file specified by configFile and
// creates a map of key-value pairs that correspond to each
// line of the file. ReadCCloudConfig returns the map on success,
// or exits on error
func ReadCCloudConfig(configFile string) map[string]string {

	m := make(map[string]string)

	file, err := os.Open(configFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to open file: %s", err)
		os.Exit(1)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !strings.HasPrefix(line, "#") && len(line) != 0 {
			kv := strings.Split(line, "=")
			parameter := strings.TrimSpace(kv[0])
			value := strings.TrimSpace(kv[1])
			m[parameter] = value
		}
	}

	if err := scanner.Err(); err != nil {
		fmt.Printf("Failed to read file: %s", err)
		os.Exit(1)
	}

	return m

}