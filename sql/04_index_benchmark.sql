USE hotel_management;

-- MySQL 8.0.18+: compare the same reservation lookup with and without its index.
EXPLAIN ANALYZE
SELECT reservation_id
FROM reservations FORCE INDEX (idx_reservations_room_dates)
WHERE room_id = 1
  AND check_in_date < '2026-10-31'
  AND check_out_date > '2026-10-24';

EXPLAIN ANALYZE
SELECT reservation_id
FROM reservations IGNORE INDEX (idx_reservations_room_dates)
WHERE room_id = 1
  AND check_in_date < '2026-10-31'
  AND check_out_date > '2026-10-24';

-- Email lookup is backed by uq_guests_email; inspect its access path.
EXPLAIN ANALYZE
SELECT guest_id
FROM guests
WHERE email = 'misafir01@example.com';
