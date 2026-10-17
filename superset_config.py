
import os

# Секретный ключ Superset.
# Замени значение на собственную случайную строку перед использованием.
SECRET_KEY = os.environ.get(
    "SUPERSET_SECRET_KEY",
    "change-this-to-a-long-random-secret-key"
)

# Настройки приложения
APP_NAME = "Lakehouse Superset"

# Язык интерфейса
BABEL_DEFAULT_LOCALE = "en"

# Часовой пояс
BABEL_DEFAULT_TIMEZONE = "Europe/Berlin"

# Безопасность сессий
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SECURE = False  # True, если настроен HTTPS
SESSION_COOKIE_SAMESITE = "Lax"

# Поддержка подключения к базам данных через SQLAlchemy
SQLALCHEMY_TRACK_MODIFICATIONS = False
