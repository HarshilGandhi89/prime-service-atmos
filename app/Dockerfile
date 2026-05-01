# syntax=docker/dockerfile:1.6
#
# Multi-stage image for the Prime Service.
#
# Goals (mirroring the playbook's container best-practices):
#   * Single app per container.
#   * Smallest practical base image (python:3.12-slim).
#   * Non-root runtime user (UID/GID 10001).
#   * No build tools in the final layer.
#   * Healthcheck so ECS / docker-compose can detect bad deploys.
#
FROM python:3.12-slim AS builder
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# psycopg2-binary ships its own libpq, so we only need build essentials
# transiently (kept in builder stage and discarded).
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt


FROM python:3.12-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/install/bin:${PATH}"

# Non-root user and group.
RUN groupadd -g 10001 app \
 && useradd  -u 10001 -g 10001 -m -s /sbin/nologin app

COPY --from=builder /install /install

WORKDIR /opt/app
COPY src ./src
COPY tests ./tests

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz').status==200 else 1)"

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
