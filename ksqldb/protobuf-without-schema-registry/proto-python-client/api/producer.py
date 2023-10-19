from confluent_kafka import Producer
import addressbook_pb2

TOPIC = 'persons'


def kafka_delivery_callback(err, msg):
    if err:
        print('%% Message failed delivery: %s\n' % err)
    else:
        print('%% Message delivered to %s [%d] @ %d\n' % (msg.topic(), msg.partition(), msg.offset()))


def main():
    conf = {'bootstrap.servers': 'broker:9092'}
    kafka = Producer(**conf)

    person = addressbook_pb2.Person()
    person.id = 1234
    person.name = "John Doe"
    person.email = "jdoe@example.com"
    phone = person.phones.add()
    phone.number = "555-4321"
    phone.type = addressbook_pb2.Person.PHONE_TYPE_HOME

    kafka.produce(TOPIC, key="1234", value=person.SerializeToString(), callback=kafka_delivery_callback)
    kafka.poll(0)

    print("Waiting for kafka deliveries..")
    kafka.flush()
    print(person.SerializeToString())
main()
