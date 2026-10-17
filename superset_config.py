import os

SECRET_KEY = os.environ.get(
    "SUPERSET_SECRET_KEY",
    "abubebabubebubabubaubaubaubaubauby"
)

APP_NAME = "Lakehouse Superset"

# Язык интерфейса
BABEL_DEFAULT_LOCALE = "en"
LANGUAGES = {
    "en": {
        "flag": "us",
        "name": "English",
    },
    "ru": {
        "flag": "ru",
        "name": "Русский",
    },
}

BABEL_DEFAULT_TIMEZONE = "Europe/Berlin"

# Метаданные самого Superset, а не таблицы Lakehouse
SQLALCHEMY_DATABASE_URI = (
    "sqlite:////app/superset_home/superset.db"
)

SQLALCHEMY_TRACK_MODIFICATIONS = False

SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SECURE = False
SESSION_COOKIE_SAMESITE = "Lax"
WTF_CSRF_ENABLED = True