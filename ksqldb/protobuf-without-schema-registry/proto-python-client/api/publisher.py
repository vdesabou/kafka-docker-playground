from confluent_kafka import Producer
from protos.user_created_event_pb2 import UserCreatedEvent
from protos.models.user_pb2 import User
from datetime import datetime
from google.protobuf.timestamp_pb2 import Timestamp


TOPIC = 'user_created_event'


def kafka_delivery_callback(err, msg):
    if err:
        print('%% Message failed delivery: %s\n' % err)
    else:
        print('%% Message delivered to %s [%d] @ %d\n' % (msg.topic(), msg.partition(), msg.offset()))


def main():
    conf = {'bootstrap.servers': 'broker:9092'}
    kafka = Producer(**conf)

    event = UserCreatedEvent(
        event_id = 'abcdefghi-event_id',
        event_timestamp = Timestamp().GetCurrentTime(),
        event_name = 'UserCreatedEvent',
        version = '1.2.1',
    )

    kafka.produce(TOPIC, event.SerializeToString(), callback=kafka_delivery_callback)
    kafka.poll(0)

    print("Waiting for kafka deliveries..")
    kafka.flush()

main()
