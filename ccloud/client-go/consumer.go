// =============================================================================
//
// Consume messages from Confluent Cloud
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
	"encoding/json"
	"fmt"
	"gopkg.in/confluentinc/confluent-kafka-go.v1/kafka"
	"os"
	"os/signal"
	"syscall"
	"time"
	"bufio"
	"flag"
	"strings"
)

// RecordValue represents the struct of the value in a Kafka message
type RecordValue struct {
	Count int
}

func main() {

	// Initialization
	configFile, topic := ParseArgs()
	conf := ReadCCloudConfig(*configFile)

	// Create Consumer instance
	c, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers": conf["bootstrap.servers"],
		"sasl.mechanisms": conf["sasl.mechanisms"],
		"security.protocol": conf["security.protocol"],
		"sasl.username":     conf["sasl.username"],
		"sasl.password":     conf["sasl.password"],
		"group.id":          "go_example_group_1",
		"auto.offset.reset": "earliest",
	})
	if err != nil {
		fmt.Printf("Failed to create consumer: %s", err)
		os.Exit(1)
	}

	// Subscribe to topic
	err = c.SubscribeTopics([]string{*topic}, nil)
	// Set up a channel for handling Ctrl-C, etc
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)

	// Process messages
	totalCount := 0
	run := true
	for run == true {
		select {
		case sig := <-sigchan:
			fmt.Printf("Caught signal %v: terminating\n", sig)
			run = false
		default:
			msg, err := c.ReadMessage(100 * time.Millisecond)
			if err != nil {
				// Errors are informational and automatically handled by the consumer
				continue
			}
			recordKey := string(msg.Key)
			recordValue := msg.Value
			data := RecordValue{}
			err = json.Unmarshal(recordValue, &data)
			if err != nil {
				fmt.Printf("Failed to decode JSON at offset %d: %v", msg.TopicPartition.Offset, err)
				continue
			}
			count := data.Count
			totalCount += count
			fmt.Printf("Consumed record with key %s and value %s, and updated total count to %d\n", recordKey, recordValue, totalCount)
		}
	}

	fmt.Printf("Closing consumer\n")
	c.Close()

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