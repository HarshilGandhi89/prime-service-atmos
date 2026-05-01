"""SQLAlchemy ORM models.

`prime_requests` records every successful execution. Storing only the
*preview* of returned primes (first 20) keeps the table compact while
preserving an auditable trail of who asked for what and when.
"""
from __future__ import annotations

from datetime import datetime, timezone
from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    Index,
    Integer,
    String,
    Text,
)

from .database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class PrimeRequest(Base):
    __tablename__ = "prime_requests"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    range_low = Column(BigInteger, nullable=False)
    range_high = Column(BigInteger, nullable=False)
    count = Column(Integer, nullable=False)
    duration_ms = Column(Integer, nullable=False)
    client_ip = Column(String(64), nullable=True)
    primes_preview = Column(Text, nullable=True)  # first 20 primes, comma-separated
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=_utcnow,
    )

    __table_args__ = (
        Index("ix_prime_requests_created_at", "created_at"),
        Index("ix_prime_requests_range", "range_low", "range_high"),
    )

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"<PrimeRequest id={self.id} "
            f"[{self.range_low},{self.range_high}] count={self.count}>"
        )
