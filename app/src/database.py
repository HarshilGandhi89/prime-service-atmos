"""Database engine + session factory.

Uses SQLAlchemy 2.x. Connection string is taken from the DATABASE_URL
environment variable so the same image runs unchanged in:
  * docker-compose (postgres container at db:5432)
  * AWS ECS Fargate (RDS endpoint, fetched from Secrets Manager)
  * local pytest (sqlite, falls back when DATABASE_URL is unset)
"""
from __future__ import annotations

import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base


DEFAULT_URL = "postgresql+psycopg2://prime:prime@db:5432/primes"
DATABASE_URL = os.getenv("DATABASE_URL", DEFAULT_URL)

# `pool_pre_ping` avoids stale-connection errors after RDS failovers
# or NAT idle timeouts. `future=True` opts into SQLAlchemy 2.x semantics.
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
    future=True,
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    future=True,
)

Base = declarative_base()


def get_session():
    """FastAPI dependency that yields a scoped Session and always closes it."""
    s = SessionLocal()
    try:
        yield s
    finally:
        s.close()
