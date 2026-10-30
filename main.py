import os
from datetime import date

from flask import Flask, current_app, request
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from config import Config
from extensions import db


def _parse_date(value):
    if not isinstance(value, str):
        return None
    try:
        parsed_date = date.fromisoformat(value)
    except ValueError:
        return None
    return parsed_date if parsed_date.isoformat() == value else None


def _parse_positive_int(value):
    if isinstance(value, bool):
        return None
    try:
        parsed_value = int(value)
    except (TypeError, ValueError):
        return None
    if parsed_value < 1 or str(parsed_value) != str(value):
        return None
    return parsed_value


def _find_available_rooms(session, check_in_date, check_out_date, room_type_id):
    result = session.execute(
        text(
            "CALL sp_find_available_rooms("
            ":check_in_date, :check_out_date, :room_type_id)"
        ),
        {
            "check_in_date": check_in_date,
            "check_out_date": check_out_date,
            "room_type_id": room_type_id,
        },
    )
    try:
        return [dict(room) for room in result.mappings().all()]
    finally:
        result.close()


def create_app(test_config=None):
    app = Flask(__name__)
    app.config.from_object(Config)
    if test_config:
        app.config.update(test_config)

    if not app.config["SQLALCHEMY_DATABASE_URI"]:
        raise RuntimeError(
            "Set DATABASE_URL or DB_USER, DB_PASSWORD, DB_HOST, and DB_NAME in .env."
        )
    if not app.config["SECRET_KEY"]:
        raise RuntimeError("Set SECRET_KEY in .env before starting the application.")

    db.init_app(app)

    @app.get("/api/health")
    def health_check():
        try:
            db.session.execute(text("SELECT 1"))
        except SQLAlchemyError:
            current_app.logger.exception("Database health check failed.")
            return {"status": "unavailable", "database": "unreachable"}, 503

        return {"status": "ok", "database": "connected"}, 200

    @app.get("/api/rooms/availability")
    def room_availability():
        check_in_date = _parse_date(request.args.get("check_in_date"))
        check_out_date = _parse_date(request.args.get("check_out_date"))
        room_type_value = request.args.get("room_type_id")
        room_type_id = (
            _parse_positive_int(room_type_value)
            if room_type_value is not None
            else None
        )

        if check_in_date is None or check_out_date is None:
            return {
                "error": "check_in_date and check_out_date must use YYYY-MM-DD."
            }, 400
        if check_out_date <= check_in_date:
            return {"error": "check_out_date must be after check_in_date."}, 400
        if room_type_value is not None and room_type_id is None:
            return {"error": "room_type_id must be a positive integer."}, 400

        try:
            rooms = _find_available_rooms(
                db.session, check_in_date, check_out_date, room_type_id
            )
        except SQLAlchemyError:
            current_app.logger.exception("Room availability search failed.")
            return {"error": "Room availability could not be checked."}, 503

        return {
            "check_in_date": check_in_date.isoformat(),
            "check_out_date": check_out_date.isoformat(),
            "rooms": rooms,
        }, 200

    @app.post("/api/reservations")
    def create_reservation():
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict):
            return {"error": "A JSON request body is required."}, 400

        room_id = _parse_positive_int(payload.get("room_id"))
        check_in_date = _parse_date(payload.get("check_in_date"))
        check_out_date = _parse_date(payload.get("check_out_date"))
        if room_id is None:
            return {"error": "room_id must be a positive integer."}, 400
        if check_in_date is None or check_out_date is None:
            return {
                "error": "check_in_date and check_out_date must use YYYY-MM-DD."
            }, 400
        if check_out_date <= check_in_date:
            return {"error": "check_out_date must be after check_in_date."}, 400

        guest_id_value = payload.get("guest_id")
        guest_details = payload.get("guest")
        if guest_id_value is not None and guest_details is not None:
            return {"error": "Provide either guest_id or guest, not both."}, 400
        guest_id = (
            _parse_positive_int(guest_id_value)
            if guest_id_value is not None
            else None
        )
        if guest_id_value is not None and guest_id is None:
            return {"error": "guest_id must be a positive integer."}, 400

        if guest_id is None:
            if not isinstance(guest_details, dict):
                return {"error": "Provide guest_id or guest details."}, 400
            first_name = guest_details.get("first_name")
            last_name = guest_details.get("last_name")
            email = guest_details.get("email")
            phone = guest_details.get("phone")
            if not all(
                isinstance(value, str) and value.strip()
                for value in (first_name, last_name, email)
            ):
                return {
                    "error": (
                        "guest.first_name, guest.last_name, and guest.email "
                        "are required."
                    )
                }, 400
            first_name = first_name.strip()
            last_name = last_name.strip()
            email = email.strip()
            if (
                len(first_name) > 100
                or len(last_name) > 100
                or len(email) > 254
                or "@" not in email
                or any(character.isspace() for character in email)
            ):
                return {"error": "Guest details are invalid."}, 400
            if phone is not None and (
                not isinstance(phone, str) or len(phone) > 32
            ):
                return {
                    "error": "guest.phone must be a string of at most 32 characters."
                }, 400
            phone = phone.strip() if phone else None

        special_requests = payload.get("special_requests")
        if special_requests is not None and (
            not isinstance(special_requests, str) or len(special_requests) > 1000
        ):
            return {
                "error": "special_requests must be a string of at most 1000 characters."
            }, 400

        try:
            room_result = db.session.execute(
                text("SELECT room_id FROM rooms WHERE room_id = :room_id"),
                {"room_id": room_id},
            )
            if room_result.first() is None:
                db.session.rollback()
                return {"error": "Room not found."}, 404

            if guest_id is not None:
                guest_result = db.session.execute(
                    text("SELECT guest_id FROM guests WHERE guest_id = :guest_id"),
                    {"guest_id": guest_id},
                )
                if guest_result.first() is None:
                    db.session.rollback()
                    return {"error": "Guest not found."}, 404
            else:
                guest_result = db.session.execute(
                    text("SELECT guest_id FROM guests WHERE email = :email"),
                    {"email": email},
                )
                existing_guest = guest_result.first()
                if existing_guest is not None:
                    guest_id = existing_guest[0]
                else:
                    guest_insert = db.session.execute(
                        text(
                            "INSERT INTO guests "
                            "(first_name, last_name, email, phone) "
                            "VALUES (:first_name, :last_name, :email, :phone)"
                        ),
                        {
                            "first_name": first_name,
                            "last_name": last_name,
                            "email": email,
                            "phone": phone,
                        },
                    )
                    guest_id = guest_insert.lastrowid

            available_rooms = _find_available_rooms(
                db.session, check_in_date, check_out_date, None
            )
            if not any(int(room["room_id"]) == room_id for room in available_rooms):
                db.session.rollback()
                return {"error": "Room is not available for the selected dates."}, 409

            reservation_result = db.session.execute(
                text(
                    "INSERT INTO reservations "
                    "(guest_id, room_id, check_in_date, check_out_date, "
                    "special_requests, status) "
                    "VALUES (:guest_id, :room_id, :check_in_date, :check_out_date, "
                    ":special_requests, 'pending')"
                ),
                {
                    "guest_id": guest_id,
                    "room_id": room_id,
                    "check_in_date": check_in_date.isoformat(),
                    "check_out_date": check_out_date.isoformat(),
                    "special_requests": special_requests,
                },
            )
            reservation_id = reservation_result.lastrowid
            db.session.commit()
        except IntegrityError as error:
            db.session.rollback()
            if "uq_guests_email" in str(error.orig):
                return {
                    "error": (
                        "A guest with this email already exists; "
                        "retry with guest_id."
                    )
                }, 409
            current_app.logger.exception("Reservation integrity check failed.")
            return {"error": "Reservation could not be created."}, 409
        except SQLAlchemyError as error:
            db.session.rollback()
            if "already reserved" in str(error.orig).lower():
                return {
                    "error": "Room is not available for the selected dates."
                }, 409
            current_app.logger.exception("Reservation creation failed.")
            return {"error": "Reservation could not be created."}, 503

        return {
            "reservation_id": reservation_id,
            "guest_id": guest_id,
            "room_id": room_id,
            "check_in_date": check_in_date.isoformat(),
            "check_out_date": check_out_date.isoformat(),
            "status": "pending",
        }, 201

    return app


app = create_app()


if __name__ == "__main__":
    app.run(
        host=os.getenv("FLASK_HOST", "127.0.0.1"),
        port=int(os.getenv("FLASK_PORT", "5000")),
        debug=os.getenv("FLASK_DEBUG", "").lower() == "true",
    )
