#!/bin/bash

set -eE functrace

echo "Available Environments"
echo "================================================================="
ccloud environment list

read -p "Enter Environment ID: " ENV_ID
echo ""

ccloud environment use $ENV_ID


echo "Available Service accounts"
echo "================================================================="
ccloud service-account list

read -p "Enter Service Account ID: " SERVICE_ACCOUNT_ID
echo ""


echo "Available Kafka Clusters"
echo "================================================================="
ccloud kafka cluster list --environment $ENV_ID

read -p "Enter Kafka Cluster ID: " CLUSTER_ID
echo ""

ccloud kafka cluster use $CLUSTER_ID


echo "Available ksqlDB Applications"
echo "================================================================="
ccloud ksql app list --environment $ENV_ID

read -p "Enter ksqlDB App ID: " KSQL_APP_ID
echo ""

CLUSTER_SVC_ACCT_KEY_FILE=existing-kafka-cluster-sa-creds.json
ccloud api-key create --service-account $SERVICE_ACCOUNT_ID --resource $CLUSTER_ID --output json > $CLUSTER_SVC_ACCT_KEY_FILE

CLUSTER_SVC_ACCT_KEY=$(jq -r '.key' $CLUSTER_SVC_ACCT_KEY_FILE)
CLUSTER_SVC_ACCT_SECRET=$(jq -r '.secret' $CLUSTER_SVC_ACCT_KEY_FILE)
BOOTSTRAP_SERVER=$(ccloud kafka cluster describe $CLUSTER_ID --output json | jq -r '.endpoint' | sed "s|SASL_SSL://||g")

CLIENT_CONFIG=existing-client.properties
echo "bootstrap.servers=$BOOTSTRAP_SERVER" > $CLIENT_CONFIG
echo "ssl.endpoint.identification.algorithm=https" >> $CLIENT_CONFIG
echo "security.protocol=SASL_SSL" >> $CLIENT_CONFIG
echo "sasl.mechanism=PLAIN" >> $CLIENT_CONFIG
echo "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$CLUSTER_SVC_ACCT_KEY\" password=\"$CLUSTER_SVC_ACCT_SECRET\";" >> $CLIENT_CONFIG


ccloud api-key create --service-account $SERVICE_ACCOUNT_ID --resource $KSQL_APP_ID --output json > existing-ksql-app-sa-creds.json






