import os

from dotenv import load_dotenv
from sqlalchemy.engine import URL


load_dotenv()


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_DATABASE_URI = os.getenv("DATABASE_URL")

    if not SQLALCHEMY_DATABASE_URI and all(
        os.getenv(key) for key in ("DB_USER", "DB_HOST", "DB_NAME")
    ):
        port = os.getenv("DB_PORT")
        SQLALCHEMY_DATABASE_URI = URL.create(
            "mysql+pymysql",
            username=os.getenv("DB_USER"),
            password=os.getenv("DB_PASSWORD", ""),
            host=os.getenv("DB_HOST"),
            port=int(port) if port else None,
            database=os.getenv("DB_NAME"),
            query={"charset": "utf8mb4"},
        ).render_as_string(hide_password=False)
