# covid19-refine.sh
This script automates the creation/population of a fully normalized, non-sparse, geo-enriched version of [JHU's COVID-19 time-series data](https://github.com/CSSEGISandData/COVID-19/tree/master/csse_covid_19_data/csse_covid_19_time_series).

0. Be sure to run `schema.sql` as noted in the main README.

1. Run `openrefine-batch.sh` to initialize the environment.  It will automatically download OpenRefine and openrefine-client. You need to do this only once, and you'll only need to run `covid19-refine.sh` for future invocations.

` ./openrefine-batch.sh`

2. Modify the `covid19-refine.sh` file to add your Postgres connection parameters, and the Geocode.earth API key.

3. Run `covid19-refine.sh`.  It will automate several OpenRefine projects to normalize and enrich the latest [JHU's time-series data](https://github.com/CSSEGISandData/COVID-19/tree/master/csse_covid_19_data/csse_covid_19_time_series) and insert it into Timescale.  It will be a relatively long-running automation (6 minutes) as it will run OpenRefine in headless mode, and geographically enrich the location data to support filtering on additional facets (continent, for the US - locality, county, state).

` ./covid19-refine.sh`


4. Slice and dice the data using Postgres/Timescale! Note these tables/hypertables/continuous aggregates:

  - `covid19_loclookup`
     we assign a `loc_id` to help with joins.  We also enrich the data with continent, and for the US - locality, county and state for additional aggregrations ([sample](workdir/location-lookup/location-lookup.csv)).

```SQL
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
```

  - `covid19_normalized_ts`
  	apart from the running totals compiled by JHU, we also compute the daily incidents for any specific date/location (e.g. how many confirmed, deaths, recoveries for each day/location).  This will allow you to do aggregations for arbitrary date ranges, compute rates of confirmed/deaths/recoveries, and benchmarking across locations.

```SQL
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
```

  	There are several Timescale-powered continuous aggregates as well:

```SQL
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
```

With the continuous aggregates, you can ask questions like:

```SQL
		SELECT b.*,  province_state, country_region
		FROM confirmed_weekly b, covid19_loclookup a 
		WHERE a.loc_id = b.loc_id 
		   AND country_region = 'Mainland China'
		ORDER BY loc_id, bucket asc;
```

you can view the result [here](workdir/China-confirmed-weekly-continuous-aggregate.csv) (as of Mar 5, noon EST).
