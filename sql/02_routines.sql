USE hotel_management;

DELIMITER //

CREATE TRIGGER trg_seasonal_prices_before_insert
BEFORE INSERT ON seasonal_prices
FOR EACH ROW
BEGIN
    DECLARE v_overlap_count INT DEFAULT 0;

    IF NEW.valid_to <= NEW.valid_from THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Season price end date must be after its start date.';
    END IF;

    SELECT COUNT(*) INTO v_overlap_count
    FROM seasonal_prices
    WHERE room_type_id = NEW.room_type_id
      AND valid_from < NEW.valid_to
      AND valid_to > NEW.valid_from;

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Season price date ranges cannot overlap for a room type.';
    END IF;
END//

CREATE TRIGGER trg_seasonal_prices_before_update
BEFORE UPDATE ON seasonal_prices
FOR EACH ROW
BEGIN
    DECLARE v_overlap_count INT DEFAULT 0;

    IF NEW.valid_to <= NEW.valid_from THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Season price end date must be after its start date.';
    END IF;

    SELECT COUNT(*) INTO v_overlap_count
    FROM seasonal_prices
    WHERE room_type_id = NEW.room_type_id
      AND seasonal_price_id <> OLD.seasonal_price_id
      AND valid_from < NEW.valid_to
      AND valid_to > NEW.valid_from;

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Season price date ranges cannot overlap for a room type.';
    END IF;
END//

CREATE TRIGGER trg_reservations_before_insert
BEFORE INSERT ON reservations
FOR EACH ROW
BEGIN
    DECLARE v_locked_room_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_overlap_reservation_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR NOT FOUND
        SET v_overlap_reservation_id = NULL;

    IF NEW.check_out_date <= NEW.check_in_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Check-out date must be after check-in date.';
    END IF;

    SELECT room_id INTO v_locked_room_id
    FROM rooms
    WHERE room_id = NEW.room_id
    FOR UPDATE;

    IF v_locked_room_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Reservation room does not exist.';
    END IF;

    SELECT reservation_id INTO v_overlap_reservation_id
    FROM reservations
    WHERE room_id = NEW.room_id
      AND status <> 'cancelled'
      AND check_in_date < NEW.check_out_date
      AND check_out_date > NEW.check_in_date
    LIMIT 1
    FOR UPDATE;

    IF v_overlap_reservation_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'The room is already reserved for part of this date range.';
    END IF;
END//

CREATE TRIGGER trg_reservations_before_update
BEFORE UPDATE ON reservations
FOR EACH ROW
BEGIN
    DECLARE v_locked_room_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_overlap_reservation_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR NOT FOUND
        SET v_overlap_reservation_id = NULL;

    IF NEW.check_out_date <= NEW.check_in_date THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Check-out date must be after check-in date.';
    END IF;

    IF OLD.status IN ('cancelled', 'completed') AND NEW.status <> OLD.status THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cancelled and completed reservations cannot be reopened.';
    END IF;

    IF NEW.status = 'checked_in' AND OLD.status <> 'confirmed' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only confirmed reservations can be checked in.';
    END IF;

    IF NEW.status = 'completed' AND OLD.status <> 'checked_in' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only checked-in reservations can be checked out.';
    END IF;

    IF NEW.room_id <> OLD.room_id
       OR NEW.check_in_date <> OLD.check_in_date
       OR NEW.check_out_date <> OLD.check_out_date
       OR NEW.status <> OLD.status THEN
        SELECT room_id INTO v_locked_room_id
        FROM rooms
        WHERE room_id = NEW.room_id
        FOR UPDATE;

        IF v_locked_room_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Reservation room does not exist.';
        END IF;

        SELECT reservation_id INTO v_overlap_reservation_id
        FROM reservations
        WHERE room_id = NEW.room_id
          AND reservation_id <> OLD.reservation_id
          AND status <> 'cancelled'
          AND check_in_date < NEW.check_out_date
          AND check_out_date > NEW.check_in_date
        LIMIT 1
        FOR UPDATE;

        IF v_overlap_reservation_id IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'The room is already reserved for part of this date range.';
        END IF;
    END IF;
END//

CREATE TRIGGER trg_reservations_after_insert
AFTER INSERT ON reservations
FOR EACH ROW
BEGIN
    INSERT INTO operation_logs (
        actor_user_id, entity_name, entity_id, action_name, details
    ) VALUES (
        NEW.created_by_user_id,
        'reservations',
        NEW.reservation_id,
        'created',
        JSON_OBJECT(
            'room_id', NEW.room_id,
            'guest_id', NEW.guest_id,
            'check_in_date', NEW.check_in_date,
            'check_out_date', NEW.check_out_date,
            'status', NEW.status
        )
    );
END//

CREATE TRIGGER trg_reservations_after_update
AFTER UPDATE ON reservations
FOR EACH ROW
BEGIN
    IF NEW.status = 'checked_in' AND OLD.status <> 'checked_in' THEN
        INSERT INTO stays (reservation_id, actual_check_in, status)
        VALUES (NEW.reservation_id, CURRENT_DATE, 'active');

        UPDATE rooms
        SET room_status = 'occupied'
        WHERE room_id = NEW.room_id;
    END IF;

    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        UPDATE stays
        SET actual_check_out = COALESCE(
                actual_check_out,
                DATE_ADD(actual_check_in, INTERVAL 1 DAY)
            ),
            status = 'completed'
        WHERE reservation_id = NEW.reservation_id;

        UPDATE rooms
        SET room_status = 'cleaning'
        WHERE room_id = NEW.room_id;

        INSERT INTO cleaning_records (room_id, reservation_id, status)
        VALUES (NEW.room_id, NEW.reservation_id, 'pending');
    END IF;

    INSERT INTO operation_logs (
        actor_user_id, entity_name, entity_id, action_name, details
    ) VALUES (
        NEW.created_by_user_id,
        'reservations',
        NEW.reservation_id,
        'updated',
        JSON_OBJECT(
            'old_status', OLD.status,
            'new_status', NEW.status,
            'room_id', NEW.room_id
        )
    );
END//

CREATE TRIGGER trg_payments_after_insert
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
    INSERT INTO operation_logs (
        entity_name, entity_id, action_name, details
    ) VALUES (
        'payments',
        NEW.payment_id,
        'created',
        JSON_OBJECT(
            'stay_id', NEW.stay_id,
            'amount', NEW.amount,
            'currency', NEW.currency,
            'status', NEW.payment_status
        )
    );
END//

CREATE TRIGGER trg_payments_after_update
AFTER UPDATE ON payments
FOR EACH ROW
BEGIN
    INSERT INTO operation_logs (
        entity_name, entity_id, action_name, details
    ) VALUES (
        'payments',
        NEW.payment_id,
        'updated',
        JSON_OBJECT(
            'old_status', OLD.payment_status,
            'new_status', NEW.payment_status,
            'amount', NEW.amount
        )
    );
END//

CREATE TRIGGER trg_cleaning_records_before_update
BEFORE UPDATE ON cleaning_records
FOR EACH ROW
BEGIN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        SET NEW.started_at = COALESCE(NEW.started_at, CURRENT_TIMESTAMP);
        SET NEW.completed_at = COALESCE(NEW.completed_at, CURRENT_TIMESTAMP);
    END IF;
END//

CREATE TRIGGER trg_cleaning_records_after_update
AFTER UPDATE ON cleaning_records
FOR EACH ROW
BEGIN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        UPDATE rooms
        SET room_status = 'available'
        WHERE room_id = NEW.room_id
          AND room_status = 'cleaning';
    END IF;
END//

CREATE PROCEDURE sp_find_available_rooms(
    IN p_check_in DATE,
    IN p_check_out DATE,
    IN p_room_type_id BIGINT UNSIGNED
)
BEGIN
    IF p_check_in IS NULL OR p_check_out IS NULL OR p_check_out <= p_check_in THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A valid check-in and check-out date range is required.';
    END IF;

    SELECT
        r.room_id,
        r.room_number,
        r.floor_number,
        r.room_status,
        rt.room_type_id,
        rt.type_name,
        rt.capacity
    FROM rooms AS r
    JOIN room_types AS rt ON rt.room_type_id = r.room_type_id
    WHERE r.room_status <> 'maintenance'
      AND (r.room_status <> 'cleaning' OR p_check_in > CURRENT_DATE)
      AND (p_room_type_id IS NULL OR r.room_type_id = p_room_type_id)
      AND NOT EXISTS (
          SELECT 1
          FROM reservations AS res
          WHERE res.room_id = r.room_id
            AND res.status <> 'cancelled'
            AND res.check_in_date < p_check_out
            AND res.check_out_date > p_check_in
      )
    ORDER BY r.room_number;
END//

CREATE PROCEDURE sp_calculate_stay_total(
    IN p_stay_id BIGINT UNSIGNED,
    OUT p_total DECIMAL(12, 2)
)
BEGIN
    DECLARE v_room_type_id BIGINT UNSIGNED;
    DECLARE v_check_in DATE;
    DECLARE v_check_out DATE;
    DECLARE v_priced_nights INT DEFAULT 0;
    DECLARE v_expected_nights INT DEFAULT 0;

    SELECT
        rm.room_type_id,
        st.actual_check_in,
        COALESCE(st.actual_check_out, res.check_out_date)
    INTO v_room_type_id, v_check_in, v_check_out
    FROM stays AS st
    JOIN reservations AS res ON res.reservation_id = st.reservation_id
    JOIN rooms AS rm ON rm.room_id = res.room_id
    WHERE st.stay_id = p_stay_id;

    IF v_check_in IS NULL OR v_check_out IS NULL OR v_check_out <= v_check_in THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'The stay does not have a valid billable date range.';
    END IF;

    SET v_expected_nights = DATEDIFF(v_check_out, v_check_in);

    WITH RECURSIVE nights (night_date) AS (
        SELECT v_check_in
        UNION ALL
        SELECT DATE_ADD(night_date, INTERVAL 1 DAY)
        FROM nights
        WHERE DATE_ADD(night_date, INTERVAL 1 DAY) < v_check_out
    )
    SELECT
        COALESCE(SUM(sp.nightly_rate), 0.00),
        COUNT(sp.seasonal_price_id)
    INTO p_total, v_priced_nights
    FROM nights AS n
    LEFT JOIN seasonal_prices AS sp
        ON sp.room_type_id = v_room_type_id
       AND n.night_date >= sp.valid_from
       AND n.night_date < sp.valid_to;

    IF v_priced_nights <> v_expected_nights THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A seasonal room rate is missing for one or more stay nights.';
    END IF;

    SELECT p_total + COALESCE(SUM(quantity * unit_price), 0.00)
    INTO p_total
    FROM stay_services
    WHERE stay_id = p_stay_id;
END//

CREATE PROCEDURE sp_monthly_report(
    IN p_year SMALLINT UNSIGNED,
    IN p_month TINYINT UNSIGNED
)
BEGIN
    DECLARE v_period_start DATE;
    DECLARE v_period_end DATE;
    DECLARE v_days_in_month INT;

    IF p_year IS NULL OR p_month IS NULL OR p_month < 1 OR p_month > 12 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A valid report year and month are required.';
    END IF;

    SET v_period_start = STR_TO_DATE(
        CONCAT(p_year, '-', LPAD(p_month, 2, '0'), '-01'),
        '%Y-%m-%d'
    );
    SET v_period_end = DATE_ADD(v_period_start, INTERVAL 1 MONTH);
    SET v_days_in_month = DATEDIFF(v_period_end, v_period_start);

    SELECT
        p_year AS report_year,
        p_month AS report_month,
        COALESCE((
            SELECT SUM(
                DATEDIFF(
                    LEAST(res.check_out_date, v_period_end),
                    GREATEST(res.check_in_date, v_period_start)
                )
            )
            FROM reservations AS res
            WHERE res.status IN ('confirmed', 'checked_in', 'completed')
              AND res.check_in_date < v_period_end
              AND res.check_out_date > v_period_start
        ), 0) AS occupied_room_nights,
        (SELECT COUNT(*) FROM rooms) * v_days_in_month AS available_room_nights,
        ROUND(
            COALESCE((
                SELECT SUM(
                    DATEDIFF(
                        LEAST(res.check_out_date, v_period_end),
                        GREATEST(res.check_in_date, v_period_start)
                    )
                )
                FROM reservations AS res
                WHERE res.status IN ('confirmed', 'checked_in', 'completed')
                  AND res.check_in_date < v_period_end
                  AND res.check_out_date > v_period_start
            ), 0) /
            NULLIF((SELECT COUNT(*) FROM rooms) * v_days_in_month, 0) * 100,
            2
        ) AS occupancy_rate_percent,
        COALESCE((
            SELECT SUM(pay.amount)
            FROM payments AS pay
            WHERE pay.payment_status = 'paid'
              AND pay.paid_at >= v_period_start
              AND pay.paid_at < v_period_end
        ), 0.00) AS revenue
    ;
END//

CREATE PROCEDURE sp_check_out(
    IN p_reservation_id BIGINT UNSIGNED,
    IN p_payment_method VARCHAR(24),
    OUT p_total DECIMAL(12, 2)
)
BEGIN
    DECLARE v_stay_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_reservation_status VARCHAR(20) DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_payment_method IS NULL
       OR p_payment_method NOT IN ('cash', 'card', 'transfer') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Unsupported payment method.';
    END IF;

    START TRANSACTION;

    SELECT status INTO v_reservation_status
    FROM reservations
    WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF v_reservation_status <> 'checked_in' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only an active checked-in reservation can be checked out.';
    END IF;

    SELECT stay_id INTO v_stay_id
    FROM stays
    WHERE reservation_id = p_reservation_id
      AND status = 'active'
    FOR UPDATE;

    IF v_stay_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No active stay exists for this reservation.';
    END IF;

    UPDATE stays
    SET actual_check_out = GREATEST(
            CURRENT_DATE,
            DATE_ADD(actual_check_in, INTERVAL 1 DAY)
        )
    WHERE stay_id = v_stay_id;

    CALL sp_calculate_stay_total(v_stay_id, p_total);

    UPDATE stays
    SET total_amount = p_total
    WHERE stay_id = v_stay_id;

    INSERT INTO payments (
        stay_id, amount, payment_method, payment_status, paid_at
    ) VALUES (
        v_stay_id, p_total, p_payment_method, 'paid', CURRENT_TIMESTAMP
    );

    UPDATE reservations
    SET status = 'completed'
    WHERE reservation_id = p_reservation_id;

    COMMIT;
END//

CREATE VIEW vw_today_arrivals_departures AS
SELECT
    res.reservation_id,
    res.status AS reservation_status,
    res.check_in_date,
    res.check_out_date,
    g.guest_id,
    g.first_name,
    g.last_name,
    g.email,
    r.room_id,
    r.room_number,
    CASE
        WHEN res.check_in_date = CURRENT_DATE THEN 'arrival'
        ELSE 'departure'
    END AS schedule_type
FROM reservations AS res
JOIN guests AS g ON g.guest_id = res.guest_id
JOIN rooms AS r ON r.room_id = res.room_id
WHERE res.status IN ('confirmed', 'checked_in')
  AND (res.check_in_date = CURRENT_DATE OR res.check_out_date = CURRENT_DATE)//

CREATE VIEW vw_room_status_and_last_cleaning AS
SELECT
    r.room_id,
    r.room_number,
    r.floor_number,
    r.room_status,
    rt.type_name AS room_type,
    rt.capacity,
    MAX(cr.completed_at) AS last_cleaned_at
FROM rooms AS r
JOIN room_types AS rt ON rt.room_type_id = r.room_type_id
LEFT JOIN cleaning_records AS cr
    ON cr.room_id = r.room_id
   AND cr.status = 'completed'
GROUP BY
    r.room_id,
    r.room_number,
    r.floor_number,
    r.room_status,
    rt.type_name,
    rt.capacity//

DELIMITER ;
