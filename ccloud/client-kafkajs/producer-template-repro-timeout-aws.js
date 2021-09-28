const { Kafka, CompressionTypes, logLevel } = require('kafkajs')            //npm install kafkajs
// add timestamps in front of log messages
require('console-stamp')(console, '[HH:MM:ss.l]');

const kafka = new Kafka({
    clientId: 'my-kafkajs-producer',
    brokers: [':BOOTSTRAP_SERVERS:'],
    ssl: true,
    sasl: {
      mechanism: 'plain',
      username: ':CLOUD_KEY:',
      password: ':CLOUD_SECRET:',
    },
    acks:1,
    connectionTimeout: 20000,
    enforceRequestTimeout: true,
    // requestTimeout: 3000,
    logLevel: logLevel.DEBUG,
    // retry: {
    //   initialRetryTime: 100,
    //   retries: 1
    // },
  })

const producer = kafka.producer()
const topic = 'kafkajs'
const admin = kafka.admin()

const { CONNECT, DISCONNECT, REQUEST_TIMEOUT, REQUEST_QUEUE_SIZE } = producer.events;
producer.on(CONNECT, e => console.log(`Producer connected at ${e.timestamp}`));
producer.on(DISCONNECT, e => console.log(`Producer disconnected at ${e.timestamp}`));
producer.on(REQUEST_TIMEOUT, e => console.log(`Producer request timed out at ${e.timestamp}`, JSON.stringify(e.payload)));
producer.on(REQUEST_QUEUE_SIZE, e => console.log(`Request queue size at ${e.timestamp}`, JSON.stringify(e.payload)));

let bigString = '';
for (let i = 0; i < 100; i++) {
  bigString += Math.random().toString(36);
}

const getRandomNumber = () => Math.round(Math.random(10) * 1000)
const createMessage = num => ({
  key: `key-${num}-${Math.random().toString(12)}`,
  value: `value-${num}-${bigString}`,
})


function sendData() {
  const used = process.memoryUsage().heapUsed / 1024 / 1024;
  console.log(`Memory: ${Math.round(used * 100) / 100} MB`);

  console.log('kafka.js send');
  producer.send({
    topic: topic,
    //messages: payload,
    messages: Array(getRandomNumber())
        .fill()
        .map(_ => createMessage(getRandomNumber())),
    acks: 1,
  }).then(() => {
    console.log('kafka.js success');
  }).catch(e => {
    console.log('kafka.js failed', e);
  });
}

(async function main(){
  await admin.connect()
  // await admin.createTopics({
  //   topics: [{ topic }],
  //   waitForLeaders: true,
  // })
  await producer.connect().catch(e => {
    log.error("failed to producer.connect()", e);
  });
  setInterval(sendData, 100);
})().catch(e => {throw e});