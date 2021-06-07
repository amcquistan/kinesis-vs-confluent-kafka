#!./.venv/bin/python

import argparse
import os
import random
import time

from confluent_kafka import SerializingProducer
from confluent_kafka.serialization import StringSerializer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer


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

COMPANIES = ['HOOLI', 'ACME']


class RandomQuoteGenerator:
    def __init__(self, company_symbols):
        self.company_symbols = company_symbols
        self.quotes = {}

    def generate_quote(self):
        symbol = random.choice(self.company_symbols)
        company_quotes = self.quotes.get(symbol, [])
        val = round(random.uniform(100, 500), 2)
        company_quotes.append(val)
        self.quotes[symbol] = company_quotes

        ts = int(time.time())
        record_value = {
            'symbol': symbol,
            'market_time': int(time.time()),
            'current': val,
            'low_day': min(company_quotes),
            'high_day': max(company_quotes)
        }
        return symbol, record_value


class AckCallback:
    def __init__(self, key, value):
        self.key = key
        self.value = value
    
    def __call__(self, err, msg):
        if err:
            print("Message delivery failure {}".format(err))
            return

        print("Produced record to topic {} key {} value {} partition [{}] @ offset {}"
              .format(msg.topic(), self.key, self.value, msg.partition(), msg.offset()))


def main(args):
    sr_conf = {
      'url': args.sr_url,
      'basic.auth.user.info': "{}:{}".format(args.sr_key, args.sr_secret)
    }
    sr_client = SchemaRegistryClient(sr_conf)

    key_serializer = StringSerializer()
    value_serializer = AvroSerializer(schema_registry_client=sr_client,
                                      schema_str=STOCK_QUOTE_SCHEMA)

    producer_conf = {
      'bootstrap.servers': args.bootstrap_server,
      'key.serializer': key_serializer,
      'value.serializer': value_serializer,
      'security.protocol': 'SASL_SSL',
      'sasl.mechanism': 'PLAIN',
      'sasl.username': args.kafka_key,
      'sasl.password': args.kafka_secret,
      'partitioner': 'murmur2_random',
      'linger.ms': 100
    }
    producer = SerializingProducer(producer_conf)

    quote_generator = RandomQuoteGenerator(COMPANIES)

    try:
        while True:
            record_key, record_value = quote_generator.generate_quote()
            producer.produce(topic=args.topic,
                            key=record_key,
                            value=record_value,
                            on_delivery=AckCallback(record_key, record_value))
            producer.poll(0)
            time.sleep(3)
    except Exception as e:
        print("Error {}".format(str(e)))
    finally:
        producer.flush()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bootstrap-server')
    parser.add_argument('--topic')
    parser.add_argument('--kafka-key')
    parser.add_argument('--kafka-secret')
    parser.add_argument('--sr-url')
    parser.add_argument('--sr-key')
    parser.add_argument('--sr-secret')

    main(parser.parse_args())

