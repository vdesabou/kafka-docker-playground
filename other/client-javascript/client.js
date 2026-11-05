// Confluent JavaScript client for Apache Kafka (@confluentinc/kafka-javascript, on librdkafka), with its
// promisified KafkaJS-compatible API and librdkafka configuration properties, and the Avro serializer of the
// Confluent JavaScript client for Schema Registry (@confluentinc/schemaregistry).
//
// usage: node client.js produce|consume|produce-avro|consume-avro <topic> <config file> [<number of messages>]
//
// <config file>: one librdkafka property per line (bootstrap.servers, security.protocol, sasl.*...), plus the
// schema.registry.url and schema.registry.basic.auth.user.info properties of the Schema Registry client.

const fs = require('fs');
const rdkafka = require('@confluentinc/kafka-javascript');
const { Kafka } = rdkafka.KafkaJS;
const { SchemaRegistryClient, SerdeType, AvroSerializer, AvroDeserializer } = require('@confluentinc/schemaregistry');

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
  const clientProps = {};
  const schemaRegistryProps = {};
  for (const rawLine of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === '' || line.startsWith('#')) {
      continue;
    }
    const index = line.indexOf('=');
    if (index < 0) {
      continue;
    }
    const key = line.substring(0, index).trim();
    const value = line.substring(index + 1).trim();
    if (key.startsWith('schema.registry.')) {
      schemaRegistryProps[key] = value;
    } else {
      clientProps[key] = value;
    }
  }
  return { clientProps, schemaRegistryProps };
}

function schemaRegistryClient(schemaRegistryProps) {
  const url = schemaRegistryProps['schema.registry.url'];
  if (!url) {
    throw new Error('schema.registry.url is missing in the config file');
  }
  const config = { baseURLs: [url] };
  const userInfo = schemaRegistryProps['schema.registry.basic.auth.user.info'];
  if (userInfo) {
    config.basicAuthCredentials = { credentialsSource: 'USER_INFO', userInfo };
  }
  return new SchemaRegistryClient(config);
}

async function produce(topic, clientProps, nbMessages, valueOf) {
  const producer = new Kafka().producer({ ...clientProps, 'acks': 'all' });
  await producer.connect();
  try {
    for (let i = 0; i < nbMessages; i++) {
      const value = await valueOf(i);
      // await each send: it resolves with the delivery report of the record
      const [report] = await producer.send({ topic, messages: [{ key: `key-${i}`, value }] });
      console.log(`Produced record key-${i} to ${topic} [${report.partition}] at offset ${report.offset}`);
    }
    console.log(`${nbMessages} records were produced to topic ${topic}`);
  } finally {
    await producer.disconnect();
  }
}

async function consume(topic, clientProps, nbMessages, decode) {
  const groupId = `${topic}-group`;
  const consumer = new Kafka().consumer({
    ...clientProps,
    'group.id': groupId,
    'auto.offset.reset': 'earliest',
    'enable.auto.commit': false,
  });
  await consumer.connect();
  let nbConsumed = 0;
  try {
    await consumer.subscribe({ topics: [topic] });
    const done = new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`Timeout: consumed ${nbConsumed} records out of ${nbMessages} after ${CONSUME_TIMEOUT_MS / 1000}s`)),
        CONSUME_TIMEOUT_MS);
      consumer.run({
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
    await done;
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
  const { clientProps, schemaRegistryProps } = loadConfig(configFile);

  const clientVersion = require('@confluentinc/kafka-javascript/package.json').version;
  console.log(`@confluentinc/kafka-javascript ${clientVersion}, librdkafka ${rdkafka.librdkafkaVersion}`);

  switch (mode) {
    case 'produce':
      await produce(topic, clientProps, nbMessages, (i) => JSON.stringify({ id: `id-${i}`, amount: i * 10.5 }));
      break;
    case 'consume':
      await consume(topic, clientProps, nbMessages, (value) => value.toString());
      break;
    case 'produce-avro': {
      const registry = schemaRegistryClient(schemaRegistryProps);
      const subject = `${topic}-value`;
      const id = await registry.register(subject, { schemaType: 'AVRO', schema: JSON.stringify(SCHEMA) });
      console.log(`Registered schema ${SCHEMA.namespace}.${SCHEMA.name} under subject ${subject} with id ${id}`);
      const serializer = new AvroSerializer(registry, SerdeType.VALUE, { useLatestVersion: true });
      await produce(topic, clientProps, nbMessages, (i) => serializer.serialize(topic, { id: `id-${i}`, amount: i * 10.5 }));
      break;
    }
    case 'consume-avro': {
      const deserializer = new AvroDeserializer(schemaRegistryClient(schemaRegistryProps), SerdeType.VALUE, {});
      await consume(topic, clientProps, nbMessages, (value) => deserializer.deserialize(topic, value));
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
