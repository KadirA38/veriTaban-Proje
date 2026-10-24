USE hotel_management;

INSERT INTO room_types (type_name, description, capacity) VALUES
    ('Single', 'Tek kişilik standart oda.', 1),
    ('Double', 'İki kişilik standart oda.', 2),
    ('Twin', 'İki ayrı yataklı oda.', 2),
    ('Family', 'Aile konaklamasına uygun oda.', 4),
    ('Suite', 'Geniş oturma alanlı suit oda.', 3);

INSERT INTO rooms (room_number, room_type_id, floor_number)
SELECT
    CAST(100 + seq.n AS CHAR),
    MOD(seq.n - 1, 5) + 1,
    FLOOR((seq.n - 1) / 10) + 1
FROM (
    SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8
    UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL SELECT 12
    UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15 UNION ALL SELECT 16
    UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
) AS seq;

INSERT INTO seasonal_prices (
    room_type_id, season_name, valid_from, valid_to, nightly_rate, currency
)
SELECT room_type_id, 'Standard (2020-2026)', '2020-01-01', '2026-06-01', 1000.00, 'TRY'
FROM room_types;

INSERT INTO seasonal_prices (
    room_type_id, season_name, valid_from, valid_to, nightly_rate, currency
)
SELECT room_type_id, 'Summer 2026', '2026-06-01', '2026-09-01', 1500.00, 'TRY'
FROM room_types;

INSERT INTO seasonal_prices (
    room_type_id, season_name, valid_from, valid_to, nightly_rate, currency
)
SELECT room_type_id, 'Standard (2026-2035)', '2026-09-01', '2035-01-01', 1100.00, 'TRY'
FROM room_types;

INSERT INTO guests (first_name, last_name, email, phone)
WITH RECURSIVE guest_numbers (n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM guest_numbers WHERE n < 50
)
SELECT
    CONCAT('Misafir', LPAD(n, 2, '0')),
    CONCAT('Ornek', LPAD(n, 2, '0')),
    CONCAT('misafir', LPAD(n, 2, '0'), '@example.com'),
    CONCAT('+9055500', LPAD(n, 4, '0'))
FROM guest_numbers;

INSERT INTO extra_services (service_name, description, unit_price, currency) VALUES
    ('Breakfast', 'Günlük kahvaltı hizmeti.', 250.00, 'TRY'),
    ('Laundry', 'Çamaşır yıkama hizmeti.', 180.00, 'TRY'),
    ('Airport Transfer', 'Tek yön havaalanı transferi.', 700.00, 'TRY');

INSERT INTO reservations (
    guest_id, room_id, check_in_date, check_out_date, status
)
WITH RECURSIVE reservation_numbers (n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM reservation_numbers WHERE n < 200
)
SELECT
    MOD(n - 1, 50) + 1,
    MOD(n - 1, 20) + 1,
    DATE_SUB(CURRENT_DATE, INTERVAL (450 - FLOOR((n - 1) / 20) * 4) DAY),
    DATE_ADD(
        DATE_SUB(CURRENT_DATE, INTERVAL (450 - FLOOR((n - 1) / 20) * 4) DAY),
        INTERVAL 2 DAY
    ),
    'completed'
FROM reservation_numbers;

INSERT INTO stays (
    reservation_id, actual_check_in, actual_check_out, status, total_amount
)
SELECT
    res.reservation_id,
    res.check_in_date,
    res.check_out_date,
    'completed',
    SUM(sp.nightly_rate)
FROM reservations AS res
JOIN rooms AS r ON r.room_id = res.room_id
JOIN seasonal_prices AS sp
    ON sp.room_type_id = r.room_type_id
   AND res.check_in_date >= sp.valid_from
   AND DATE_SUB(res.check_out_date, INTERVAL 1 DAY) < sp.valid_to
WHERE res.status = 'completed'
GROUP BY
    res.reservation_id,
    res.check_in_date,
    res.check_out_date;

INSERT INTO payments (
    stay_id, amount, payment_method, payment_status, paid_at
)
SELECT
    st.stay_id,
    st.total_amount,
    'card',
    'paid',
    TIMESTAMP(st.actual_check_out, '12:00:00')
FROM stays AS st;

INSERT INTO staff (first_name, last_name, job_title, hired_at) VALUES
    ('Deneme', 'Resepsiyon', 'receptionist', '2024-01-01'),
    ('Deneme', 'Temizlik', 'housekeeping', '2024-01-01');
