--CREATE DATABASE covid-19;

\c covid_19

CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

CREATE TABLE IF NOT EXISTS covid19_ts (
  province_state TEXT,
  country_region TEXT NOT NULL,
  observation_date TIMESTAMPTZ NOT NULL,
  confirmed INTEGER DEFAULT 0,
  deaths INTEGER DEFAULT 0,
  recovered INTEGER DEFAULT 0);

CREATE TABLE IF NOT EXISTS import_covid19_ts (like covid19_ts);

ALTER TABLE covid19_ts ADD
  PRIMARY KEY(province_state, country_region, observation_date);

SELECT create_hypertable('covid19_ts', 'observation_date');

-- Continuous Aggregates 
-- we need to DROP VIEW CASCADE as there are underlying Timescale structures.
-- CREATE OR REPLACE VIEW doesn't work with Timescale's continuous aggregates

DROP VIEW confirmed_hourly CASCADE;
CREATE VIEW confirmed_hourly
WITH (timescaledb.continuous)
AS
SELECT
  country_region,
  time_bucket('1 hour', observation_date) as bucket,
  sum(confirmed) as sum,
  avg(confirmed) as avg,
  max(confirmed) as max,
  min(confirmed) as min
FROM
  covid19_ts
GROUP BY country_region, bucket;

DROP VIEW deaths_hourly CASCADE;
CREATE VIEW deaths_hourly
WITH (timescaledb.continuous)
AS
SELECT
  country_region,
  time_bucket('1 hour', observation_date) as bucket,
  sum(deaths) as sum,
  avg(deaths) as avg,
  max(deaths) as max,
  min(deaths) as min
FROM
  covid19_ts
GROUP BY country_region, bucket;

DROP VIEW recovered_hourly CASCADE;
CREATE VIEW recovered_hourly
WITH (timescaledb.continuous)
AS
SELECT
  country_region,
  time_bucket('1 hour', observation_date) as bucket,
  sum(recovered) as sum,
  avg(recovered) as avg,
  max(recovered) as max,
  min(recovered) as min
FROM
  covid19_ts
GROUP BY country_region, bucket;
