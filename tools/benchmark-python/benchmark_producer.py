"""Load for 'playground connector benchmark' on the aws and gcp messaging sources (sqs, kinesis, pub/sub).

Run by benchmark_python_load (scripts/cli/src/lib/utils_function.sh) in the playground-benchmark-python image:
  benchmark_producer.py sqs --queue-url <url> --region <region> --records <n> [--first <i>] [--record-size <bytes>] [--shape bulk|small-txn]
  benchmark_producer.py kinesis --stream <name> --region <region> --records <n> ...
  benchmark_producer.py pubsub --project <id> --topic <id> --keyfile <path> --records <n> ...
Messages are "benchmark message <i>", padded with spaces to --record-size. Prints SENT=<n> at the end.
"""
import argparse
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor


def messages(args):
    for i in range(args.first, args.first + args.records):
        message = "benchmark message %d" % i
        if args.record_size > len(message):
            message = message.ljust(args.record_size)
        yield message


def chunks(items, size):
    items = list(items)
    return [items[i:i + size] for i in range(0, len(items), size)]


def aws_client(service, args):
    import boto3
    from botocore.config import Config
    return boto3.client(service, region_name=args.region,
                        config=Config(max_pool_connections=args.threads, retries={"max_attempts": 10, "mode": "adaptive"}))


def sqs(args):
    client = aws_client("sqs", args)
    # a fifo queue needs a message group and a deduplication id (the threads send in parallel: no order across batches)
    fifo = args.queue_url.endswith(".fifo")

    def entry(i, message):
        e = {"Id": str(i), "MessageBody": message}
        if fifo:
            e.update(MessageGroupId="benchmark", MessageDeduplicationId=uuid.uuid4().hex)
        return e
    if args.shape == "small-txn":
        def send_one(message):
            e = entry(0, message)
            del e["Id"]
            client.send_message(QueueUrl=args.queue_url, **e)
        with ThreadPoolExecutor(args.threads) as executor:
            list(executor.map(send_one, messages(args)))
        return

    # send_message_batch takes 10 messages at most, and can fail some of them
    def send_batch(batch):
        entries = [entry(i, m) for i, m in enumerate(batch)]
        while entries:
            failed = {f["Id"] for f in client.send_message_batch(QueueUrl=args.queue_url, Entries=entries).get("Failed", [])}
            entries = [e for e in entries if e["Id"] in failed]
            if entries:
                time.sleep(0.2)
    with ThreadPoolExecutor(args.threads) as executor:
        list(executor.map(send_batch, chunks(messages(args), 10)))


def kinesis(args):
    client = aws_client("kinesis", args)
    size = 1 if args.shape == "small-txn" else 500

    # put_records takes 500 records at most; a shard takes 1000 records/s, the throttled records are sent again
    def put_batch(batch):
        records = [{"Data": m.encode(), "PartitionKey": str(hash(m))} for m in batch]
        delay = 0.1
        while records:
            response = client.put_records(StreamName=args.stream, Records=records)
            if not response.get("FailedRecordCount"):
                return
            records = [r for r, result in zip(records, response["Records"]) if "ErrorCode" in result]
            time.sleep(delay)
            delay = min(delay * 2, 2)
    with ThreadPoolExecutor(args.threads) as executor:
        list(executor.map(put_batch, chunks(messages(args), size)))


def pubsub(args):
    from google.cloud import pubsub_v1
    from google.oauth2 import service_account
    credentials = service_account.Credentials.from_service_account_file(args.keyfile)
    batch_settings = pubsub_v1.types.BatchSettings(max_messages=1000, max_bytes=9000000, max_latency=0.05)
    if args.shape == "small-txn":
        batch_settings = pubsub_v1.types.BatchSettings(max_messages=1)
    publisher = pubsub_v1.PublisherClient(credentials=credentials, batch_settings=batch_settings)
    topic = publisher.topic_path(args.project, args.topic)
    if args.shape == "small-txn":
        for message in messages(args):
            publisher.publish(topic, message.encode()).result()
        return
    futures = [publisher.publish(topic, message.encode()) for message in messages(args)]
    for future in futures:
        future.result()


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="target", required=True)
    for name in ("sqs", "kinesis", "pubsub"):
        p = sub.add_parser(name)
        p.add_argument("--records", type=int, required=True)
        p.add_argument("--first", type=int, default=1)
        p.add_argument("--record-size", type=int, default=0)
        p.add_argument("--shape", default="bulk", choices=["bulk", "small-txn"])
        p.add_argument("--threads", type=int, default=16)
        if name in ("sqs", "kinesis"):
            p.add_argument("--region", required=True)
        if name == "sqs":
            p.add_argument("--queue-url", required=True)
        if name == "kinesis":
            p.add_argument("--stream", required=True)
        if name == "pubsub":
            p.add_argument("--project", required=True)
            p.add_argument("--topic", required=True)
            p.add_argument("--keyfile", required=True)
    args = parser.parse_args()
    {"sqs": sqs, "kinesis": kinesis, "pubsub": pubsub}[args.target](args)
    print("SENT=%d" % args.records)


if __name__ == "__main__":
    sys.exit(main())
