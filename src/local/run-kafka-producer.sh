#!/bin/bash

# This script assumes you went through the setup and provisioning as described in the 
# project's README.md, specifically that you have a configs/cluster-env.json file, a
# configs/demo-client-sa-key.json file and a configs/demo-sr-key.json file


set -e

CLUSTER_FILE=configs/cluster-env.json
SA_CREDS_FILE=configs/demo-client-sa-key.json
SR_FILE=configs/demo-sr.json
SR_CREDS_FILE=configs/demo-sr-key.json

BOOTSTRAP_SERVER=$(jq -r '.endpoint' $CLUSTER_FILE)
TOPIC=stocks
KAFKA_KEY=$(jq -r '.key' $SA_CREDS_FILE)
KAFKA_SECRET=$(jq -r '.secret' $SA_CREDS_FILE)
SR_URL=$(jq -r '.endpoint_url' $SR_FILE)
SR_KEY=$(jq -r '.key' $SR_CREDS_FILE)
SR_SECRET=$(jq -r '.secret' $SR_CREDS_FILE)

./kafka_producer.py --bootstrap-server $BOOTSTRAP_SERVER \
  --topic $TOPIC \
  --kafka-key $KAFKA_KEY \
  --kafka-secret $KAFKA_SECRET \
  --sr-url $SR_URL \
  --sr-key $SR_KEY \
  --sr-secret $SR_SECRET

