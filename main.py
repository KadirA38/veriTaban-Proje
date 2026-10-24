import os

from flask import Flask, current_app
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from config import Config
from extensions import db


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

    return app


app = create_app()


if __name__ == "__main__":
    app.run(
        host=os.getenv("FLASK_HOST", "127.0.0.1"),
        port=int(os.getenv("FLASK_PORT", "5000")),
        debug=os.getenv("FLASK_DEBUG", "").lower() == "true",
    )
