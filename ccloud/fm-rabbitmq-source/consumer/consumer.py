#!/usr/bin/env python3
import pika
import sys
import json

if len(sys.argv) != 2:
   print("Usage: " + sys.argv[0] + " <queueName>")
   sys.exit(1)

queue = sys.argv[1]

print("queue:\t%s" % (queue) )

credentials = pika.PlainCredentials('myuser', 'mypassword')
connection = pika.BlockingConnection(pika.ConnectionParameters('rabbitmq',5672,'/',credentials))
channel = connection.channel()
channel.queue_declare(queue = queue)

def callback(ch, method, properties, body):
    msgBody = json.loads(body)
    print("Receive\t%r" % msgBody)

channel.basic_consume(queue = queue,
                      auto_ack=True,
                      on_message_callback=callback)

print('Waiting for messages. To exit press CTRL+C')
try:
    channel.start_consuming()
except KeyboardInterrupt:
    print('Exiting')
