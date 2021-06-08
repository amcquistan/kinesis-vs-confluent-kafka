import datetime
import json
import logging
import os
import time

import boto3
import requests
from confluent_kafka import SerializingProducer, KafkaError
from confluent_kafka.serialization import StringSerializer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
kinesis = boto3.client('kinesis')

UTC_OPEN = datetime.time(12, 00, tzinfo=datetime.timezone.utc)
UTC_CLOSE = datetime.time(23, 00, tzinfo=datetime.timezone.utc)


STOCK_QUOTE_SCHEMA = """
  {
    "namespace": "com.intrado.stockdemo",
    "name": "StockQuote",
    "type": "record",
    "fields": [
      {"name":"symbol",         "type":"string"},
      {"name":"short_name",     "type":["null", "string"], "default": null},
      {"name":"market_time",    "type":"long"},
      {"name":"quote_source",   "type":["null", "string"], "default": null},
      {"name":"current",        "type":"double"},
      {"name":"low_day",        "type":"double"},
      {"name":"high_day",       "type":"double"},
      {"name":"open",           "type":["null", "double"], "default": null},
      {"name":"previous_close", "type":["null", "double"], "default": null},
      {"name":"low_52wk",       "type":["null", "double"], "default": null},
      {"name":"high_52wk",      "type":["null", "double"], "default": null}
    ]
  }
"""

def encode_record(record: dict) -> bytes:
    bytes_data = json.dumps(record).encode('utf-8')
    return bytes_data


class AckCallback:
    def __init__(self, key, value):
        self.key = key
        self.value = value
    
    def __call__(self, err, msg):
        if err:
            logger.error({
                'message': 'failed to deliver message to Kafka',
                'error': str(err),
                'key': self.key,
                'value': self.value
            })
        else:
            logger.info({
                'message': 'successfully produced message to Kafka',
                'topic': msg.topic(),
                'partition': msg.partition(),
                'offset': msg.offset(),
                'key': self.key,
                'value': self.value
            })


def lambda_handler(event, context):
    now = datetime.datetime.utcnow()
    utc_now = datetime.time(now.hour, now.minute, tzinfo=datetime.timezone.utc)
    if utc_now < UTC_OPEN or utc_now > UTC_CLOSE:
        logger.info({'message': 'Exiting early, {} not during market hours {} - {}'.format(utc_now, UTC_OPEN, UTC_CLOSE)})
        return

    headers = {
      'x-rapidapi-key': os.environ['YAHOO_X_RAPIDAPI_KEY'],
      'x-rapidapi-host': os.environ['YAHOO_X_RAPIDAPI_HOST']
    }
    query_params = {
        'region': 'US',
        'symbols': 'AMZN,MSFT,AAPL,NEOG,BOX,NNI'
    }
    logger.info({'action': 'fetching_stocks', 'details': query_params})

    sr_conf = {
      'url': os.environ['SR_URL'],
      'basic.auth.user.info': "{}:{}".format(os.environ['SR_KEY'], os.environ['SR_SECRET'])
    }
    sr_client = SchemaRegistryClient(sr_conf)

    key_serializer = StringSerializer()
    value_serializer = AvroSerializer(schema_registry_client=sr_client,
                                      schema_str=STOCK_QUOTE_SCHEMA)

    producer_conf = {
      'bootstrap.servers': os.environ['KAFKA_BOOTSTRAP_SERVER'],
      'key.serializer': key_serializer,
      'value.serializer': value_serializer,
      'security.protocol': 'SASL_SSL',
      'sasl.mechanism': 'PLAIN',
      'sasl.username': os.environ['KAFKA_SASL_USERNAME'],
      'sasl.password': os.environ['KAFKA_SASL_PASSWORD'],
      'partitioner': 'murmur2_random',
      'linger.ms': 100
    }
    kafka_producer = SerializingProducer(producer_conf)

    for _ in range(5):
        try:
            response = requests.get(os.environ['YAHOO_QUOTES_URL'], headers=headers, params=query_params)
            data = response.json()
        except Exception as e:
            logger.error({'error': 'failed_stocks_fetch', 'exception': str(e)})
            raise e

        records = []
        for quote in data['quoteResponse']['result']:
            record_value = {
                'symbol': quote['symbol'],
                'short_name': quote['shortName'],
                'market_time': quote['regularMarketTime'],
                'quote_source': quote['quoteSourceName'],
                'current': quote['regularMarketPrice'],
                'low_day': quote['regularMarketDayLow'],
                'high_day': quote['regularMarketDayHigh'],
                'open': quote['regularMarketOpen'],
                'previous_close': quote['regularMarketPreviousClose'],
                'low_52wk': quote['fiftyTwoWeekLow'],
                'high_52wk': quote['fiftyTwoWeekHigh'],
            }
            record_key = quote['symbol']
            records.append({
                'Data': encode_record(record_value),
                'PartitionKey': record_key
            })

            try:
                kafka_producer.produce(os.environ['KAFKA_TOPIC'],
                                    key=record_key,
                                    value=record_value,
                                    on_delivery=AckCallback(record_key, record_value))
            except KafkaError as e:
                logger.error({'action': 'kafka_produce', 'exception': str(e)})

        try:
            response = kinesis.put_records(Records=records, StreamName=os.environ['KINESIS_STREAM'])
            logger.info({'action': 'kinesis_put_records', 'response': response})
        except Exception as e:
            logger.error({'error': 'failed_kinesis_fetch', 'exception': str(e)})
            raise e

        kafka_producer.poll(0)
        time.sleep(9)

    kafka_producer.flush()
    logger.info({'action': 'stock_producer_complete'})
