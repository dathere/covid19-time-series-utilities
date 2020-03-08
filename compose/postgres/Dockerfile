FROM timescale/timescaledb-postgis:latest-pg10

COPY ./compose/postgres/initdb.sql /docker-entrypoint-initdb.d/010_initdb.sql
COPY schema.sql /docker-entrypoint-initdb.d/011_schema.sql
