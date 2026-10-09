#!/bin/sh
# Corre UNA sola vez, al crear el volumen de Postgres.
# Un esquema y un usuario por servicio. Las contrasenas salen del .env,
# asi no quedan escritas en el repo.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS core;

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${AUTH_DB_USER}') THEN
    CREATE ROLE ${AUTH_DB_USER} LOGIN PASSWORD '${AUTH_DB_PASSWORD}';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${CORE_DB_USER}') THEN
    CREATE ROLE ${CORE_DB_USER} LOGIN PASSWORD '${CORE_DB_PASSWORD}';
  END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON SCHEMA auth TO ${AUTH_DB_USER};
GRANT ALL PRIVILEGES ON SCHEMA core TO ${CORE_DB_USER};
ALTER ROLE ${AUTH_DB_USER} SET search_path TO auth;
ALTER ROLE ${CORE_DB_USER} SET search_path TO core;

-- Cada servicio solo ve su esquema: Auth y Core no pueden hacer JOIN entre si.
REVOKE ALL ON SCHEMA core FROM ${AUTH_DB_USER};
REVOKE ALL ON SCHEMA auth FROM ${CORE_DB_USER};
SQL
