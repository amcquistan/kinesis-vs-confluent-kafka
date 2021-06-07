import base64
import json
import logging
import os

import boto3
import datetime
from dateutil import parser


logger = logging.getLogger()
logger.setLevel(logging.INFO)

kinesis = boto3.client('kinesis')
s3 = boto3.client('s3')
sns = boto3.client('sns')

UTC_OPEN = datetime.time(14, 30, tzinfo=datetime.timezone.utc)
UTC_CLOSE = datetime.time(21, 00, tzinfo=datetime.timezone.utc)


def decode_record(record: bytes) -> dict:
    string_data = base64.b64decode(record).decode('utf-8')
    return json.loads(string_data)


def send_alert(message: str) -> None:
    logger.info({'action': 'send_stock_alert', 'alert_message': message})
    try:
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC'],
            Message=message,
            Subject='Kinesis Lambda Stocks Stream Alert'
        )
    except Exception as e:
        logger.error({
            'error': 'failed_sns_publish',
            'exception': str(e),
            'topic': os.environ['SNS_TOPIC'],
            'message': message
        })
        raise e


def save_window_aggregate(window_state: dict) -> None:
    logger.info({'action': 'save_window_state', 'window_state': window_state})

    end_dt = parser.parse(window_state['window_end'])
    s3_key = "{s3_prefix}/year={y}/month={m:02d}/day={d:02d}/hour={h:02d}/{filename}".format(
        s3_prefix=os.environ['OUTPUT_S3PREFIX'],
        y=end_dt.year,
        m=end_dt.month,
        d=end_dt.day,
        h=end_dt.hour,
        filename=end_dt.strftime("%Y-%m-%dT%H%M%S.json")
    )
    try:
        s3.put_object(
            Bucket=os.environ['S3_BUCKET'],
            Body=json.dumps(window_state).encode('utf-8'),
            Key=s3_key,
            ACL='private'
        )
    except Exception as e:
        logger.error({
            'window_state': window_state,
            'error': 'failed_s3_put',
            'exception': str(e),
            's3_bucket': os.environ['S3_BUCKET'],
            's3_key': s3_key
        })
        raise e


def lambda_handler(event, context):
    now = datetime.datetime.utcnow()
    utc_now = datetime.time(now.hour, now.minute, tzinfo=datetime.timezone.utc)
    if utc_now < UTC_OPEN or utc_now > UTC_CLOSE:
        # restart empty state in non-market time
        logger.info({'message': 'Exiting early, {} not during market hours {} - {}'.format(utc_now, UTC_OPEN, UTC_CLOSE)})
        return {}

    if event['isWindowTerminatedEarly']:
        logger.error({'error': 'window_terminated_early', 'event': event})

    state = event.get('state', {})
    if not state:
        logger.info({'action': 'starting_new_state', 'event': event})

    if event['isFinalInvokeForWindow']:
        logger.info({'action': 'window_final_invoke', 'event': event})

        for symbol, symbol_data in state.items():
            if symbol_data['low_window'] < symbol_data['low_day']:
                msg = '{} has new daily low of ${} down from ${}'.format(symbol, symbol_data['low_window'], symbol_data['low_day'])
                symbol_data['low_day'] = symbol_data['low_window']
                send_alert(msg)

            if symbol_data['high_window'] > symbol_data['high_day']:
                msg = '{} has new daily high of ${} up from ${}'.format(symbol, symbol_data['high_window'], symbol_data['high_day'])
                symbol_data['high_day'] = symbol_data['high_window']
                send_alert(msg)

        save_window_aggregate({
            'window_state': state,
            'window_start': event['window']['start'],
            'window_end': event['window']['end'],
            'shard_id': event['shardId']
        })

    for record in event['Records']:
        try:
            stock_data = decode_record(record['kinesis']['data'])
        except Exception as e:
            logger.error({
                'error': 'failed_decoding_record',
                'exception': str(e),
                'record': record
            })
            raise e

        partition_key = record['kinesis']['partitionKey']
        stock_state = state.get(partition_key, {
            'low_day': stock_data['low_day'],
            'high_day': stock_data['high_day'],
            'sum': 0,
            'count': 0,
            'average': 0
        })

        stock_state['low_window'] = stock_data['low_day']
        stock_state['high_window'] = stock_data['high_day']
        stock_state['sum'] += stock_data['current']
        stock_state['count'] += 1
        stock_state['average'] = stock_state['sum'] / stock_state['count']

        state[partition_key] = stock_state

    logger.info({'action': 'completed_invokation', 'state': state})
    return { 'state': state }
