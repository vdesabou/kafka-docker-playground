const { Kafka, CompressionTypes, logLevel } = require('kafkajs')            //npm install kafkajs
// add timestamps in front of log messages
require('console-stamp')(console, '[HH:MM:ss.l]');

const kafka = new Kafka({
  clientId: 'my-kafkajs-producer',
  brokers: ['broker:9092'],
  connectionTimeout: 10000,
  // enforceRequestTimeout: true,
  // requestTimeout: 3000,
  // //logLevel: logLevel.DEBUG,
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
//producer.logger().setLogLevel(logLevel.DEBUG)

let bigString = '';
for (let i = 0; i < 100; i++) {
  bigString += Math.random().toString(3);
}

const payload = new Array(10).fill({value: bigString});

var outgoingMessages = 0;

function successCallback(result) {
  console.log("send() finished ");
  outgoingMessages--;
}

function exceptionCallback(result) {
  // console.error(`[example/producer] ${e.message}`, e)
  console.log("send() failed!  " + result);
  outgoingMessages--;
}

function sendData() {
  const now = new Date();
  const used = process.memoryUsage().heapUsed / 1024 / 1024;
  console.log(`Memory: ${Math.round(used * 100) / 100} MB`);
  console.log(`outgoingMessages ` + outgoingMessages);

  if(outgoingMessages>100) {
    console.log(`Refusing message as we have outgoing messages ` + outgoingMessages);
    return;
  }
  outgoingMessages++;

  producer.send({
    topic: topic,
    messages: payload,
    acks: 1,
  }).then(() => {
    console.log('data sent', {messages: payload.length, duration: new Date() - now});
    outgoingMessages--;
  }).catch(e => {
    console.log('failed to send data', e);
    outgoingMessages--;
  });
}

(async function main(){
  await admin.connect()
  await admin.createTopics({
    topics: [{ topic }],
    waitForLeaders: true,
  })
  await producer.connect().catch(e => {
    log.error("failed to producer.connect()", e);
  });
  setInterval(sendData, 1000);
})().catch(e => {throw e});