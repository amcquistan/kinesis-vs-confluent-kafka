import base64
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(events, context):
    logger.info({'events': events})

    # use only the most recent stock update if 
    # multiple arrive in same batch
    latest_prices = {}
    for evt in events:
        value = evt['payload']['value']
        key = base64.b64decode(evt['payload']['key']).decode('utf-8')
        value.update(SYMBOL=key)
        value.update(timestamp=evt['payload']['timestamp'])

        existing_price = latest_prices.get(key)
        if not existing_price or existing_price['timestamp'] < value['timestamp']:
            latest_prices[key] = value

    logger.info({'latest_prices': latest_prices})

    # assemble message for email notification
    messages = []
    for stock_highlow in latest_prices.values():
        symbol = stock_highlow['SYMBOL']
        desc = stock_highlow['CHANGE']
        price = stock_highlow['LATEST_QUOTE']
        low = stock_highlow['END_LOW']
        high = stock_highlow['END_HIGH']
        messages.append(f"{symbol} has {desc} between {low} and {high} and latest price ${price}")

    logger.info({'messages': messages})

    # send email via SNS topic
    sns = boto3.client('sns')
    msg = '\n'.join(messages)
    try:
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC'],
            Message=msg,
            Subject='Kafka Lambda Stocks Stream Alert'
        )
    except Exception as e:
        logger.error({
            'error': 'failed_sns_publish',
            'exception': str(e),
            'topic': os.environ['SNS_TOPIC'],
            'message': msg
        })
        raise e
