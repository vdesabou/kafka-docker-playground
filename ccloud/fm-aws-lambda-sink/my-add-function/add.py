import json
import logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    result_list = []
    for obj in event:

        payload = obj["payload"]
        logging.info(payload)

        value = payload["value"]
        num1 = value["a"]
        num2 = value["b"]

        timestamp = payload["timestamp"]
        offset = payload["offset"]
        partition = payload["partition"]
        topic = payload["topic"]

        payload_result = {}

        payload_result["timestamp"] = timestamp
        payload_result["offset"] = offset
        payload_result["partition"] = partition
        payload_result["topic"] = topic

        result = {}
        result["sum"] = num1 + num2
        payload_result["result"] = result

        final_result = {}
        final_result["payload"] = payload_result

        result_list.append(final_result)

        logging.info(final_result)
    return result_list