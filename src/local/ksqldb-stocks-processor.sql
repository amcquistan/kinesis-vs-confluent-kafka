-- ** Multi-step application of both Tables and Streams **
-- Intermediate, in-application streams are useful for building multi-step applications.
--                .-----------------.   .-------------------.    .---------------.    .-------------------.          
--                |                 |   |                   |    |               |    |                   |        
-- stocks topic-->|  STOCKS_STREAM  |-->| STOCK_HIGHLOW_TBL |--> | STOCK_WINDOWS |--> | STOCK_HIGHLOW_CHG |--> stock_highlow_chg topic
--   (Producer)   |                 |   |                   |    |               |    |                   |      (Consumer)
--                '-----------------'   '-------------------'    '---------------'    '-------------------'       
-- STREAM: A partitioned, immutable, append-only collection that represents a series of historical facts
-- TABLE: A mutable, partitioned collection that models changes over time, specifically showing the state of thing right now

CREATE STREAM STOCKS_STREAM WITH (
    KAFKA_TOPIC='stocks',
    VALUE_FORMAT='AVRO'
);

CREATE TABLE STOCK_HIGHLOW_TBL
WITH (KAFKA_TOPIC='stock_highlow_tbl') AS
SELECT
  SYMBOL,
  LATEST_BY_OFFSET(SYMBOL) STOCK_SYMBOL,
  EARLIEST_BY_OFFSET(LOW_DAY) START_LOW,
  MIN(LOW_DAY) END_LOW,
  EARLIEST_BY_OFFSET(HIGH_DAY) START_HIGH,
  MAX(HIGH_DAY) END_HIGH,
  LATEST_BY_OFFSET(CURRENT) LATEST_QUOTE,
  CASE
    WHEN MIN(LOW_DAY) < EARLIEST_BY_OFFSET(LOW_DAY) THEN 'new low'
    WHEN MAX(HIGH_DAY) > EARLIEST_BY_OFFSET(HIGH_DAY) THEN 'new high'
    ELSE 'no change'
  END CHANGE
FROM STOCKS_STREAM
WINDOW TUMBLING ( SIZE 2 MINUTE )
GROUP BY SYMBOL
EMIT CHANGES;

CREATE STREAM STOCK_WINDOWS WITH (
  KAFKA_TOPIC='stock_highlow_tbl',
  VALUE_FORMAT='AVRO'
);

CREATE STREAM STOCK_HIGHLOW_CHG WITH (
  KAFKA_TOPIC='stock_highlow_chg',
  VALUE_FORMAT='AVRO'
) AS
SELECT *
FROM STOCK_WINDOWS s
WHERE START_LOW != END_LOW OR START_HIGH != END_HIGH
PARTITION BY STOCK_SYMBOL
EMIT CHANGES;


