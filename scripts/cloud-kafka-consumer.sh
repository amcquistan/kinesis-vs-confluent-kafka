#!/bin/bash

kafka-console-consumer --bootstrap-server $1 --topic $2 --from-beginning \
  --consumer.config ./client.properties --max-messages 100
