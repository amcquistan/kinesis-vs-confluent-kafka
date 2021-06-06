# sam-stock-streaming-kinesis-kafka

This is an AWS SAM project for experimenting with and evaluating the stream processing technologies AWS Kinesis along with Confluent Kafka (specifically their Managed Cloud Offering).

Use Case for Stream Processing Evaluation:

* live stock quotes are sourced from Yahoo Finance API and streamed into each technology's storage system
* processing functionalities are employed on each technologies underlying stream of stock quote events to calculate two minute windowed operations
  * average stock quote price over subsequent two minutes windows are calculated for each company
  * any two minute window containing a new daily high or daily low are filtered out and fed into secondary streams which signify a stream of events comsumer applications can subscribe to and react when such targeted newly daily low / high stocks are encountered



