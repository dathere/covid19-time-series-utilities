#!/bin/bash
# author: Joel Natividad, datHere.com

FILES=COVID-19/csse_covid_19_data/csse_covid_19_daily_reports/*.csv
export PGUSER=covid19_user
export PGPASSWORD=your-password-here
export PGDATABASE=covid_19
export PGHOST=your-hostname-here
export PGPORT=5432

start_time="$(date -u +%s)"

mkdir -p ~/.covid-19
lastcsvprocessed=$(<~/.covid-19/lastcsvprocessed)

echo -e -n "Checking latest data from JHU... "
git submodule update --remote 

for f in $FILES
do
  csvname="$(basename "$f")"

  if [[ "$lastcsvprocessed" > "$csvname" ]] || [[ "$lastcsvprocessed" == "$csvname" ]]; then
  	continue;
  fi

  echo -e -n "\nProcessing $csvname...\n  Checking CSV... "
  cp $f /tmp/workfile.csv
  csvclean -e UTF-8 /tmp/workfile.csv
  csvcut -x -c 1,2,3,4,5,6 /tmp/workfile_out.csv > /tmp/cleaned.csv
  psql -q -c "TRUNCATE TABLE import_covid19_ts;"

  echo -e -n "  Copying CSV... "
  psql  \
    -c "\COPY import_covid19_ts(province_state,country_region,observation_date,confirmed,deaths,recovered) \
    FROM '/tmp/cleaned.csv' DELIMITER ',' CSV HEADER FORCE NOT NULL province_state;"

  echo -e -n "  Upserting into time-series table... "
  psql -f 'upsert_covid19.sql'  
  echo $csvname > ~/.covid-19/lastcsvprocessed
done

echo -e -n "\nCreating Locations table... "
csvcut -x -c 1,2,7,8 /tmp/workfile_out.csv > /tmp/locations.csv
psql -q -c "TRUNCATE TABLE covid19_locations;"
psql  \
    -c "\COPY covid19_locations(province_state,country_region,latitude,longitude) \
    FROM '/tmp/locations.csv' DELIMITER ',' CSV HEADER FORCE NOT NULL province_state;"

echo -e -n "\nVacuuming/Analyzing database..."
psql -q -c "VACUUM FULL ANALYZE covid19_ts, import_covid19_ts, covid19_locations;"
psql -t -c "SELECT count(*) || ' rows' from covid19_ts;"

end_time="$(date -u +%s)"
elapsed="$(($end_time-$start_time))"
echo "Run time: $elapsed seconds"
