import unittest
from unittest.mock import patch

from sqlalchemy import text

from extensions import db
from main import create_app


class ReservationApiTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(
            {
                "TESTING": True,
                "SECRET_KEY": "test-only-secret",
                "SQLALCHEMY_DATABASE_URI": "sqlite://",
            }
        )
        self.client = self.app.test_client()
        with self.app.app_context():
            db.session.execute(
                text("CREATE TABLE rooms (room_id INTEGER PRIMARY KEY)")
            )
            db.session.execute(
                text(
                    "CREATE TABLE guests ("
                    "guest_id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    "first_name TEXT NOT NULL, last_name TEXT NOT NULL, "
                    "email TEXT NOT NULL UNIQUE, phone TEXT)"
                )
            )
            db.session.execute(
                text(
                    "CREATE TABLE reservations ("
                    "reservation_id INTEGER PRIMARY KEY AUTOINCREMENT, "
                    "guest_id INTEGER NOT NULL, room_id INTEGER NOT NULL, "
                    "check_in_date DATE NOT NULL, check_out_date DATE NOT NULL, "
                    "special_requests TEXT, status TEXT NOT NULL)"
                )
            )
            db.session.execute(text("INSERT INTO rooms (room_id) VALUES (7)"))
            db.session.commit()

    def tearDown(self):
        with self.app.app_context():
            db.session.remove()
            db.engine.dispose()

    def test_room_availability_returns_rooms_and_dates(self):
        rooms = [
            {
                "room_id": 7,
                "room_number": "204",
                "floor_number": 2,
                "room_status": "available",
                "room_type_id": 3,
                "type_name": "Double",
                "capacity": 2,
            }
        ]
        with patch("main._find_available_rooms", return_value=rooms):
            response = self.client.get(
                "/api/rooms/availability",
                query_string={
                    "check_in_date": "2026-11-10",
                    "check_out_date": "2026-11-12",
                    "room_type_id": "3",
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.get_json(),
            {
                "check_in_date": "2026-11-10",
                "check_out_date": "2026-11-12",
                "rooms": rooms,
            },
        )

    def test_room_availability_rejects_invalid_date_range(self):
        response = self.client.get(
            "/api/rooms/availability",
            query_string={
                "check_in_date": "2026-11-12",
                "check_out_date": "2026-11-10",
            },
        )

        self.assertEqual(response.status_code, 400)

    def test_create_reservation_creates_guest_and_reservation(self):
        with patch(
            "main._find_available_rooms",
            return_value=[{"room_id": 7}],
        ):
            response = self.client.post(
                "/api/reservations",
                json={
                    "room_id": 7,
                    "check_in_date": "2026-11-10",
                    "check_out_date": "2026-11-12",
                    "guest": {
                        "first_name": "Ada",
                        "last_name": "Yilmaz",
                        "email": "ada@example.com",
                        "phone": "+90 555 000 00 00",
                    },
                    "special_requests": "Quiet room",
                },
            )

        self.assertEqual(response.status_code, 201)
        body = response.get_json()
        self.assertEqual(body["reservation_id"], 1)
        self.assertEqual(body["guest_id"], 1)
        self.assertEqual(body["room_id"], 7)
        self.assertEqual(body["status"], "pending")
        with self.app.app_context():
            reservation = db.session.execute(
                text(
                    "SELECT guest_id, room_id, check_in_date, check_out_date, "
                    "special_requests, status FROM reservations"
                )
            ).one()
            self.assertEqual(reservation[0], 1)
            self.assertEqual(reservation[1], 7)
            self.assertEqual(reservation[4], "Quiet room")
            self.assertEqual(reservation[5], "pending")

    def test_create_reservation_rejects_unavailable_room(self):
        with patch("main._find_available_rooms", return_value=[]):
            response = self.client.post(
                "/api/reservations",
                json={
                    "room_id": 7,
                    "check_in_date": "2026-11-10",
                    "check_out_date": "2026-11-12",
                    "guest": {
                        "first_name": "Ada",
                        "last_name": "Yilmaz",
                        "email": "ada@example.com",
                    },
                },
            )

        self.assertEqual(response.status_code, 409)
        with self.app.app_context():
            guest_count = db.session.execute(
                text("SELECT COUNT(*) FROM guests")
            ).scalar_one()
            reservation_count = db.session.execute(
                text("SELECT COUNT(*) FROM reservations")
            ).scalar_one()
            self.assertEqual(guest_count, 0)
            self.assertEqual(reservation_count, 0)


if __name__ == "__main__":
    unittest.main()
