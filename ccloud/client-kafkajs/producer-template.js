const { Kafka, CompressionTypes, logLevel } = require('kafkajs')            //npm install kafkajs
// add timestamps in front of log messages
require('console-stamp')(console, '[HH:MM:ss.l]');

const kafka = new Kafka({
  clientId: 'my-kafkajs-producer',
  brokers: [':BOOTSTRAP_SERVERS:'],
  connectionTimeout: 20000,
  ssl: true,
  //logLevel: logLevel.DEBUG,
  enforceRequestTimeout: true,
  requestTimeout: 3000,
  retry: {
    initialRetryTime: 100,
    retries: 1
  },
  sasl: {
    mechanism: 'plain',
    username: ':CLOUD_KEY:',
    password: ':CLOUD_SECRET:',
  },
})

const producer = kafka.producer()
const myArgs = process.argv.slice(2)
console.log('topic is : ', myArgs[0])
const topic = myArgs[0]
const admin = kafka.admin()

const { CONNECT, DISCONNECT, REQUEST_TIMEOUT } = producer.events;
producer.on(CONNECT, e => console.log(`Producer connected at ${e.timestamp}`));
producer.on(DISCONNECT, e => console.log(`Producer disconnected at ${e.timestamp}`));
producer.on(REQUEST_TIMEOUT, e => console.log(`Producer request timed out at ${e.timestamp}`, JSON.stringify(e.payload)));
//producer.logger().setLogLevel(logLevel.DEBUG)

const getRandomNumber = () => Math.round(Math.random(10) * 1000)
const createMessage = num => ({
  key: `key-${num}`,
  value: `value-${num}-${new Date().toISOString()}`,
})

const sendMessage = () => {
  return producer
    .send({
      topic,
      // compression: CompressionTypes.GZIP,
      messages: Array(getRandomNumber())
        .fill()
        .map(_ => createMessage(getRandomNumber())),
    })
    .then(console.log)
    .catch(e => console.error(`[example/producer] ${e.message}`, e))
}

const run = async () => {
  await admin.connect()
  await admin.createTopics({
    topics: [{ topic: topic, numPartitions: 1, replicationFactor: 3 }],
    waitForLeaders: true,
  })

  // Producing
  await producer.connect()
  setInterval(sendMessage, 1000)
}

run().catch(e => console.error(`[example/producer] ${e.message}`, e))

const errorTypes = ['unhandledRejection', 'uncaughtException']
const signalTraps = ['SIGTERM', 'SIGINT', 'SIGUSR2']

errorTypes.map(type => {
  process.on(type, async () => {
    try {
      console.log(`process.on ${type}`)
      await producer.disconnect()
      process.exit(0)
    } catch (_) {
      process.exit(1)
    }
  })
})

signalTraps.map(type => {
  process.once(type, async () => {
    try {
      await producer.disconnect()
    } finally {
      process.kill(process.pid, type)
    }
  })
})