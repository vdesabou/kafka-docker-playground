// KafkaJS (kafkajs, a pure JavaScript Kafka client, not maintained since 2.2.4) with the Avro serializer of
// @kafkajs/confluent-schema-registry, the Schema Registry library KafkaJS applications usually use.
// The Confluent JavaScript client (@confluentinc/kafka-javascript) has a KafkaJS-compatible API: see other/client-javascript.
//
// usage: node client.js produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]
//
// <config file>: the same librdkafka-style properties as the other client examples, mapped to the KafkaJS configuration:
// bootstrap.servers, security.protocol (SASL_SSL, SSL), sasl.mechanisms (PLAIN, SCRAM-SHA-256, SCRAM-SHA-512),
// sasl.username, sasl.password, plus schema.registry.url and schema.registry.basic.auth.user.info.

const fs = require('fs');
const { Kafka, logLevel } = require('kafkajs');
const { SchemaRegistry, SchemaType } = require('@kafkajs/confluent-schema-registry');

const USAGE = 'usage: node client.js produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]';
const CONSUME_TIMEOUT_MS = 60000;

const SCHEMA = {
  type: 'record',
  namespace: 'io.confluent.playground',
  name: 'Payment',
  fields: [
    { name: 'id', type: 'string' },
    { name: 'amount', type: 'double' },
  ],
};

function loadConfig(file) {
  const props = {};
  for (const rawLine of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === '' || line.startsWith('#')) {
      continue;
    }
    const index = line.indexOf('=');
    if (index > 0) {
      props[line.substring(0, index).trim()] = line.substring(index + 1).trim();
    }
  }
  return props;
}

// librdkafka-style properties -> KafkaJS client configuration
function kafkaConfig(props, clientId) {
  if (!props['bootstrap.servers']) {
    throw new Error('bootstrap.servers is missing in the config file');
  }
  const config = { clientId, brokers: props['bootstrap.servers'].split(','), logLevel: logLevel.WARN };
  const protocol = (props['security.protocol'] || 'PLAINTEXT').toUpperCase();
  if (protocol === 'SSL' || protocol === 'SASL_SSL') {
    config.ssl = true;
  }
  if (protocol.startsWith('SASL_')) {
    config.sasl = {
      mechanism: (props['sasl.mechanisms'] || props['sasl.mechanism'] || 'PLAIN').toLowerCase(),
      username: props['sasl.username'],
      password: props['sasl.password'],
    };
  }
  return config;
}

function schemaRegistry(props) {
  const host = props['schema.registry.url'];
  if (!host) {
    throw new Error('schema.registry.url is missing in the config file');
  }
  const config = { host };
  const userInfo = props['schema.registry.basic.auth.user.info'];
  if (userInfo) {
    const index = userInfo.indexOf(':');
    config.auth = { username: userInfo.substring(0, index), password: userInfo.substring(index + 1) };
  }
  return new SchemaRegistry(config);
}

async function produce(topic, props, nbMessages, valueOf) {
  const producer = new Kafka(kafkaConfig(props, 'client-kafkajs-producer')).producer();
  await producer.connect();
  try {
    for (let i = 0; i < nbMessages; i++) {
      const value = await valueOf(i);
      // acks: -1 (all), awaited: it resolves with the metadata of the record
      const [metadata] = await producer.send({ topic, acks: -1, messages: [{ key: `key-${i}`, value }] });
      console.log(`Produced record key-${i} to ${topic} [${metadata.partition}] at offset ${metadata.baseOffset}`);
    }
    console.log(`${nbMessages} records were produced to topic ${topic}`);
  } finally {
    await producer.disconnect();
  }
}

async function consume(topic, props, nbMessages, decode) {
  const groupId = `${topic}-group`;
  const consumer = new Kafka(kafkaConfig(props, 'client-kafkajs-consumer')).consumer({ groupId });
  await consumer.connect();
  let nbConsumed = 0;
  try {
    await consumer.subscribe({ topics: [topic], fromBeginning: true });
    await new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`Timeout: consumed ${nbConsumed} records out of ${nbMessages} after ${CONSUME_TIMEOUT_MS / 1000}s`)),
        CONSUME_TIMEOUT_MS);
      consumer.run({
        autoCommit: false,
        eachMessage: async ({ topic: t, partition, message }) => {
          const value = await decode(message.value);
          console.log(`Consumed record from ${t} [${partition}] at offset ${message.offset}: key=${message.key?.toString()} value=${JSON.stringify(value)}`);
          await consumer.commitOffsets([{ topic: t, partition, offset: (BigInt(message.offset) + 1n).toString() }]);
          nbConsumed++;
          if (nbConsumed >= nbMessages) {
            clearTimeout(timer);
            resolve();
          }
        },
      }).catch(reject);
    });
    console.log(`${nbConsumed} records were consumed from topic ${topic} by group ${groupId}`);
  } finally {
    await consumer.disconnect();
  }
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 3 || args.length > 4) {
    console.error(USAGE);
    process.exit(1);
  }
  const [mode, topic, configFile] = args;
  const nbMessages = args.length === 4 ? parseInt(args[3], 10) : 10;
  const props = loadConfig(configFile);

  console.log(`kafkajs ${require('kafkajs/package.json').version}, @kafkajs/confluent-schema-registry ${require('@kafkajs/confluent-schema-registry/package.json').version}`);

  switch (mode) {
    case 'produce':
      await produce(topic, props, nbMessages, (i) => JSON.stringify({ id: `id-${i}`, amount: i * 10.5 }));
      break;
    case 'consume':
      await consume(topic, props, nbMessages, (value) => value.toString());
      break;
    case 'produce-avro': {
      const registry = schemaRegistry(props);
      const subject = `${topic}-value`;
      const { id } = await registry.register({ type: SchemaType.AVRO, schema: JSON.stringify(SCHEMA) }, { subject });
      console.log(`Registered schema ${SCHEMA.namespace}.${SCHEMA.name} under subject ${subject} with id ${id}`);
      await produce(topic, props, nbMessages, (i) => registry.encode(id, { id: `id-${i}`, amount: i * 10.5 }));
      break;
    }
    case 'consume-avro': {
      const registry = schemaRegistry(props);
      await consume(topic, props, nbMessages, (value) => registry.decode(value));
      break;
    }
    default:
      console.error(USAGE);
      process.exit(1);
  }
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
