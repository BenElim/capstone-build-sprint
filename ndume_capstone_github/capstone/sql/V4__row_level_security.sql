-- V4: least-privilege roles + row-level security.
-- The migration/owner role (who runs Flyway) is NOT subject to RLS. The application roles are.
-- The app sets, per transaction:  SET LOCAL app.ranch_id = '<id>';  SET LOCAL app.role = '<role>';
--                                 SET LOCAL app.user_id = '<id>';

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'capstone_app') THEN
        CREATE ROLE capstone_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD 'change-me-app';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'capstone_readonly') THEN
        CREATE ROLE capstone_readonly LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD 'change-me-ro';
    END IF;
END $$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO capstone_app, capstone_readonly;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM capstone_app, capstone_readonly;

-- helper: current tenant (NULL if unset => policies match nothing => fail closed)
CREATE OR REPLACE FUNCTION app_ranch() RETURNS integer LANGUAGE sql STABLE AS
$$ SELECT NULLIF(current_setting('app.ranch_id', true), '')::integer $$;
CREATE OR REPLACE FUNCTION app_role() RETURNS text LANGUAGE sql STABLE AS
$$ SELECT NULLIF(current_setting('app.role', true), '') $$;
GRANT EXECUTE ON FUNCTION app_ranch(), app_role() TO capstone_app, capstone_readonly;

-- table privileges
GRANT SELECT ON breeds TO capstone_app, capstone_readonly;
GRANT SELECT ON ranches, pastures, animals, weight_records, health_events,
                breeding_events, feed_logs, sales TO capstone_app, capstone_readonly;
GRANT SELECT (user_id, ranch_id, email, full_name, role, created_at) ON app_users
                TO capstone_app, capstone_readonly;            -- password_hash NOT readable
GRANT SELECT (buyer_id, ranch_id, name) ON buyers TO capstone_app, capstone_readonly;  -- phone_enc NOT readable
GRANT INSERT, UPDATE ON animals, pastures, weight_records, health_events,
                        breeding_events, feed_logs, buyers TO capstone_app;
GRANT INSERT ON sales TO capstone_app;
GRANT SELECT ON audit_log TO capstone_app;                     -- owners only, via policy below
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO capstone_app;
-- no DELETE anywhere for the app: animals are never deleted, status changes instead.

-- enable RLS on every tenant table
DO $$ DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['app_users','pastures','animals','weight_records','health_events',
                           'breeding_events','feed_logs','buyers','sales','audit_log']
  LOOP EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t); END LOOP;
END $$;
ALTER TABLE ranches ENABLE ROW LEVEL SECURITY;

-- generic tenant policies
DO $$ DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['app_users','pastures','animals','weight_records','health_events',
                           'breeding_events','feed_logs','buyers']
  LOOP
    EXECUTE format($f$CREATE POLICY tenant_isolation ON %I FOR ALL
                      TO capstone_app, capstone_readonly
                      USING (ranch_id = app_ranch()) WITH CHECK (ranch_id = app_ranch())$f$, t);
  END LOOP;
END $$;

CREATE POLICY tenant_isolation ON ranches FOR SELECT
    TO capstone_app, capstone_readonly USING (ranch_id = app_ranch());

-- sales are financial: only owner/manager may see or create them
CREATE POLICY sales_tenant_roles ON sales FOR ALL TO capstone_app, capstone_readonly
    USING (ranch_id = app_ranch() AND app_role() IN ('owner','manager'))
    WITH CHECK (ranch_id = app_ranch() AND app_role() IN ('owner','manager'));

-- audit log: owners read their own ranch's trail; nobody writes it directly
CREATE POLICY audit_owner_read ON audit_log FOR SELECT TO capstone_app, capstone_readonly
    USING (ranch_id = app_ranch() AND app_role() = 'owner');
