-- V1: core tables. Tenant key = ranch_id on every business table.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE ranches (
    ranch_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        text        NOT NULL UNIQUE,
    county      text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app_users (
    user_id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ranch_id       integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    email          text    NOT NULL UNIQUE,
    password_hash  text    NOT NULL,                 -- bcrypt via pgcrypto crypt()
    full_name      text    NOT NULL,
    role           text    NOT NULL CHECK (role IN ('owner','manager','vet','worker')),
    created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE breeds (
    breed_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name      text NOT NULL UNIQUE,
    purpose   text NOT NULL CHECK (purpose IN ('beef','dairy','dual'))
);

CREATE TABLE pastures (
    pasture_id     integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ranch_id       integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    name           text    NOT NULL,
    area_ha        numeric(8,2) NOT NULL CHECK (area_ha > 0),
    capacity_head  integer NOT NULL CHECK (capacity_head > 0),
    UNIQUE (ranch_id, name)
);

CREATE TABLE animals (
    animal_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ranch_id     integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    tag_number   text    NOT NULL,
    name         text,
    breed_id     integer NOT NULL REFERENCES breeds(breed_id),
    sex          char(1) NOT NULL CHECK (sex IN ('M','F')),
    birth_date   date    NOT NULL,
    dam_id       bigint  REFERENCES animals(animal_id) ON DELETE SET NULL,
    sire_id      bigint  REFERENCES animals(animal_id) ON DELETE SET NULL,
    pasture_id   integer REFERENCES pastures(pasture_id) ON DELETE SET NULL,
    status       text    NOT NULL DEFAULT 'active' CHECK (status IN ('active','sold','deceased')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (ranch_id, tag_number),
    CHECK (dam_id  IS DISTINCT FROM animal_id),
    CHECK (sire_id IS DISTINCT FROM animal_id)
);

CREATE TABLE weight_records (
    weight_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    animal_id    bigint  NOT NULL REFERENCES animals(animal_id) ON DELETE CASCADE,
    ranch_id     integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    weighed_on   date    NOT NULL,
    weight_kg    numeric(6,1) NOT NULL CHECK (weight_kg > 0 AND weight_kg < 1500),
    recorded_by  integer REFERENCES app_users(user_id) ON DELETE SET NULL
);

CREATE TABLE health_events (
    event_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    animal_id    bigint  NOT NULL REFERENCES animals(animal_id) ON DELETE CASCADE,
    ranch_id     integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    event_date   date    NOT NULL,
    event_type   text    NOT NULL CHECK (event_type IN ('vaccination','treatment','deworming','checkup')),
    medicine     text,
    next_due_on  date,
    cost_kes     numeric(10,2) NOT NULL DEFAULT 0 CHECK (cost_kes >= 0),
    recorded_by  integer REFERENCES app_users(user_id) ON DELETE SET NULL
);

CREATE TABLE breeding_events (
    breeding_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ranch_id          integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    dam_id            bigint  NOT NULL REFERENCES animals(animal_id) ON DELETE CASCADE,
    sire_id           bigint  REFERENCES animals(animal_id) ON DELETE SET NULL,
    mated_on          date    NOT NULL,
    expected_calving  date,
    outcome           text    NOT NULL DEFAULT 'pending' CHECK (outcome IN ('pending','calved','failed')),
    calf_id           bigint  UNIQUE REFERENCES animals(animal_id) ON DELETE SET NULL
);

CREATE TABLE feed_logs (
    feed_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ranch_id      integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    pasture_id    integer NOT NULL REFERENCES pastures(pasture_id) ON DELETE CASCADE,
    logged_on     date    NOT NULL,
    feed_type     text    NOT NULL,
    quantity_kg   numeric(10,1) NOT NULL CHECK (quantity_kg > 0),
    cost_kes      numeric(10,2) NOT NULL DEFAULT 0 CHECK (cost_kes >= 0)
);

CREATE TABLE buyers (
    buyer_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ranch_id   integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    name       text   NOT NULL,
    phone_enc  bytea,                                -- pgp_sym_encrypt(); never stored in clear
    UNIQUE (ranch_id, name)
);

CREATE TABLE sales (
    sale_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ranch_id           integer NOT NULL REFERENCES ranches(ranch_id) ON DELETE CASCADE,
    animal_id          bigint  NOT NULL UNIQUE REFERENCES animals(animal_id),
    buyer_id           integer NOT NULL REFERENCES buyers(buyer_id),
    sold_on            date    NOT NULL,
    price_kes          numeric(12,2) NOT NULL CHECK (price_kes > 0),
    weight_at_sale_kg  numeric(6,1)
);
