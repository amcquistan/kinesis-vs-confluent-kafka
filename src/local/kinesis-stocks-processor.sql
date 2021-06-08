
-- ** Multi-step application **
-- Intermediate, in-application streams are useful for building multi-step applications.
 
--          .-----------------------.   .--------------------.                  
--          |                       |   |                    |                  
-- Source-->| STOCKS_WINDOWS_STREAM |-->| STOCKS_HIGHLOW_CHG |-->Destination
--          |                       |   |                    |              
--          '-----------------------'   '--------------------'               
-- STREAM (in-application): a continuously updated entity that you can SELECT from and INSERT into like a TABLE
-- PUMP: an entity used to continuously 'SELECT ... FROM' a source STREAM, and INSERT SQL results into an output STREAM
 

CREATE OR REPLACE STREAM "STOCKS_WINDOWS_STREAM" (
    "SYMBOL"        VARCHAR(4),
    "START_LOW"     REAL,
    "END_LOW"       REAL,
    "START_HIGH"    REAL,
    "END_HIGH"      REAL,
    "LATEST_QUOTE"  REAL,
    "CHANGE"        VARCHAR(10)
);

CREATE OR REPLACE PUMP "STOCKS_WINDOWS_PUMP" AS
INSERT INTO "STOCKS_WINDOWS_STREAM"
SELECT STREAM 
    "SOURCE_SQL_STREAM_001"."symbol" AS "SYMBOL",
    FIRST_VALUE("SOURCE_SQL_STREAM_001"."low_day") AS "START_LOW",
    MIN("SOURCE_SQL_STREAM_001"."low_day") AS "END_LOW",
    FIRST_VALUE("SOURCE_SQL_STREAM_001"."high_day") AS "START_HIGH",
    MAX("SOURCE_SQL_STREAM_001"."high_day") AS "END_HIGH",
    LAST_VALUE("SOURCE_SQL_STREAM_001"."COL_current") AS "LATEST_QUOTE",
    CASE
      WHEN MIN("SOURCE_SQL_STREAM_001"."low_day") < FIRST_VALUE("SOURCE_SQL_STREAM_001"."low_day") THEN 'new low'
      WHEN MAX("SOURCE_SQL_STREAM_001"."high_day") > FIRST_VALUE("SOURCE_SQL_STREAM_001"."high_day") THEN 'new high'
      ELSE 'no change'
    END "CHANGE"
FROM "SOURCE_SQL_STREAM_001"
GROUP BY "SOURCE_SQL_STREAM_001"."symbol",
  STEP("SOURCE_SQL_STREAM_001"."ROWTIME" BY INTERVAL '2' MINUTE);


CREATE OR REPLACE STREAM "STOCKS_HIGHLOW_CHG" (
    "SYMBOL"        VARCHAR(4),
    "START_LOW"     REAL,
    "END_LOW"       REAL,
    "START_HIGH"    REAL,
    "END_HIGH"      REAL,
    "LATEST_QUOTE"  REAL,
    "CHANGE"        VARCHAR(10)
);

CREATE OR REPLACE PUMP "STOCK_HIGHLOW_PUMP" AS
INSERT INTO "STOCKS_HIGHLOW_CHG"
SELECT 
    "SYMBOL",
    "START_LOW",
    "END_LOW",
    "START_HIGH",
    "END_HIGH",
    "LATEST_QUOTE",
    "CHANGE"
FROM "STOCKS_WINDOWS_STREAM"
WHERE "STOCKS_WINDOWS_STREAM"."START_LOW" != "STOCKS_WINDOWS_STREAM"."END_LOW"
  OR "STOCKS_WINDOWS_STREAM"."START_HIGH" != "STOCKS_WINDOWS_STREAM"."END_HIGH";
