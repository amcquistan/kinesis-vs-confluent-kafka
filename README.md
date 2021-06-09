# sam-stock-streaming-kinesis-kafka

This is an AWS SAM project for experimenting with and evaluating the stream processing technologies AWS Kinesis along with Confluent Kafka (specifically their Managed Cloud Offering).

Use Case for Stream Processing Evaluation:

* live stock quotes are sourced from Yahoo Finance API and streamed into each technology's storage system
* processing functionalities are employed on each technologies underlying stream of stock quote events to calculate two minute windowed operations
  * average stock quote price over subsequent two minutes windows are calculated for each company
  * any two minute window containing a new daily high or daily low are filtered out and fed into secondary streams which signify a stream of events comsumer applications can subscribe to and react when such targeted newly daily low / high stocks are encountered

### Demo Project Setup: Kafka Cluster, Schema Registry and ksqlDB

The Confluent Cloud basic Kafka cluster, service account with API Key/Secret pair, and stocks Kafka topic should be provisioned first before any of the AWS Resources. This is because the Kafka cluster bootstrap server URL as well as the service account API Key/Secret pair are dependencies of the AWS Lambda based Kafka Producer. 

Below are the steps / commands required to provision [Confluent Cloud using the ccloud CLI](https://docs.confluent.io/ccloud-cli/current/install.html) (version 1.33.0)

1) Login to Confluent Cloud

```
ccloud login --prompt
```

2) Create an environment to encapsulate the resources

```
mkdir configs
ENV_FILE=configs/confluent-env.json
ccloud environment create aws-kinesis-vs-confluent-kafka -o json > $ENV_FILE
ENV_ID=$(jq -r '.id' $ENV_FILE)
ccloud environment use $ENV_ID
```

3) Create Kafka Cluster

```
CLUSTER_FILE=configs/cluster-env.json
ccloud kafka cluster create demo-cluster --cloud aws --region us-east-2 --type basic -o json > $CLUSTER_FILE
CLUSTER_ID=$(jq -r '.id' $CLUSTER_FILE)
ccloud kafka cluster use $CLUSTER_ID
```

The configs in the output file configs/cluster-env.json has a endpoint field that needs  to be used with for the AWS Lambda based producer client

4) Create a Kafka Topic named stocks

```
ccloud kafka topic create stocks --partitions 3 --cluster $CLUSTER_ID
```

You may get an error if you try to run this command too soon after creating the Kafka Cluster before it can properly finish provisioning. Just wait a few minutes and try it again.

```
$ ccloud kafka topic create stocks --partitions 3 --cluster $CLUSTER_ID
Error: Kafka cluster "lkc-dxrpo" not ready

Suggestions:
    It may take up to 5 minutes for a recently created Kafka cluster to be ready.
```

5) Create a service account for Kafka Clients

```
SVC_ACCT_FILE=configs/demo-client-sa.json
ccloud service-account create demo-client-sa --description "For Kafka Clients" -o json > $SVC_ACCT_FILE
SVC_ACCT_ID=$(jq -r '.id' $SVC_ACCT_FILE)
```

Also set ACLs for the service account to produce to and consume from the stocks topic.

```
ccloud kafka acl create --allow --service-account $SVC_ACCT_ID --cluster $CLUSTER_ID --operation WRITE --topic 'stocks'
ccloud kafka acl create --allow --service-account $SVC_ACCT_ID --cluster $CLUSTER_ID --operation READ --topic 'stocks'
ccloud kafka acl create --allow --service-account $SVC_ACCT_ID --cluster $CLUSTER_ID --operation DESCRIBE --topic 'stocks'
ccloud kafka acl create --allow --service-account $SVC_ACCT_ID --cluster $CLUSTER_ID --operation DESCRIBE_CONFIGS --topic 'stocks'
ccloud kafka acl create --allow --service-account $SVC_ACCT_ID --cluster $CLUSTER_ID --operation READ --consumer-group '*'
```

6) Create Service Account API Key/Secret Pair for Kafka Clients

```
SVC_ACCT_KEY_FILE=configs/demo-client-sa-key.json
ccloud api-key create --service-account $SVC_ACCT_ID --resource $CLUSTER_ID -o json > $SVC_ACCT_KEY_FILE
```

The key and secret saved to the configs/demo-client-sa-keys.json is what will be needed for the AWS Lambda based producer client.

7) Enable the Confluent Schema Registry

```
SR_FILE=configs/demo-sr.json
ccloud schema-registry cluster enable --cloud aws --geo us -o json > $SR_FILE
SR_ID=$(jq -r '.id' $SR_FILE)
```

8) Create credentials for the Schema Registry

```
SR_KEY_FILE=configs/demo-sr-key.json
ccloud api-key create --service-account $SVC_ACCT_ID --resource $SR_ID -o json > $SR_KEY_FILE
```

The API Key/Secret is needed for clients using Schema Registry

9) Create a Service Account to Run the ksqlDB App Under

Create Service Account

```
KSQL_SA_FILE=configs/ksqldb-sa.json
ccloud service-account create ksql-demo-sa --description "For KSQL Demo" -o json > $KSQL_SA_FILE
KSQL_SA_ID=$(jq -r '.id' $KSQL_SA_FILE)
```

Assign ACLs to Service Account

```
ccloud kafka acl create --allow --service-account $KSQL_SA_ID --operation READ --operation WRITE --topic '*'
ccloud kafka acl create --allow --service-account $KSQL_SA_ID --operation WRITE --operation WRITE --topic '*'
ccloud kafka acl create --allow --service-account $KSQL_SA_ID --operation CREATE --cluster-scope
```

Create API Key/Secret for KSQL Service Account

```
KSQL_SA_KEY_FILE=configs/ksql-sa-key.json
ccloud api-key create --service-account $KSQL_SA_ID --resource $CLUSTER_ID -o json > $KSQL_SA_KEY_FILE
KSQL_SA_KEY=$(jq -r '.key' $KSQL_SA_KEY_FILE)
KSQL_SA_SECRET=$(jq -r '.secret' $KSQL_SA_KEY_FILE)
```

10) Create a ksqlDB Application

```
KSQL_FILE=configs/ksql.json
ccloud ksql app create ksql-stocks-demo --api-key $KSQL_SA_KEY --api-secret $KSQL_SA_SECRET -o json > $KSQL_FILE
KSQL_ID=$(jq -r '.id' $KSQL_FILE)
ccloud ksql app configure-acls $KSQL_ID '*'
```

11) Create API Key/Secret pair for accessing KSQL via ksqldb-cli client

```
KSQLCLI_CREDS_FILE=configs/ksql-creds.json
ccloud api-key create --resource $KSQL_ID -o json > $KSQLCLI_CREDS_FILE
ccloud ksql app configure-acls $KSQL_ID '*' ALL
```

These API Key/Secret creds are needed to connect to ksqlDB from ksqldb-cli 


### Provisioning AWS Resources: Lambda, SNS, EventBridge, S3

Most of the AWS resources being used for this comparison project are defined in the AWS SAM/CloudFormation template.yaml file at the root of this project. However, there are a few dependencies that need passed to the SAM/CloudFormation template as parameters which are created during the Confluent Cloud Provisioning in the earlier section.

In the same directory as the template.yaml file run.

```
sam build --use-container
```

Deploy with a command similar to the following while substituting your profile and region where appropriate as well as the other values the command interactively asks you for.

```
sam deploy --guided --stack-name kinesis-vs-confluent-kafka-comparison \
  --profile intrado_dev --region us-east-2 \
  --capabilities CAPABILITY_NAMED_IAM
```


### Provisioning Confluent Cloud Continued: Lambda Sink and S3 Sink Connectors

Since it is desired to have the output from the processed stocks stream (new daily high/low stocks over 2 minute windows) pushed to AWS Lambda as an event driven consumer as well as push processed and raw data to AWS S3 for later batch analytics it was required to provision the previous AWS resources first.

1) Create API Key / Secret pair for S3 Sink Connector

```
S3_SINK_KEY_FILE=configs/s3-sink-key.json
ccloud api-key create --resource $CLUSTER_ID -o json > $S3_SINK_KEY_FILE
```

The Key and Secret will need to be used when launching the S3 Sink Connector


2) Lauanch the S3 Sink Connector

Create a JSON based config file for the Connector with the following. The output of the sam deploy command will give you the credentials and function name for AWS (you can also find them in the output tab of the CloudFormation UI). Mine is configs/s3-sink-connector.json

```
{
   "name" : "confluent-s3-sink",
   "connector.class": "S3_SINK",
   "kafka.api.key": "<my-kafka-api-key>",
   "kafka.api.secret" : "<my-kafka-api-secret>",
   "aws.access.key.id" : "<my-aws-access-key>",
   "aws.secret.access.key": "<my-aws-access-key-secret>",
   "input.data.format": "AVRO",
   "output.data.format": "JSON",
   "compression.codec": "JSON - gzip",
   "s3.compression.level": "6",
   "s3.bucket.name": "<my-bucket-name>",
   "time.interval" : "HOURLY",
   "flush.size": "1000",
   "tasks.max" : "1",
   "topics": "stocks",
   "topics.dir": "stocks-raw-kafka-stream"
}
```

The following ccloud command launches the connector

```
ccloud connector create --config configs/s3-sink-connector.json --cluster $CLUSTER_ID
```

3) Launch the kqlDB Processing Queries

Parse connection params

```
KSQL_ENDPOINT=$(jq -r '.endpoint' $KSQL_FILE)
KSQL_KEY=$(jq -r '.key' $KSQLCLI_CREDS_FILE)
KSQL_SECRET=$(jq -r '.secret' $KSQLCLI_CREDS_FILE)
```

Create connection.

```
ksql -u $KSQL_KEY -p $KSQL_SECRET $KSQL_ENDPOINT
```

Run the queries top to bottom in this Shell found in src/local/stocks-processor.ksql

4) Create API Keys for Lambda Sink

```
LAMBDA_KEY_FILE=configs/s3-sink-key.json
ccloud api-key create --resource $CLUSTER_ID -o json > $LAMBDA_SA_KEY_FILE
```

Use this Confluent API Key/Secret pair to launch the Lambda Sink Connector

5) Launch the Lambda Sink Connector

Create a JSON based config file for the Connector with the following. The output of the sam deploy command will give you the credentials and function name for AWS (you can also find them in the output tab of the CloudFormation UI). Mine is named (or placed) in configs/lambda-sink-connector.json

```
{
   "name": "stocks-highlow-lambda-sink",
	"connector.class": "LambdaSink",
	"input.data.format": "AVRO",
   "kafka.api.key": "YOUR-SINK-KEY",
   "kafka.api.secret": "YOUR-SINK-SECRET",
	"aws.access.key.id": "YOUR-KEY",
	"aws.secret.access.key": "YOUR-SECRET",
	"aws.lambda.function.name": "YOUR-FUNCTION-NAME",
	"aws.lambda.invocation.type": "async",
	"tasks.max": "1",
	"topics": "stock_highlow_chg"
}
```

Then run the following to launch it.

```
LAMBDA_SINK_FILE=configs/lambda-sink.json
ccloud connector create --config configs/lambda-sink-connector.json --cluster $CLUSTER_ID -o json > $LAMBDA_SINK_FILE
```

### 