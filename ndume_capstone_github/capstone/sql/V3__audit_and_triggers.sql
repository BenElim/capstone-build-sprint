-- V3: audit log + business-rule triggers.

CREATE TABLE audit_log (
    audit_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name  text        NOT NULL,
    row_pk      text        NOT NULL,
    ranch_id    integer,
    action      text        NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    old_data    jsonb,
    new_data    jsonb,
    changed_by  text,                      -- app.user_id set by the application per transaction
    db_user     text        NOT NULL DEFAULT current_user,
    changed_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_ranch_time ON audit_log (ranch_id, changed_at DESC);
CREATE INDEX idx_audit_table_row  ON audit_log (table_name, row_pk);

-- SECURITY DEFINER: the app role can cause audit rows to be written but can never
-- INSERT/UPDATE/DELETE audit_log directly, so the trail cannot be tampered with.
CREATE OR REPLACE FUNCTION audit_row() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    pk_col text := TG_ARGV[0];
    old_j  jsonb;
    new_j  jsonb;
    rid    integer;
    pk     text;
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') THEN old_j := to_jsonb(OLD); END IF;
    IF TG_OP IN ('INSERT','UPDATE') THEN new_j := to_jsonb(NEW); END IF;
    -- never copy the encrypted phone into the audit trail
    old_j := old_j - 'phone_enc';
    new_j := new_j - 'phone_enc';
    rid := COALESCE((new_j->>'ranch_id')::integer, (old_j->>'ranch_id')::integer);
    pk  := COALESCE(new_j->>pk_col, old_j->>pk_col);
    INSERT INTO audit_log (table_name, row_pk, ranch_id, action, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME, pk, rid, TG_OP, old_j, new_j, current_setting('app.user_id', true));
    RETURN COALESCE(NEW, OLD);
END $$;

CREATE TRIGGER trg_audit_animals  AFTER INSERT OR UPDATE OR DELETE ON animals
    FOR EACH ROW EXECUTE FUNCTION audit_row('animal_id');
CREATE TRIGGER trg_audit_health   AFTER INSERT OR UPDATE OR DELETE ON health_events
    FOR EACH ROW EXECUTE FUNCTION audit_row('event_id');
CREATE TRIGGER trg_audit_sales    AFTER INSERT OR UPDATE OR DELETE ON sales
    FOR EACH ROW EXECUTE FUNCTION audit_row('sale_id');
CREATE TRIGGER trg_audit_buyers   AFTER INSERT OR UPDATE OR DELETE ON buyers
    FOR EACH ROW EXECUTE FUNCTION audit_row('buyer_id');

-- keep animals.updated_at honest
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_animals_touch BEFORE UPDATE ON animals
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- business rule: recording a sale removes the animal from the active herd,
-- and an animal that is not active cannot be sold.
CREATE OR REPLACE FUNCTION sale_marks_animal_sold() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE cur text;
BEGIN
    SELECT status INTO cur FROM animals WHERE animal_id = NEW.animal_id FOR UPDATE;
    IF cur IS DISTINCT FROM 'active' THEN
        RAISE EXCEPTION 'animal % is not active (status=%)', NEW.animal_id, cur;
    END IF;
    UPDATE animals SET status = 'sold', pasture_id = NULL WHERE animal_id = NEW.animal_id;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_sale_marks_sold BEFORE INSERT ON sales
    FOR EACH ROW EXECUTE FUNCTION sale_marks_animal_sold();
