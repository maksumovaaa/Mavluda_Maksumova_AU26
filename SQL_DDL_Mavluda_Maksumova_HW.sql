
CREATE SCHEMA IF NOT EXISTS car_sharing;
SET search_path TO car_sharing;


/* =====================================================================
   TABLES

   WHY THE ORDER MATTERS:
   A foreign key needs the parent table to exist already. If we create
   a child table first, PostgreSQL gives an error like:
   'relation "address" does not exist'.
   So we create parent tables first and child tables after them.

   WHAT HAPPENS WITHOUT A FOREIGN KEY:
   The database would accept wrong links, for example a trip that points
   to a reservation which does not exist, or we could delete a customer
   who still has reservations. That leaves "orphan" rows and wrong reports.

   RISKS OF A WRONG DATA TYPE:
   - Money as float -> rounding errors. We use numeric(10,2).
   - Dates as text -> wrong sorting and impossible dates like 31 Feb.
     We use date / timestamp.
   - Too small number type -> overflow when data grows. We use bigint for ids.
   - Too short varchar -> long values are rejected or cut.
   - Coordinates as integer -> position is wrong by many kilometers.
   ===================================================================== */

-- ---------- Parent tables (no foreign keys) ----------

CREATE TABLE IF NOT EXISTS address (
    address_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_code   char(2)      NOT NULL,
    city           varchar(100) NOT NULL,
    street_address varchar(255) NOT NULL,
    postal_code    varchar(20),
    latitude       numeric(9,6),
    longitude      numeric(9,6),
    CONSTRAINT uq_address UNIQUE (country_code, city, street_address)
);

CREATE TABLE IF NOT EXISTS vehicle_category (
    category_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name varchar(50) NOT NULL,
    description   varchar(255),
    -- UNIQUE: no two categories with the same name.
    -- Without it, "SUV" could be saved twice and reports would be confusing.
    CONSTRAINT uq_vehicle_category_name UNIQUE (category_name)
);

CREATE TABLE IF NOT EXISTS vehicle_feature (
    feature_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    feature_name varchar(60) NOT NULL,
    description  varchar(255),
    CONSTRAINT uq_vehicle_feature_name UNIQUE (feature_name)
);

CREATE TABLE IF NOT EXISTS payment_method (
    payment_method_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    method_name       varchar(30) NOT NULL,
    is_active         boolean     NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_payment_method_name UNIQUE (method_name)
);

CREATE TABLE IF NOT EXISTS pricing_plan (
    pricing_plan_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plan_name       varchar(80)   NOT NULL,
    billing_unit    varchar(20)   NOT NULL,
    rate_amount     numeric(10,2) NOT NULL,
    currency_code   char(3)       NOT NULL DEFAULT 'USD',
    effective_from  timestamp     NOT NULL DEFAULT current_timestamp,
    effective_to    timestamp,
    CONSTRAINT uq_pricing_plan UNIQUE (plan_name, effective_from),
    -- CHECK (not negative): a price can not be below 0.
    -- Without it, a typo like -5 would mean the company pays the customer.
    CONSTRAINT chk_pricing_rate CHECK (rate_amount >= 0),
    -- CHECK (date after 2000-01-01): stops fake dates like 1900-01-01.
    CONSTRAINT chk_pricing_from CHECK (effective_from > TIMESTAMP '2000-01-01'),
    CONSTRAINT chk_pricing_unit CHECK (billing_unit IN ('minute', 'hour', 'day', 'km'))
);

CREATE TABLE IF NOT EXISTS customer (
    customer_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name     varchar(50)  NOT NULL,   -- NOT NULL: we must know the name
    last_name      varchar(50)  NOT NULL,
    email          varchar(254) NOT NULL,
    phone          varchar(20)  NOT NULL,
    created_at     timestamp    NOT NULL DEFAULT current_timestamp,
    account_status varchar(20)  NOT NULL DEFAULT 'active',
    -- UNIQUE: one account per e-mail. Without it the same person could
    -- register many times and e-mail search would return several rows.
    CONSTRAINT uq_customer_email UNIQUE (email),
    -- CHECK (only allowed values, like gender): only these 3 statuses.
    -- Without it, typos like 'actve' would be saved and break filters.
    CONSTRAINT chk_customer_status CHECK (account_status IN ('active', 'suspended', 'closed')),
    CONSTRAINT chk_customer_created CHECK (created_at > TIMESTAMP '2000-01-01')
);

-- ---------- Tables that depend on the tables above ----------

CREATE TABLE IF NOT EXISTS parking_zone (
    zone_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    zone_name  varchar(100) NOT NULL,
    address_id bigint       NOT NULL REFERENCES address (address_id),
    CONSTRAINT uq_parking_zone_name UNIQUE (zone_name)
);

CREATE TABLE IF NOT EXISTS driver_license (
    license_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id         bigint      NOT NULL REFERENCES customer (customer_id),
    license_number      varchar(50) NOT NULL,
    issuing_country     char(2)     NOT NULL,
    issue_date          date        NOT NULL,
    expiry_date         date        NOT NULL,
    verification_status varchar(20) NOT NULL DEFAULT 'pending',
    CONSTRAINT uq_driver_license UNIQUE (issuing_country, license_number),
    CONSTRAINT chk_license_issue CHECK (issue_date > DATE '2000-01-01'),
    CONSTRAINT chk_license_expiry CHECK (expiry_date > issue_date),
    CONSTRAINT chk_license_status CHECK (verification_status IN ('pending', 'verified', 'rejected'))
);

CREATE TABLE IF NOT EXISTS parking_spot (
    spot_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    zone_id    bigint      NOT NULL REFERENCES parking_zone (zone_id),
    address_id bigint      NOT NULL REFERENCES address (address_id),
    spot_code  varchar(30) NOT NULL,
    is_active  boolean     NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_parking_spot_code UNIQUE (spot_code)
);

CREATE TABLE IF NOT EXISTS vehicle (
    vehicle_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id       bigint        NOT NULL REFERENCES vehicle_category (category_id),
    current_spot_id   bigint        NOT NULL REFERENCES parking_spot (spot_id),
    plate_number      varchar(20)   NOT NULL,
    vin               char(17)      NOT NULL,
    make              varchar(50)   NOT NULL,
    model             varchar(50)   NOT NULL,
    model_year        smallint      NOT NULL,
    battery_level_pct smallint,
    odometer_km       numeric(10,1) NOT NULL DEFAULT 0,
    CONSTRAINT uq_vehicle_plate UNIQUE (plate_number),
    CONSTRAINT uq_vehicle_vin UNIQUE (vin),
    -- CHECK (not negative): mileage can not be below 0.
    -- Without it a wrong value like -500 km could be saved.
    CONSTRAINT chk_vehicle_odometer CHECK (odometer_km >= 0),
    CONSTRAINT chk_vehicle_battery CHECK (battery_level_pct BETWEEN 0 AND 100),
    CONSTRAINT chk_vehicle_year CHECK (model_year >= 2000)
);

CREATE TABLE IF NOT EXISTS vehicle_feature_assignment (
    vehicle_id  bigint    NOT NULL REFERENCES vehicle (vehicle_id),
    feature_id  bigint    NOT NULL REFERENCES vehicle_feature (feature_id),
    assigned_at timestamp NOT NULL DEFAULT current_timestamp,
    PRIMARY KEY (vehicle_id, feature_id)
);

CREATE TABLE IF NOT EXISTS vehicle_status_history (
    status_history_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id        bigint      NOT NULL REFERENCES vehicle (vehicle_id),
    status            varchar(20) NOT NULL,
    changed_at        timestamp   NOT NULL DEFAULT current_timestamp,
    notes             varchar(500),
    CONSTRAINT uq_status_history UNIQUE (vehicle_id, changed_at),
    CONSTRAINT chk_status_value CHECK (status IN ('available', 'reserved', 'in_use', 'maintenance', 'out_of_service'))
);

CREATE TABLE IF NOT EXISTS reservation (
    reservation_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id        bigint      NOT NULL REFERENCES customer (customer_id),
    pricing_plan_id    bigint      NOT NULL REFERENCES pricing_plan (pricing_plan_id),
    vehicle_id         bigint      NOT NULL REFERENCES vehicle (vehicle_id),
    reserved_from      timestamp   NOT NULL,
    reserved_until     timestamp   NOT NULL,
    reservation_status varchar(20) NOT NULL DEFAULT 'pending',
    created_at         timestamp   NOT NULL DEFAULT current_timestamp,
    CONSTRAINT uq_reservation UNIQUE (vehicle_id, reserved_from),
    CONSTRAINT chk_reservation_from CHECK (reserved_from > TIMESTAMP '2000-01-01'),
    CONSTRAINT chk_reservation_period CHECK (reserved_until > reserved_from),
    CONSTRAINT chk_reservation_status CHECK (reservation_status IN ('pending', 'confirmed', 'active', 'completed', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS maintenance_record (
    maintenance_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reported_by_customer_id bigint REFERENCES customer (customer_id),
    vehicle_id              bigint        NOT NULL REFERENCES vehicle (vehicle_id),
    maintenance_type        varchar(40)   NOT NULL,
    description             varchar(1000),
    opened_at               timestamp     NOT NULL DEFAULT current_timestamp,
    closed_at               timestamp,
    cost_amount             numeric(10,2),
    maintenance_status      varchar(20)   NOT NULL DEFAULT 'open',
    CONSTRAINT uq_maintenance UNIQUE (vehicle_id, maintenance_type, opened_at),
    CONSTRAINT chk_maintenance_cost CHECK (cost_amount >= 0),
    CONSTRAINT chk_maintenance_status CHECK (maintenance_status IN ('open', 'in_progress', 'closed'))
);

CREATE TABLE IF NOT EXISTS trip (
    trip_id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reservation_id    bigint        NOT NULL REFERENCES reservation (reservation_id),
    started_at        timestamp     NOT NULL,
    ended_at          timestamp,
    start_spot_id     bigint        NOT NULL REFERENCES parking_spot (spot_id),
    end_spot_id       bigint        REFERENCES parking_spot (spot_id),
    start_odometer_km numeric(10,1) NOT NULL,
    end_odometer_km   numeric(10,1),
    trip_status       varchar(20)   NOT NULL DEFAULT 'in_progress',
    CONSTRAINT uq_trip UNIQUE (reservation_id, started_at),
    CONSTRAINT chk_trip_started CHECK (started_at > TIMESTAMP '2000-01-01'),
    CONSTRAINT chk_trip_period CHECK (ended_at > started_at),
    CONSTRAINT chk_trip_start_odo CHECK (start_odometer_km >= 0),
    CONSTRAINT chk_trip_end_odo CHECK (end_odometer_km >= start_odometer_km),
    CONSTRAINT chk_trip_status CHECK (trip_status IN ('in_progress', 'completed', 'cancelled'))
);

CREATE TABLE IF NOT EXISTS payment (
    payment_id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trip_id                  bigint        NOT NULL REFERENCES trip (trip_id),
    payment_method_id        bigint        NOT NULL REFERENCES payment_method (payment_method_id),
    amount                   numeric(10,2) NOT NULL,
    currency_code            char(3)       NOT NULL DEFAULT 'USD',
    payment_status           varchar(20)   NOT NULL DEFAULT 'pending',
    provider_transaction_ref varchar(100),
    created_at               timestamp     NOT NULL DEFAULT current_timestamp,
    -- UNIQUE: the same bank transaction can not be saved twice (double charge).
    CONSTRAINT uq_payment_ref UNIQUE (provider_transaction_ref),
    CONSTRAINT chk_payment_amount CHECK (amount >= 0),
    CONSTRAINT chk_payment_status CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded'))
);


/* =====================================================================
   SAMPLE DATA

   How consistency is kept:
   - Parent tables are filled first, child tables after them.
   - We do NOT type ids by hand. For every foreign key we look up the
     id with a small SELECT (for example by street, plate number or
     e-mail). So every link points to a real row.
   - ON CONFLICT DO NOTHING skips rows that already exist (unique
     constraints), so running the script again creates no duplicates.
   ===================================================================== */

INSERT INTO address (country_code, city, street_address, postal_code, latitude, longitude)
VALUES ('UZ', 'Tashkent',  'Amir Temur Street 15', '100000', 41.311081, 69.240562),
       ('UZ', 'Tashkent',  'Mustaqillik Avenue 8', '100077', 41.304200, 69.279700),
       ('UZ', 'Tashkent',  'Navoi Street 30',      '100011', 41.320100, 69.250300),
       ('UZ', 'Samarkand', 'Registan Street 1',    '140100', 39.654200, 66.959700)
ON CONFLICT DO NOTHING;

INSERT INTO vehicle_category (category_name, description)
VALUES ('Economy',  'Small and cheap city cars'),
       ('SUV',      'Bigger cars for families'),
       ('Electric', 'Fully electric cars')
ON CONFLICT DO NOTHING;

INSERT INTO vehicle_feature (feature_name, description)
VALUES ('GPS',        'Navigation system'),
       ('Bluetooth',  'Hands-free phone connection'),
       ('Child seat', 'Safety seat for children')
ON CONFLICT DO NOTHING;

INSERT INTO payment_method (method_name)
VALUES ('card'), ('cash'), ('mobile_wallet')
ON CONFLICT DO NOTHING;

INSERT INTO pricing_plan (plan_name, billing_unit, rate_amount, effective_from)
VALUES ('Per Minute Standard', 'minute', 0.25,  '2025-01-01'),
       ('Hourly Saver',        'hour',   12.00, '2025-01-01'),
       ('Daily Explorer',      'day',    55.00, '2025-01-01')
ON CONFLICT DO NOTHING;

INSERT INTO customer (first_name, last_name, email, phone)
VALUES ('Alisher', 'Karimov',  'alisher.karimov@example.com',  '+998901112233'),
       ('Dilnoza', 'Yusupova', 'dilnoza.yusupova@example.com', '+998902223344'),
       ('Bobur',   'Rahimov',  'bobur.rahimov@example.com',    '+998903334455')
ON CONFLICT DO NOTHING;

INSERT INTO parking_zone (zone_name, address_id)
VALUES ('Tashkent Center',
        (SELECT address_id FROM address WHERE street_address = 'Amir Temur Street 15')),
       ('Samarkand Old Town',
        (SELECT address_id FROM address WHERE street_address = 'Registan Street 1'))
ON CONFLICT DO NOTHING;

INSERT INTO driver_license (customer_id, license_number, issuing_country, issue_date, expiry_date, verification_status)
VALUES ((SELECT customer_id FROM customer WHERE email = 'alisher.karimov@example.com'),
        'AA1234567', 'UZ', '2018-05-10', '2028-05-10', 'verified'),
       ((SELECT customer_id FROM customer WHERE email = 'dilnoza.yusupova@example.com'),
        'AB7654321', 'UZ', '2020-09-15', '2030-09-15', 'verified'),
       ((SELECT customer_id FROM customer WHERE email = 'bobur.rahimov@example.com'),
        'AC1122334', 'UZ', '2019-02-01', '2029-02-01', 'pending')
ON CONFLICT DO NOTHING;

INSERT INTO parking_spot (zone_id, address_id, spot_code)
VALUES ((SELECT zone_id FROM parking_zone WHERE zone_name = 'Tashkent Center'),
        (SELECT address_id FROM address WHERE street_address = 'Mustaqillik Avenue 8'), 'TSH-A-01'),
       ((SELECT zone_id FROM parking_zone WHERE zone_name = 'Tashkent Center'),
        (SELECT address_id FROM address WHERE street_address = 'Navoi Street 30'), 'TSH-A-02'),
       ((SELECT zone_id FROM parking_zone WHERE zone_name = 'Samarkand Old Town'),
        (SELECT address_id FROM address WHERE street_address = 'Registan Street 1'), 'SMK-S-01')
ON CONFLICT DO NOTHING;

INSERT INTO vehicle (category_id, current_spot_id, plate_number, vin, make, model, model_year, battery_level_pct, odometer_km)
VALUES ((SELECT category_id FROM vehicle_category WHERE category_name = 'Economy'),
        (SELECT spot_id FROM parking_spot WHERE spot_code = 'TSH-A-01'),
        '01A123BC', 'KLAKA48E1DB000001', 'Chevrolet', 'Spark', 2021, NULL, 12000.5),
       ((SELECT category_id FROM vehicle_category WHERE category_name = 'SUV'),
        (SELECT spot_id FROM parking_spot WHERE spot_code = 'TSH-A-02'),
        '01B456DE', 'KNAPH81ABJ7000002', 'Kia', 'Sportage', 2022, NULL, 8500.0),
       ((SELECT category_id FROM vehicle_category WHERE category_name = 'Electric'),
        (SELECT spot_id FROM parking_spot WHERE spot_code = 'SMK-S-01'),
        '30C789FG', 'LRWYGCEK4NC000003', 'Tesla', 'Model 3', 2023, 85, 4300.2)
ON CONFLICT DO NOTHING;

INSERT INTO vehicle_feature_assignment (vehicle_id, feature_id)
VALUES ((SELECT vehicle_id FROM vehicle WHERE plate_number = '01A123BC'),
        (SELECT feature_id FROM vehicle_feature WHERE feature_name = 'Bluetooth')),
       ((SELECT vehicle_id FROM vehicle WHERE plate_number = '01B456DE'),
        (SELECT feature_id FROM vehicle_feature WHERE feature_name = 'GPS')),
       ((SELECT vehicle_id FROM vehicle WHERE plate_number = '30C789FG'),
        (SELECT feature_id FROM vehicle_feature WHERE feature_name = 'GPS'))
ON CONFLICT DO NOTHING;

INSERT INTO vehicle_status_history (vehicle_id, status, changed_at, notes)
VALUES ((SELECT vehicle_id FROM vehicle WHERE plate_number = '01A123BC'),
        'available', '2025-02-01 09:00', 'Added to fleet'),
       ((SELECT vehicle_id FROM vehicle WHERE plate_number = '01B456DE'),
        'available', '2025-02-01 09:05', 'Added to fleet'),
       ((SELECT vehicle_id FROM vehicle WHERE plate_number = '30C789FG'),
        'maintenance', '2025-02-02 10:00', 'Battery check')
ON CONFLICT DO NOTHING;

INSERT INTO reservation (customer_id, pricing_plan_id, vehicle_id, reserved_from, reserved_until, reservation_status)
VALUES ((SELECT customer_id FROM customer WHERE email = 'alisher.karimov@example.com'),
        (SELECT pricing_plan_id FROM pricing_plan WHERE plan_name = 'Per Minute Standard'),
        (SELECT vehicle_id FROM vehicle WHERE plate_number = '01A123BC'),
        '2025-03-01 08:00', '2025-03-01 12:00', 'completed'),
       ((SELECT customer_id FROM customer WHERE email = 'dilnoza.yusupova@example.com'),
        (SELECT pricing_plan_id FROM pricing_plan WHERE plan_name = 'Hourly Saver'),
        (SELECT vehicle_id FROM vehicle WHERE plate_number = '01B456DE'),
        '2025-03-02 14:00', '2025-03-02 18:00', 'completed')
ON CONFLICT DO NOTHING;

INSERT INTO maintenance_record (reported_by_customer_id, vehicle_id, maintenance_type, description, opened_at, closed_at, cost_amount, maintenance_status)
VALUES ((SELECT customer_id FROM customer WHERE email = 'alisher.karimov@example.com'),
        (SELECT vehicle_id FROM vehicle WHERE plate_number = '30C789FG'),
        'battery_check', 'Battery drains fast', '2025-02-02 10:00', '2025-02-03 16:00', 120.00, 'closed'),
       ((SELECT customer_id FROM customer WHERE email = 'dilnoza.yusupova@example.com'),
        (SELECT vehicle_id FROM vehicle WHERE plate_number = '01B456DE'),
        'tire_change', 'Front tire is worn', '2025-03-05 11:00', NULL, NULL, 'open')
ON CONFLICT DO NOTHING;

INSERT INTO trip (reservation_id, started_at, ended_at, start_spot_id, end_spot_id, start_odometer_km, end_odometer_km, trip_status)
VALUES ((SELECT reservation_id FROM reservation
          WHERE vehicle_id = (SELECT vehicle_id FROM vehicle WHERE plate_number = '01A123BC')
            AND reserved_from = '2025-03-01 08:00'),
        '2025-03-01 08:10', '2025-03-01 09:30',
        (SELECT spot_id FROM parking_spot WHERE spot_code = 'TSH-A-01'),
        (SELECT spot_id FROM parking_spot WHERE spot_code = 'TSH-A-02'),
        12000.5, 12035.0, 'completed'),
       ((SELECT reservation_id FROM reservation
          WHERE vehicle_id = (SELECT vehicle_id FROM vehicle WHERE plate_number = '01B456DE')
            AND reserved_from = '2025-03-02 14:00'),
        '2025-03-02 14:05', '2025-03-02 17:00',
        (SELECT spot_id FROM parking_spot WHERE spot_code = 'TSH-A-02'),
        (SELECT spot_id FROM parking_spot WHERE spot_code = 'TSH-A-01'),
        8500.0, 8620.4, 'completed')
ON CONFLICT DO NOTHING;

INSERT INTO payment (trip_id, payment_method_id, amount, payment_status, provider_transaction_ref)
VALUES ((SELECT t.trip_id FROM trip t
          JOIN reservation r ON r.reservation_id = t.reservation_id
          WHERE r.vehicle_id = (SELECT vehicle_id FROM vehicle WHERE plate_number = '01A123BC')),
        (SELECT payment_method_id FROM payment_method WHERE method_name = 'card'),
        22.50, 'paid', 'TXN-2025-0001'),
       ((SELECT t.trip_id FROM trip t
          JOIN reservation r ON r.reservation_id = t.reservation_id
          WHERE r.vehicle_id = (SELECT vehicle_id FROM vehicle WHERE plate_number = '01B456DE')),
        (SELECT payment_method_id FROM payment_method WHERE method_name = 'mobile_wallet'),
        36.00, 'paid', 'TXN-2025-0002')
ON CONFLICT DO NOTHING;


/* =====================================================================
   record_ts COLUMN
   ADD COLUMN with NOT NULL + DEFAULT fills all existing rows with
   current_date automatically, so it does not fail on tables with data.
   ===================================================================== */

ALTER TABLE address                    ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE vehicle_category           ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE vehicle_feature            ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE payment_method             ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE pricing_plan               ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE customer                   ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE parking_zone               ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE driver_license             ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE parking_spot               ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE vehicle                    ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE vehicle_feature_assignment ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE vehicle_status_history     ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE reservation                ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE maintenance_record         ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE trip                       ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;
ALTER TABLE payment                    ADD COLUMN IF NOT EXISTS record_ts date NOT NULL DEFAULT current_date;


