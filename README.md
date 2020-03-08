# COVID-19 - time-series utilities

This repo contains several utilities for wrangling COVID-19 data from the [John Hopkins University COVID-19 repository](https://github.com/CSSEGISandData/COVID-19). 

## Requirements
* A working instance of [TimescaleDB](https://docs.timescale.com) in PostgreSQL v10+
* [csvkit](https://csvkit.readthedocs.io/en/latest/)
* [git](https://git-scm.com/)
* Unix/Linux operating system with bash 
* for OpenRefine time-series automation
  - [OpenRefine](http://openrefine.org) - installed automatically
  - [openrefine-batch](https://github.com/opencultureconsulting/openrefine-batch) - included
  - a [Geocode.earth](https://geocode.earth) API key - [install](https://github.com/pelias/pelias) or [free trial](https://geocode.earth/invite/request?referrer=datHere). Used to enrich geographic data.
* [Docker](https://docs.docker.com/compose/install/) with docker-compose in case you want to run it in containers (optional)

## Cloning
A note on cloning this repo, since the COVID19 directory is a git submodule:

* after cloning, you must initiate the submodule. In the top level directory for the project, run `git submodule init` and `git submodule update` to clone the JHU Repo as a submodule 

## Content
The files in this directory and how they're used:

* `covid-19_ingest.sh`: script that converts the JHU COVID-19 [daily-report data](https://github.com/CSSEGISandData/COVID-19/tree/master/csse_covid_19_data/csse_covid_19_daily_reports) to a time-series database using TimescaleDB.
* `covid-refine`:   OpenRefine automation script that converts JHU COVID-19 [time-series data](https://github.com/CSSEGISandData/COVID-19/tree/master/csse_covid_19_data/csse_covid_19_time_series) into a normalized, enriched format and uploads it to TimescaleDB. 
* `schema.sql`: Data definition (DDL) to create the necessary tables & hypertables.
* `environment`: Default environment values used in Docker containers.

## Using the Timescale covid19-ingest script
1. Create a TimescaleDB instance - [download](https://docs.timescale.com/latest/getting-started/installation) or [signup](https://www.timescale.com/cloud-signup)
2. Create a database named `covid_19`, and an application user `covid_19_user`

```
  psql
  create database covid_19;
  create user covid_19_user WITH PASSWORD 'your-password-here';
  alter database covid_19 OWNER TO covid_19_user;
  \quit
```

3. Run `schema.sql` as the `covid_19_user`. VACUUM/ANALYZE require owner privs 

   `psql -U covid_19_user -h <the.server.hostname> -f schema.sql covid_19`
   
   
4. Install csvkit

    - Ubuntu: `sudo apt-get install csvkit`
    - MacOS: Using [homebrew](https://brew.sh/) run `brew install csvkit`

5. Using a text editor, replace the environment variables for `PGHOST`, `PGUSER` and `PGPASSWORD` in `covid-19_ingest.sh`

6. Run the script 

   `bash covid-19_ingest.sh`

7. (OPTIONAL) add shell script to crontab to run daily

8. Be able to slice-and-dice the data using the full power of PostgreSQL along with Timescale's time-series capabilities!

## Using COVIDrefine 
See the detailed [README](covid19-refine/).

## Using docker-compose
1. Remember initiate the submodule, run `git submodule init`
2. Run `docker-compose build`
3. Run `docker-compose up`
4. That's all. You can go to [Swagger](http://localhost:8080) or [PostgREST](http://localhost:3000)

## NOTES
 - the JHU COVID-19 repository is a git submodule. This was done to automate getting the latest data from their repo.
 - the script will only work in \*nix environment (Linux, Unix, MacOS)
 - both scripts maintain a hidden directory called `~/.covid-19` in your home directory. 
   -`covid-19_ingest.sh` checks`lastcsvprocessed`.  Delete that file to process all daily-report files from the beginning, or change the date in the file to start processing files AFTER the entered date.  

## TODO
 - use [postgREST](http://postgrest.org) to add a REST API in front of TimescaleDB database
 - create a Grafana dashboard
 - create a Carto visualization
 - create a Superset visualization

 ## ACKNOWLEDGEMENTS
  - thanks to Avtar Sewrathan (@avthars), Prashant Sridharan (@CoolAssPuppy) and Mike Freedman (@michaelfreedman) at [Timescale](https://timescale.com) for their help & support to implement this project from idea to implementation in 5 days!
  - thanks to Julian Simioni (@orangejulius) at [Geocode.earth](https://geocode.earth) for allowing us to use the Geocode.earth API!


Shield: [![CC BY-SA 4.0][cc-by-sa-shield]][cc-by-sa]

This work is licensed under a [Creative Commons Attribution-ShareAlike 4.0
International License][cc-by-sa].

[![CC BY-SA 4.0][cc-by-sa-image]][cc-by-sa]

[cc-by-sa]: http://creativecommons.org/licenses/by-sa/4.0/
[cc-by-sa-image]: https://licensebuttons.net/l/by-sa/4.0/88x31.png
[cc-by-sa-shield]: https://img.shields.io/badge/License-CC%20BY--SA%204.0-lightgrey.svg
