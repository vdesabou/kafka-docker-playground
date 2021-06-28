const { Kafka, CompressionTypes, logLevel } = require('kafkajs')            //npm install kafkajs
const Chance = require('chance')                //npm install chance

const kafka = new Kafka({
  clientId: 'my-kafkajs-producer',
  brokers: [':BOOTSTRAP_SERVERS:'],
  connectionTimeout: 3000,
  ssl: true,
  sasl: {
    mechanism: 'plain',
    username: ':CLOUD_KEY:',
    password: ':CLOUD_SECRET:',
    logLevel: logLevel.DEBUG
  },
})

const producer = kafka.producer()
const topic = 'kafkajs'
const admin = kafka.admin()

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
    topics: [{ topic }],
    waitForLeaders: true,
  })

  // Producing
  await producer.connect()
  setInterval(sendMessage, 10)
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