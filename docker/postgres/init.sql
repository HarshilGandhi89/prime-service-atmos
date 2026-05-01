-- Postgres bootstrap script. Runs once, on first `docker compose up`.
-- Application schema is created by SQLAlchemy on app startup; this file
-- is reserved for extensions and operational tooling.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Read-only role for ad-hoc analytics / dashboards (matches the playbook's
-- "least privilege" guidance for groups-to-role mapping).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'prime_reader') THEN
        CREATE ROLE prime_reader NOLOGIN;
    END IF;
END
$$;

GRANT CONNECT ON DATABASE primes TO prime_reader;
GRANT USAGE ON SCHEMA public TO prime_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO prime_reader;
