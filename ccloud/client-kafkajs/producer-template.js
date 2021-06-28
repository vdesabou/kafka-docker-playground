const { Kafka } = require('kafkajs')            //npm install kafkajs
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
  },
})

const producer = kafka.producer()
const topic = 'kafkajs'

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
  // Producing
  await producer.connect()
  setInterval(produceMessage, 100)
}

run().catch(console.error)