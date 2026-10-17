FROM apache/superset:6.0.0

USER root

RUN . /app/.venv/bin/activate && \
    uv pip install --no-cache-dir "trino[sqlalchemy]"

USER superset