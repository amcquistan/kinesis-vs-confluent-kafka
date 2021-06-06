#!/bin/bash

set -eE -o functrace

###########################################################
# Parse and validate config file passed in as argument
###########################################################

CONFIG_FILE=$1

if [[ ! -f $CONFIG_FILE ]]
then
  echo "First argument must be a config file in JSON"
  exit 1
fi

if [[ ! -f ccloud_library.sh ]]
then
  wget -O ccloud_library.sh https://raw.githubusercontent.com/confluentinc/examples/latest/utils/ccloud_library.sh
fi

source ./ccloud_library.sh

ccloud::validate_version_ccloud_cli $CCLOUD_MIN_VERSION || exit 1
ccloud::validate_logged_in_ccloud_cli || exit 1


ENV_NAME=$(jq -r '.environment' $CONFIG_FILE)

if [[ $? != 0 || -z $ENV_NAME ]]
then
  echo "config file $CONFIG_FILE is missing required field [environment]"
  exit 1
fi

CLUSTER_NAME=$(jq -r '.cluster' $CONFIG_FILE)
if [[ $? != 0 || -z $CLUSTER_NAME ]]
then
  echo "Config file $CONFIG_FILE missing required field [cluster]"
  exit 1
fi

CLUSTER_REGION=$(jq -r '.cluster_region' $CONFIG_FILE)
if [[ $? != 0 || -z $CLUSTER_REGION ]]
then
  echo "Config file $CONFIG_FILE missing required field [cluster_region]"
  exit 1
fi

CLUSTER_TYPE=$(jq -r '.cluster_type' $CONFIG_FILE)
if [[ $? != 0 || -z $CLUSTER_TYPE ]]
then
  echo "Config file $CONFIG_FILE missing required field [cluster_type]"
  exit 1
fi

CLUSTER_SVC_ACCT_NAME=$(jq -r '.service_account' $CONFIG_FILE)
if [[ $? != 0 || -z $CLUSTER_SVC_ACCT_NAME ]]
then
  echo "Config file $CONFIG_FILE missing required field [service_account]"
  exit 1
fi

TOPIC_NAME=$(jq -r '.topic' $CONFIG_FILE)
if [[ $? != 0 || -z $TOPIC_NAME ]]
then
  echo "Config file $CONFIG_FILE missing required field [topic]"
  exit 1
fi

TOPIC_PARTITIONS=$(jq -r '.topic_partitions' $CONFIG_FILE)
if [[ $? != 0 || -z $TOPIC_PARTITIONS ]]
then
  echo "Config file $CONFIG_FILE missing required field [topic_partitions]"
  exit 1
fi

TOPIC_REPLICATION=$(jq -r '.topic_replication' $CONFIG_FILE)
if [[ $? != 0 || -z $TOPIC_REPLICATION ]]
then
  echo "Config file $CONFIG_FILE missing required field [topic_replication]"
  exit 1
fi

KSQL_APP_NAME=$(jq -r '.ksql_app' $CONFIG_FILE)
if [[ $? != 0 || -z $KSQL_APP_NAME ]]
then
  echo "Config file $CONFIG_FILE missing required field [ksql_app]"
  exit 1
fi

###########################################################
# Get or Create Confluent Cloud Environment for Working In
###########################################################

ENV_METADATA_FILE=$ENV_NAME-env-metadata.json
ccloud environment create $ENV_NAME --output json > $ENV_METADATA_FILE
if [[ $? != 0 ]]
then
  echo "Failed to create environment $ENV_NAME"
  exit 1
# else
#   echo "created environment"
fi
ENV_ID=$(jq -r '.id' $ENV_METADATA_FILE)


echo ""
echo "================================================================================="
echo "Confluent Cloud Environment"
echo "Environment Name: $ENV_NAME"
echo "Environment ID: $ENV_ID"
echo "Environment Metadata: $ENV_METADATA_FILE"
echo ""
ccloud environment use $ENV_ID


#############################################################
# Get or Create Confluent Cloud Kafka Cluster for Working In
#############################################################

CLUSTER_METADATA_FILE=$ENV_NAME-$CLUSTER_NAME-cluster-metadata.json
ccloud kafka cluster create $CLUSTER_NAME --cloud aws --type $CLUSTER_TYPE --region $CLUSTER_REGION --output json > $CLUSTER_METADATA_FILE
if [[ $? != 0 ]]
then
  echo "Failed to create cluster"
  exit 1
# else
#   echo "created cluster"
fi

CLUSTER_ID=$(jq -r '.id' $CLUSTER_METADATA_FILE)
ccloud kafka cluster use $CLUSTER_ID

CLUSTER_USER_KEY_FILE=$ENV_NAME-$CLUSTER_NAME-api-key.json
ccloud api-key create --description "$CLUSTER_NAME user credentials" --resource $CLUSTER_ID --output json > $CLUSTER_USER_KEY_FILE
if [[ $? != 0 ]]
then
  echo "Failed to create user api key"
  exit 1
# else
  # echo "created user api key"
fi

CLUSTER_KEY=$(jq -r ".key" $CLUSTER_USER_KEY_FILE)
ccloud api-key use $CLUSTER_KEY --resource $CLUSTER_ID

CLUSTER_SVC_ACCT_FILE=$ENV_NAME-$CLUSTER_SVC_ACCT_NAME-svc-account.json
DESC="$ENV_NAME cluster $CLUSTER_NAME service account"
ccloud service-account create $CLUSTER_SVC_ACCT_NAME --description "$DESC" --output json > $CLUSTER_SVC_ACCT_FILE
if [[ $? != 0 ]]
then
  echo "Failed to create cluster service account"
  exit 1
# else
  # echo "created cluster service account"
fi
CLUSTER_SVC_ACCT_ID=$(jq -r '.id' $CLUSTER_SVC_ACCT_FILE)

CLUSTER_SVC_ACCT_KEY_FILE=$ENV_NAME-$CLUSTER_SVC_ACCT_NAME-svc-account-key.json
ccloud api-key create --service-account $CLUSTER_SVC_ACCT_ID --resource $CLUSTER_ID --output json > $CLUSTER_SVC_ACCT_KEY_FILE
if [[ $? != 0 ]]
then
  echo "Failed to create cluster service account api key"
  exit 1
# else
  # echo "created service account api key"
fi

echo "Verifying kafka cluster is ready"
sleep 30
MAX_WAIT=720
ccloud::retry $MAX_WAIT ccloud::validate_ccloud_cluster_ready || exit 1
sleep 30

CLUSTER_SVC_ACCT_KEY=$(jq -r '.key' $CLUSTER_SVC_ACCT_KEY_FILE)
CLUSTER_SVC_ACCT_SECRET=$(jq -r '.secret' $CLUSTER_SVC_ACCT_KEY_FILE)

ccloud::create_acls_all_resources_full_access $CLUSTER_SVC_ACCT_ID

BOOTSTRAP_SERVER=$(jq -r '.endpoint' $CLUSTER_METADATA_FILE | sed "s|SASL_SSL://||g")
echo "bootstrap.servers=$BOOTSTRAP_SERVER" > client.properties
echo "ssl.endpoint.identification.algorithm=https" >> client.properties
echo "security.protocol=SASL_SSL" >> client.properties
echo "sasl.mechanism=PLAIN" >> client.properties
echo "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$CLUSTER_SVC_ACCT_KEY\" password=\"$CLUSTER_SVC_ACCT_SECRET\";" >> client.properties

echo ""
echo "================================================================================="
echo "Confluent Cloud Kafka Cluster"
echo "Cluster Name: $CLUSTER_NAME"
echo "Cluster ID: $CLUSTER_ID"
echo "Cluster Service Acct Key: $CLUSTER_SVC_ACCT_KEY"
echo "Cluster Metadata: $CLUSTER_METADATA_FILE"
echo "Cluser User Key: $CLUSTER_USER_KEY_FILE"
echo "Cluster Service Account Metadata: $CLUSTER_SVC_ACCT_FILE"
echo "Cluster service account key: $CLUSTER_SVC_ACCT_KEY_FILE"
echo ""

ccloud kafka acl list --service-account $CLUSTER_SVC_ACCT_ID --cluster $CLUSTER_ID


#############################################################
# Get or Create Confluent Cloud ksqlDB Cluster for Working In
#############################################################

KSQL_METADATA_FILE=$ENV_NAME-$CLUSTER_NAME-ksql-metadata.json
ccloud ksql app create $KSQL_APP_NAME --cluster $CLUSTER_ID --api-key $CLUSTER_SVC_ACCT_KEY --api-secret $CLUSTER_SVC_ACCT_SECRET --output json > $KSQL_METADATA_FILE
if [[ $? != 0 ]]
then 
  echo "Failed to create KSQL Application"
  exit 1
# else
#   echo "created ksqlDB application"
fi
KSQL_APP_ID=$(jq -r '.id' $KSQL_METADATA_FILE)
ccloud ksql app configure-acls $KSQL_APP_ID


echo ""
echo "================================================================================="
echo "Confluent Cloud KSQL App"
echo "KSQL App Name: $KSQL_APP_NAME"
echo "KSQL App ID: $KSQL_APP_ID"
echo "Cluster ksqlDB App metadata: $KSQL_METADATA_FILE"

# Connect to ksqlDB server with ksql CLI
# docker run --rm -it confluentinc/ksqldb-cli:0.18.0 ksql \
#        -u $KSQL_API_KEY \
#        -p $KSQL_API_SECRET \
#        "$KSQL_ENDPOINT"

#############################################################
# Create Kafka Topic for Working In
#############################################################

sleep 20

ccloud kafka topic create $TOPIC_NAME --if-not-exists --partitions $TOPIC_PARTITIONS \
  --cluster $CLUSTER_ID --config replication.factor=$TOPIC_REPLICATION

