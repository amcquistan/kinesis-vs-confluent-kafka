#!/bin/bash

if [[ -z $AWS_PROFILE ]]
then
  AWS_PROFILE=default
fi

if [[ -z $AWS_REGION ]]
then
  AWS_REGION=us-east-2
fi

if [[ -z $CC_CLIENT_KEY ]]
then
  echo "Missing Confluent Client Key variable CC_CLIENT_KEY"
  exit 1
fi

if [[ -z $CC_CLIENT_SECRET ]]
then
  echo "Missing Confluent Client Secret variable CC_CLIENT_SECRET"
  exit 1
fi

set -x

aws ssm put-parameter --overwrite --name /confluent/client/key \
  --value $CC_CLIENT_KEY --profile $AWS_PROFILE --region $AWS_REGION

aws ssm put-parameter --overwrite --name /confluent/client/secret \
  --value $CC_CLIENT_SECRET --profile $AWS_PROFILE --region $AWS_REGION
