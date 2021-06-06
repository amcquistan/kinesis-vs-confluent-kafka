#!/bin/bash

if [[ -f ksqldb-api-key.json ]]
then
  # parse file key and secret into CC_KEY and CC_SECRET vars
else

  if [[ -z $CC_KEY ]]
  then
    echo "Missing Confluent Cloud Key variable CC_KEY"
    exit 1
  fi

  if [[ -z $CC_SECRET ]]
  then
    echo "Missing Confluent Cloud Secret variable: CC_SECRET"
    exit 1
  fi

  if [[ -z $KSQL_SERVER ]]
  then
    echo "Missing KSQL Server URL variable: KSQL_SERVER"
  fi

fi

ksql -u $CC_KEY -p $CC_SECRET $KSQL_SERVER
