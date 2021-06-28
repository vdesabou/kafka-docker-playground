const { Kafka,logLevel } = require('kafkajs')            //npm install kafkajs
const Chance = require('chance')                //npm install chance
const chance = new Chance()

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

const produceMessage = async () => {
    const value = chance.animal();
    console.log(value);

    try {
      await producer.send({
          topic,
          messages: [
            { value },
          ],
        })
    } catch (error) {
        console.log(error);
    }
}

const run = async () => {
  await admin.connect()
  await admin.createTopics({
    topics: [{ topic }],
    waitForLeaders: true,
  })

  // Producing
  await producer.connect()
  setInterval(produceMessage, 100)
}

run().catch(console.error)