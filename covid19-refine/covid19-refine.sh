#!/bin/bash 
# author: Joel Natividad, datHere.com

FILES=COVID-19/csse_covid_19_data/csse_covid_19_daily_reports/*.csv
export PGUSER=covid19_user
export PGPASSWORD=your-password-here
export PGDATABASE=covid_19
export PGHOST=your-hostname-here
export PGPORT=5432
GEOCODE_EARTH_API_KEY=your-apikey-here

start_time="$(date -u +%s)"

echo "Checking latest data from JHU... "
git submodule update --remote 

mkdir -p ~/.covid-19
if [ -f ~/.covid-19/covidrefinelastrun ]; then 
  covidrefinelastrun=$(<~/.covid-19/covidrefinelastrun)
  last_modified="$(date -r workdir/location-lookup/input/time_series_19-covid-Confirmed.csv -u "+%Y-%m-%d %H:%M:%S")"
  if [[ $last_modified < $covidrefinelastrun ]]; then
    echo "ABORTED. JHU's COVID-19 data has not been modified since the last run."
    echo -e "JHU data last modified: $last_modified\nLast Run: $covidrefinelastrun"
    exit
  fi
fi

if [[ $GEOCODE_EARTH_API_KEY == 'your-apikey-here' ]]; then
  echo "ABORTED. You need to specify a Geocode.earth API key. Signup for a free trial at https://geocode.earth"
  exit
fi

echo ">>> Starting OpenRefine Automation!\n  Creating geocoded location lookup..."
mkdir -p workdir/location-lookup/transform
mkdir -p workdir/location-lookup/output
sed "s/GEOCODE_EARTH_API_KEY/$GEOCODE_EARTH_API_KEY/" workdir/location-lookup/covid-19-locations-recipe.json > workdir/location-lookup/transform/lookup-recipe.json
rm -rf workdir/location-lookup/output

./openrefine-batch.sh -a workdir/location-lookup/input/ -b workdir/location-lookup/transform/ -c workdir/location-lookup/output/ -m 4096M -e csv -f csv -i projectName=location-lookup 

echo ">>> Normalizing data..." 
rm -rf workdir/normalize/output
mkdir -p workdir/normalize/output
mkdir -p workdir/normalize/input
cp ../COVID-19/csse_covid_19_data/csse_covid_19_time_series/*.csv workdir/normalize/input
./openrefine-batch.sh -a workdir/normalize/input -b workdir/normalize/transform/ -c workdir/normalize/output/ -e csv -f csv -m 4096M -X -R -d workdir/location-lookup/output/ 

echo -e -n "\n>>> Copying to database...\n  Creating geocoded location lookup table..."
psql -q -c "TRUNCATE TABLE covid19_loclookup;"
csvcut -x \
  -c loc_id,province_state,country_region,latitude,longitude,us_locality,us_state,us_county,continent,geocode-earthJSON \
    workdir/location-lookup/output/location-lookup.csv > workdir/location-lookup/location-lookup.csv
psql -c \
    "\COPY covid19_loclookup(loc_id,province_state,country_region,latitude,longitude,us_locality,us_state,us_county,continent,geocode_earth_json) \
      FROM 'workdir/location-lookup/location-lookup.csv' DELIMITER ',' CSV HEADER ;"

echo -e -n "  Populating deaths table..."
psql -q -c "TRUNCATE TABLE import_covid19_deaths;"
psql  -c \
    "\COPY import_covid19_deaths(loc_id,observation_date,observation_count) \
      FROM 'workdir/normalize/output/time_series_19-covid-Deaths.csv' DELIMITER ',' CSV HEADER;"

echo -e -n "  Populating confirmed table..."
psql -q -c "TRUNCATE TABLE import_covid19_confirmed;"
psql  -c \
    "\COPY import_covid19_confirmed(loc_id,observation_date,observation_count) \
      FROM 'workdir/normalize/output/time_series_19-covid-Confirmed.csv' DELIMITER ',' CSV HEADER;"

echo -e -n "  Populating recovered table..."
psql -q -c "TRUNCATE TABLE import_covid19_recovered;"
psql  -c \
    "\COPY import_covid19_recovered(loc_id,observation_date,observation_count) \
      FROM 'workdir/normalize/output/time_series_19-covid-Recovered.csv' DELIMITER ',' CSV HEADER;"

echo -e "  Collating normalized data... "
psql -q -c "TRUNCATE TABLE covid19_normalized_ts;"
psql -q -c "INSERT INTO covid19_normalized_ts \
      SELECT a.loc_id, a.observation_date, a.observation_count as confirmed_total, \
        b.observation_count as deaths_total, c.observation_count as recovered_total, 0, 0, 0 \
        from import_covid19_confirmed a, import_covid19_deaths b, import_covid19_recovered c \
      WHERE a.loc_id = b.loc_id and a.loc_id = c.loc_id AND \
            a.observation_date = b.observation_date AND \
            a.observation_date = c.observation_date;"

echo -e "  Deriving Daily Counts..."
psql -q -t -o /dev/null -c "select derive_daily_counts();"

echo -e -n "\nVacuuming/Analyzing database...\n"
psql -q -c "VACUUM FULL ANALYZE covid19_normalized_ts, covid19_loclookup;"
psql -t -c "SELECT count(*) || ' rows' FROM covid19_normalized_ts;"
psql -t -c "SELECT count(*) || ' locations' FROM covid19_loclookup;"

last_run="$(date -u  "+%Y-%m-%d %H:%M:%S")"
echo $last_run>~/.covid-19/covidrefinelastrun

end_time="$(date -u +%s)"
elapsed="$(($end_time-$start_time))"
echo "Run time: $elapsed seconds"
