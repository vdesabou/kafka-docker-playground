const { Kafka, CompressionTypes, logLevel } = require('kafkajs')            //npm install kafkajs

const kafka = new Kafka({
  clientId: 'my-kafkajs-producer',
  brokers: ['broker1:9092','broker2:9092','broker3:9092'],
  connectionTimeout: 20000,
})

const producer = kafka.producer()
const topic = 'kafkajs'

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