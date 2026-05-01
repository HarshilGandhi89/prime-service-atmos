"""FastAPI application entry point for the Prime Number Service.

Endpoints
---------
GET /healthz                 Liveness probe (no DB hit).
GET /readyz                  Readiness probe (DB SELECT 1).
GET /api/v1/primes           Compute primes in [low, high].
GET /api/v1/history          Recent execution history.

Security & operational notes
----------------------------
* The container does NOT bind to the host network in docker-compose.
  Inbound traffic must arrive via the WireGuard gateway sidecar.
* In AWS, the ECS service runs in private subnets. The only ingress
  path is Client VPN -> ALB (internal scheme) -> ECS task SG.
* Structured JSON logs are emitted on stdout; the platform (CloudWatch
  / journald) handles aggregation.
"""
from __future__ import annotations

import logging
import os
import time
from typing import List, Optional

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from .database import Base, engine, get_session
from .models import PrimeRequest
from .primes import primes_in_range


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format=(
        '{"ts":"%(asctime)s","level":"%(levelname)s",'
        '"logger":"%(name)s","msg":"%(message)s"}'
    ),
)
logger = logging.getLogger("prime-service")


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Prime Number Service",
    version="1.0.0",
    description=(
        "Generates prime numbers in a given inclusive range and records each "
        "execution in PostgreSQL."
    ),
)


@app.on_event("startup")
def _init_db() -> None:
    """Create tables on cold start.

    For production we recommend Alembic migrations gated behind the IaC
    pipeline; create_all is fine for the case-study scope.
    """
    Base.metadata.create_all(bind=engine)
    logger.info("Database schema verified")


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------
class PrimeQueryResponse(BaseModel):
    low: int
    high: int
    count: int
    duration_ms: int
    primes: List[int]


class HistoryItem(BaseModel):
    id: int
    range_low: int
    range_high: int
    count: int
    duration_ms: int
    client_ip: Optional[str] = None
    created_at: str


class HealthResponse(BaseModel):
    status: str
    version: str


# ---------------------------------------------------------------------------
# Operational endpoints
# ---------------------------------------------------------------------------
@app.get("/healthz", response_model=HealthResponse, tags=["ops"])
def healthz() -> HealthResponse:
    return HealthResponse(status="ok", version=app.version)


@app.get("/readyz", tags=["ops"])
def readyz(session: Session = Depends(get_session)):
    try:
        session.execute(text("SELECT 1"))
        return {"status": "ready"}
    except Exception as exc:  # noqa: BLE001
        logger.warning("readiness probe failed: %s", exc)
        raise HTTPException(status_code=503, detail="not ready")


# ---------------------------------------------------------------------------
# Business endpoints
# ---------------------------------------------------------------------------
MAX_RANGE = int(os.getenv("PRIME_MAX_RANGE", "10000000"))


@app.get(
    "/api/v1/primes",
    response_model=PrimeQueryResponse,
    tags=["primes"],
    summary="Compute primes in [low, high]",
)
def get_primes(
    request: Request,
    low: int = Query(..., ge=0, description="Lower bound (inclusive)"),
    high: int = Query(..., ge=0, description="Upper bound (inclusive)"),
    limit: Optional[int] = Query(
        None,
        ge=1,
        le=1_000_000,
        description="Optional cap on number of primes returned.",
    ),
    session: Session = Depends(get_session),
) -> PrimeQueryResponse:
    if high < low:
        raise HTTPException(status_code=400, detail="high must be >= low")
    if (high - low) > MAX_RANGE:
        raise HTTPException(
            status_code=400,
            detail=f"Range too large; max span is {MAX_RANGE}",
        )

    started = time.perf_counter()
    out: List[int] = []
    for p in primes_in_range(low, high):
        out.append(p)
        if limit is not None and len(out) >= limit:
            break
    duration_ms = int((time.perf_counter() - started) * 1000)

    record = PrimeRequest(
        range_low=low,
        range_high=high,
        count=len(out),
        duration_ms=duration_ms,
        client_ip=(request.client.host if request.client else None),
        primes_preview=",".join(str(x) for x in out[:20]),
    )
    session.add(record)
    session.commit()

    logger.info(
        "primes computed low=%s high=%s count=%s duration_ms=%s",
        low,
        high,
        len(out),
        duration_ms,
    )
    return PrimeQueryResponse(
        low=low,
        high=high,
        count=len(out),
        duration_ms=duration_ms,
        primes=out,
    )


@app.get(
    "/api/v1/history",
    response_model=List[HistoryItem],
    tags=["primes"],
    summary="Most recent executions",
)
def get_history(
    session: Session = Depends(get_session),
    limit: int = Query(20, ge=1, le=200),
) -> List[HistoryItem]:
    rows = (
        session.query(PrimeRequest)
        .order_by(PrimeRequest.created_at.desc())
        .limit(limit)
        .all()
    )
    return [
        HistoryItem(
            id=r.id,
            range_low=r.range_low,
            range_high=r.range_high,
            count=r.count,
            duration_ms=r.duration_ms,
            client_ip=r.client_ip,
            created_at=r.created_at.isoformat(),
        )
        for r in rows
    ]
