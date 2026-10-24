CREATE DATABASE IF NOT EXISTS hotel_management
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE hotel_management;

CREATE TABLE IF NOT EXISTS room_types (
    room_type_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    type_name VARCHAR(80) NOT NULL,
    description VARCHAR(500) NULL,
    capacity TINYINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (room_type_id),
    UNIQUE KEY uq_room_types_type_name (type_name),
    CONSTRAINT chk_room_types_capacity CHECK (capacity > 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS rooms (
    room_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    room_number VARCHAR(12) NOT NULL,
    room_type_id BIGINT UNSIGNED NOT NULL,
    floor_number SMALLINT NOT NULL,
    room_status ENUM('available', 'occupied', 'cleaning', 'maintenance')
        NOT NULL DEFAULT 'available',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (room_id),
    UNIQUE KEY uq_rooms_room_number (room_number),
    KEY idx_rooms_room_type_status (room_type_id, room_status),
    CONSTRAINT fk_rooms_room_type
        FOREIGN KEY (room_type_id) REFERENCES room_types (room_type_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS seasonal_prices (
    seasonal_price_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    room_type_id BIGINT UNSIGNED NOT NULL,
    season_name VARCHAR(80) NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    nightly_rate DECIMAL(12, 2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'TRY',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (seasonal_price_id),
    KEY idx_seasonal_prices_type_dates (room_type_id, valid_from, valid_to),
    CONSTRAINT fk_seasonal_prices_room_type
        FOREIGN KEY (room_type_id) REFERENCES room_types (room_type_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_seasonal_prices_dates CHECK (valid_to > valid_from),
    CONSTRAINT chk_seasonal_prices_rate CHECK (nightly_rate >= 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS guests (
    guest_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(254) NOT NULL,
    phone VARCHAR(32) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (guest_id),
    UNIQUE KEY uq_guests_email (email)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS users (
    user_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    guest_id BIGINT UNSIGNED NULL,
    email VARCHAR(254) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('guest', 'receptionist', 'admin') NOT NULL DEFAULT 'guest',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_users_email (email),
    UNIQUE KEY uq_users_guest (guest_id),
    CONSTRAINT fk_users_guest
        FOREIGN KEY (guest_id) REFERENCES guests (guest_id)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS staff (
    staff_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    job_title ENUM('receptionist', 'housekeeping', 'manager') NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    hired_at DATE NOT NULL,
    PRIMARY KEY (staff_id),
    UNIQUE KEY uq_staff_user (user_id),
    CONSTRAINT fk_staff_user
        FOREIGN KEY (user_id) REFERENCES users (user_id)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS reservations (
    reservation_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    guest_id BIGINT UNSIGNED NOT NULL,
    room_id BIGINT UNSIGNED NOT NULL,
    created_by_user_id BIGINT UNSIGNED NULL,
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    status ENUM('pending', 'confirmed', 'checked_in', 'completed', 'cancelled')
        NOT NULL DEFAULT 'pending',
    special_requests VARCHAR(1000) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (reservation_id),
    KEY idx_reservations_room_dates (room_id, check_in_date, check_out_date),
    KEY idx_reservations_guest_dates (guest_id, check_in_date),
    KEY idx_reservations_status_dates (status, check_in_date, check_out_date),
    CONSTRAINT fk_reservations_guest
        FOREIGN KEY (guest_id) REFERENCES guests (guest_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_reservations_room
        FOREIGN KEY (room_id) REFERENCES rooms (room_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_reservations_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (user_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_reservations_dates CHECK (check_out_date > check_in_date)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stays (
    stay_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    reservation_id BIGINT UNSIGNED NOT NULL,
    checked_in_by_staff_id BIGINT UNSIGNED NULL,
    checked_out_by_staff_id BIGINT UNSIGNED NULL,
    actual_check_in DATE NOT NULL,
    actual_check_out DATE NULL,
    status ENUM('active', 'completed') NOT NULL DEFAULT 'active',
    total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (stay_id),
    UNIQUE KEY uq_stays_reservation (reservation_id),
    KEY idx_stays_status_dates (status, actual_check_in, actual_check_out),
    CONSTRAINT fk_stays_reservation
        FOREIGN KEY (reservation_id) REFERENCES reservations (reservation_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_stays_checked_in_by
        FOREIGN KEY (checked_in_by_staff_id) REFERENCES staff (staff_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT fk_stays_checked_out_by
        FOREIGN KEY (checked_out_by_staff_id) REFERENCES staff (staff_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_stays_total CHECK (total_amount >= 0),
    CONSTRAINT chk_stays_actual_dates
        CHECK (actual_check_out IS NULL OR actual_check_out > actual_check_in)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS extra_services (
    service_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    service_name VARCHAR(100) NOT NULL,
    description VARCHAR(500) NULL,
    unit_price DECIMAL(12, 2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'TRY',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (service_id),
    UNIQUE KEY uq_extra_services_name (service_name),
    CONSTRAINT chk_extra_services_price CHECK (unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stay_services (
    stay_service_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    stay_id BIGINT UNSIGNED NOT NULL,
    service_id BIGINT UNSIGNED NOT NULL,
    quantity SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    unit_price DECIMAL(12, 2) NOT NULL,
    added_by_staff_id BIGINT UNSIGNED NULL,
    added_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (stay_service_id),
    KEY idx_stay_services_stay (stay_id),
    CONSTRAINT fk_stay_services_stay
        FOREIGN KEY (stay_id) REFERENCES stays (stay_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_stay_services_service
        FOREIGN KEY (service_id) REFERENCES extra_services (service_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_stay_services_staff
        FOREIGN KEY (added_by_staff_id) REFERENCES staff (staff_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_stay_services_quantity CHECK (quantity > 0),
    CONSTRAINT chk_stay_services_price CHECK (unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS payments (
    payment_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    stay_id BIGINT UNSIGNED NOT NULL,
    amount DECIMAL(12, 2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'TRY',
    payment_method ENUM('cash', 'card', 'transfer') NOT NULL,
    payment_status ENUM('pending', 'paid', 'refunded', 'failed')
        NOT NULL DEFAULT 'pending',
    paid_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (payment_id),
    KEY idx_payments_stay_status (stay_id, payment_status),
    KEY idx_payments_paid_at_status (paid_at, payment_status),
    CONSTRAINT fk_payments_stay
        FOREIGN KEY (stay_id) REFERENCES stays (stay_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_payments_amount CHECK (amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS cleaning_records (
    cleaning_record_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    room_id BIGINT UNSIGNED NOT NULL,
    reservation_id BIGINT UNSIGNED NULL,
    staff_id BIGINT UNSIGNED NULL,
    status ENUM('pending', 'in_progress', 'completed') NOT NULL DEFAULT 'pending',
    notes VARCHAR(500) NULL,
    started_at DATETIME NULL,
    completed_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (cleaning_record_id),
    KEY idx_cleaning_records_room_completed (room_id, completed_at),
    CONSTRAINT fk_cleaning_records_room
        FOREIGN KEY (room_id) REFERENCES rooms (room_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_cleaning_records_reservation
        FOREIGN KEY (reservation_id) REFERENCES reservations (reservation_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT fk_cleaning_records_staff
        FOREIGN KEY (staff_id) REFERENCES staff (staff_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT chk_cleaning_records_dates
        CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS operation_logs (
    operation_log_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    actor_user_id BIGINT UNSIGNED NULL,
    entity_name VARCHAR(64) NOT NULL,
    entity_id BIGINT UNSIGNED NOT NULL,
    action_name VARCHAR(32) NOT NULL,
    details JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (operation_log_id),
    KEY idx_operation_logs_entity (entity_name, entity_id, created_at),
    KEY idx_operation_logs_created_at (created_at),
    CONSTRAINT fk_operation_logs_actor
        FOREIGN KEY (actor_user_id) REFERENCES users (user_id)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;
