const { Kafka, CompressionTypes, logLevel } = require('kafkajs')            //npm install kafkajs

const kafka = new Kafka({
  clientId: 'my-kafkajs-consumer',
  brokers: [':BOOTSTRAP_SERVERS:'],
  ssl: true,
  //    logLevel: logLevel.DEBUG,
  sasl: {
    mechanism: 'plain',
    username: ':CLOUD_KEY:',
    password: ':CLOUD_SECRET:'
  },
})


const myArgs = process.argv.slice(2)
console.log('topic is : ', myArgs[0])
const topic = myArgs[0]
const consumer = kafka.consumer({ groupId: 'test-group' })
const admin = kafka.admin()

const run = async () => {
  await admin.connect()
  await admin.createTopics({
    topics: [{ topic: topic, numPartitions: 1, replicationFactor: 3 }],
    waitForLeaders: true,
  })
  await consumer.connect()
  await consumer.subscribe({ topic, fromBeginning: false })
  await consumer.run({
    // eachBatch: async ({ batch }) => {
    //   console.log(batch)
    // },
    eachMessage: async ({ topic, partition, message }) => {
      const prefix = `${topic}[${partition} | ${message.offset}] / ${message.timestamp}`
      console.log(`- ${prefix} ${message.key}#${message.value}`)
    },
  })
}

run().catch(e => console.error(`[example/consumer] ${e.message}`, e))

const errorTypes = ['unhandledRejection', 'uncaughtException']
const signalTraps = ['SIGTERM', 'SIGINT', 'SIGUSR2']

errorTypes.map(type => {
  process.on(type, async e => {
    try {
      console.log(`process.on ${type}`)
      console.error(e)
      await consumer.disconnect()
      process.exit(0)
    } catch (_) {
      process.exit(1)
    }
  })
})

signalTraps.map(type => {
  process.once(type, async () => {
    try {
      await consumer.disconnect()
    } finally {
      process.kill(process.pid, type)
    }
  })
})