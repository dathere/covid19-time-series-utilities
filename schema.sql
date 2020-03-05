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

CREATE TABLE IF NOT EXISTS covid19_locations (
  province_state TEXT,
  country_region TEXT NOT NULL,
  latitude NUMERIC NOT NULL,
  longitude NUMERIC NOT NULL,
  PRIMARY KEY (province_state, country_region));

-- OpenRefine tables

CREATE TABLE IF NOT EXISTS covid19_loclookup (
  loc_id INTEGER PRIMARY KEY,
  province_state TEXT,
  country_region TEXT NOT NULL,
  latitude NUMERIC NOT NULL,
  longitude NUMERIC NOT NULL,
  us_locality TEXT,
  us_state TEXT,
  us_county TEXT,
  continent TEXT,
  geocode_earth_json JSONB);
ALTER TABLE covid19_loclookup OWNER TO covid19_user;
CREATE INDEX IF NOT EXISTS geocode_earth_json_idx ON covid19_loclookup USING GIN (geocode_earth_json);


CREATE TABLE IF NOT EXISTS import_covid19_confirmed (
  loc_id INTEGER NOT NULL,
  observation_date TIMESTAMPTZ NOT NULL,
  observation_count INTEGER NOT NULL,
  PRIMARY KEY (loc_id, observation_date));
ALTER TABLE import_covid19_confirmed OWNER TO covid19_user;

CREATE TABLE IF NOT EXISTS import_covid19_deaths (like import_covid19_confirmed INCLUDING ALL);
ALTER TABLE import_covid19_deaths OWNER TO covid19_user;

CREATE TABLE IF NOT EXISTS import_covid19_recovered (like import_covid19_confirmed INCLUDING ALL);
ALTER TABLE import_covid19_recovered OWNER TO covid19_user;


CREATE TABLE IF NOT EXISTS covid19_normalized_ts (
  loc_id INTEGER NOT NULL,
  observation_date TIMESTAMPTZ NOT NULL,
  confirmed_total INTEGER NOT NULL DEFAULT 0,
  deaths_total INTEGER NOT NULL DEFAULT 0,
  recovered_total INTEGER NOT NULL DEFAULT 0,
  confirmed_daily INTEGER NOT NULL DEFAULT 0,
  deaths_daily INTEGER NOT NULL DEFAULT 0,
  recovered_daily INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(loc_id, observation_date));
ALTER TABLE covid19_normalized_ts OWNER TO covid19_user;

select create_hypertable('covid19_normalized_ts', 'observation_date');


-- Continuous Aggregates 
-- we need to DROP VIEW CASCADE as there are underlying Timescale structures.
-- CREATE OR REPLACE VIEW doesn't work with Timescale's continuous aggregates

DROP VIEW IF EXISTS confirmed_3days CASCADE;
CREATE VIEW confirmed_3days
WITH (timescaledb.continuous)
AS
SELECT
  loc_id,
  time_bucket('3 days', observation_date) as bucket,
  max(confirmed_total) as running_total,
  sum(confirmed_daily) as sum,
  avg(confirmed_daily) as avg,
  max(confirmed_daily) as max,
  min(confirmed_daily) as min
FROM
  covid19_normalized_ts a
GROUP BY loc_id, bucket;

DROP VIEW IF EXISTS deaths_3days CASCADE;
CREATE VIEW deaths_3days
WITH (timescaledb.continuous)
AS
SELECT
  loc_id,
  time_bucket('3 days', observation_date) as bucket,
  max(deaths_total) as running_total,
  sum(deaths_daily) as sum,
  avg(deaths_daily) as avg,
  max(deaths_daily) as max,
  min(deaths_daily) as min
FROM
  covid19_normalized_ts a
GROUP BY loc_id, bucket;

DROP VIEW IF EXISTS recovered_3days CASCADE;
CREATE VIEW recovered_3days
WITH (timescaledb.continuous)
AS
SELECT
  loc_id,
  time_bucket('3 days', observation_date) as bucket,
  max(recovered_total) as running_total,
  sum(recovered_daily) as sum,
  avg(recovered_daily) as avg,
  max(recovered_daily) as max,
  min(recovered_daily) as min
FROM
  covid19_normalized_ts a
GROUP BY loc_id, bucket;

DROP VIEW IF EXISTS confirmed_3days CASCADE;
CREATE VIEW confirmed_3days
WITH (timescaledb.continuous)
AS
SELECT
  loc_id,
  time_bucket('3 days', observation_date) as bucket,
  max(recovered_total) as running_total,
  sum(recovered_daily) as sum,
  avg(recovered_daily) as avg,
  max(recovered_daily) as max,
  min(recovered_daily) as min
FROM
  covid19_normalized_ts a
GROUP BY loc_id, bucket;

DROP VIEW IF EXISTS confirmed_weekly CASCADE;
CREATE VIEW confirmed_weekly
WITH (timescaledb.continuous)
AS
SELECT
  loc_id,
  time_bucket('7 days', observation_date) as bucket,
  max(confirmed_total) as running_total,
  sum(confirmed_daily) as sum,
  avg(confirmed_daily) as avg,
  max(confirmed_daily) as max,
  min(confirmed_daily) as min
FROM
  covid19_normalized_ts a
GROUP BY loc_id, bucket;

DROP VIEW IF EXISTS deaths_weekly CASCADE;
CREATE VIEW deaths_weekly
WITH (timescaledb.continuous)
AS
SELECT
  loc_id,
  time_bucket('7 days', observation_date) as bucket,
  max(deaths_total) as running_total,
  sum(deaths_daily) as sum,
  avg(deaths_daily) as avg,
  max(deaths_daily) as max,
  min(deaths_daily) as min
FROM
  covid19_normalized_ts a
GROUP BY loc_id, bucket;

DROP VIEW  IF EXISTS recovered_weekly CASCADE;
CREATE VIEW recovered_weekly
WITH (timescaledb.continuous)
AS
SELECT
  loc_id,
  time_bucket('7 days', observation_date) as bucket,
  max(recovered_total) as running_total,
  sum(recovered_daily) as sum,
  avg(recovered_daily) as avg,
  max(recovered_daily) as max,
  min(recovered_daily) as min
FROM
  covid19_normalized_ts a
GROUP BY loc_id, bucket;


-- function to derive dauly counts
CREATE OR REPLACE FUNCTION public.derive_daily_counts()
    RETURNS integer
    LANGUAGE 'plpgsql'
    
AS $BODY$DECLARE 
    vrowsupdated INT DEFAULT 0;
    vprevious_date TIMESTAMPTZ;
    vdeaths_daily INTEGER DEFAULT 0;
    vconfirmed_daily INTEGER DEFAULT 0;
    vrecovered_daily INTEGER DEFAULT 0;
    vprevday_deaths_total INTEGER DEFAULT 0;
    vprevday_confirmed_total INTEGER DEFAULT 0;
    vprevday_recovered_total INTEGER DEFAULT 0;
    rec_covid19   RECORD;
    rec_prior_covid19 RECORD;
  
  cur_ro_covid19 SCROLL CURSOR(ploc_id INTEGER, pobservation_date TIMESTAMPTZ)
       FOR SELECT loc_id, observation_date, confirmed_total, deaths_total, recovered_total, confirmed_daily, deaths_daily, recovered_daily
       FROM covid19_normalized_ts
       WHERE loc_id=ploc_id AND observation_date=pobservation_date;
  
    cur_covid19 CURSOR
       FOR SELECT loc_id, observation_date, confirmed_total, deaths_total, recovered_total, confirmed_daily, deaths_daily, recovered_daily
       FROM covid19_normalized_ts
       ORDER BY loc_id, observation_date ASC FOR UPDATE;
BEGIN

   vrowsupdated = 0;
   OPEN cur_covid19;
   
   LOOP
      FETCH cur_covid19 INTO rec_covid19;
      -- exit when no more row to fetch
      EXIT WHEN NOT FOUND;

      vprevious_date = rec_covid19.observation_date - interval '1 day';

      -- get previous day's running total
      OPEN cur_ro_covid19(rec_covid19.loc_id, vprevious_date);
      FETCH cur_ro_covid19 INTO rec_prior_covid19;
    
      IF NOT FOUND THEN
        vprevday_deaths_total = 0;
        vprevday_confirmed_total = 0;
        vprevday_recovered_total = 0;
      ELSE
        vprevday_deaths_total = rec_prior_covid19.deaths_total;
        vprevday_confirmed_total = rec_prior_covid19.confirmed_total;
        vprevday_recovered_total = rec_prior_covid19.recovered_total;
      END IF;
      CLOSE cur_ro_covid19;
   
      vdeaths_daily = rec_covid19.deaths_total - vprevday_deaths_total;
      vconfirmed_daily = rec_covid19.confirmed_total - vprevday_confirmed_total;
      vrecovered_daily = rec_covid19.recovered_total - vprevday_recovered_total; 

      UPDATE covid19_normalized_ts SET deaths_daily=vdeaths_daily,
          confirmed_daily=vconfirmed_daily, recovered_daily=vrecovered_daily
        WHERE CURRENT OF cur_covid19;

      vrowsupdated = vrowsupdated + 1;
   END LOOP;
  
   -- Close the cursor
   CLOSE cur_covid19;
   RETURN vrowsupdated;
END;$BODY$;

ALTER FUNCTION public.derive_daily_counts() OWNER TO covid19_user;