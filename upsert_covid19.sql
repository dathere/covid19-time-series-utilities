INSERT INTO covid19_ts (
    province_state, 
    country_region, 
    observation_date,
    confirmed,
    deaths,
    recovered)
  SELECT
    province_state,
    country_region,
    observation_date,
    confirmed,
    deaths,
    recovered
  FROM import_covid19_ts 
ON CONFLICT(province_state, country_region, observation_date) DO UPDATE SET
  confirmed          = EXCLUDED.confirmed,
  deaths             = EXCLUDED.deaths,
  recovered          = EXCLUDED.recovered;
