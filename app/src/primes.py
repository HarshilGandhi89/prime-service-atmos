"""Prime number generation utilities.

Uses a segmented Sieve of Eratosthenes so that:
  * Memory stays bounded (O(sqrt(high) + SEGMENT)) regardless of `high`.
  * Large ranges (e.g., 10^7+) complete in seconds without OOM.

The implementation is deliberately written from first principles. See
the playbook (Section 3 - Application Architecture) for the algorithmic
rationale and complexity discussion.
"""
from __future__ import annotations

import math
from typing import Iterator, List


def _sieve_upto(limit: int) -> List[int]:
    """Return all primes p where 2 <= p <= limit using a basic sieve.

    Used to seed the segmented sieve with primes up to sqrt(high).
    """
    if limit < 2:
        return []
    is_prime = bytearray(b"\x01") * (limit + 1)
    is_prime[0] = 0
    is_prime[1] = 0
    p = 2
    while p * p <= limit:
        if is_prime[p]:
            start = p * p
            step = p
            # Mark multiples of p starting at p*p; lower multiples
            # are already crossed out by smaller primes.
            for j in range(start, limit + 1, step):
                is_prime[j] = 0
        p += 1
    return [i for i, v in enumerate(is_prime) if v]


SEGMENT_SIZE = 1 << 16  # 65,536 — fits in L2 cache on most modern CPUs


def primes_in_range(low: int, high: int) -> Iterator[int]:
    """Yield every prime p with low <= p <= high in ascending order.

    Bounds are inclusive. Negative or zero bounds are tolerated:
    primes are >= 2 by definition, so the lower bound is clamped.
    """
    if high < 2 or high < low:
        return
    low = max(low, 2)

    sqrt_high = int(math.isqrt(high))
    base_primes = _sieve_upto(sqrt_high)

    seg_low = low
    while seg_low <= high:
        seg_high = min(seg_low + SEGMENT_SIZE - 1, high)
        size = seg_high - seg_low + 1
        sieve = bytearray(b"\x01") * size

        for p in base_primes:
            # First multiple of p that is >= seg_low and >= p*p
            start = max(p * p, ((seg_low + p - 1) // p) * p)
            for j in range(start, seg_high + 1, p):
                sieve[j - seg_low] = 0

        for i in range(size):
            if sieve[i]:
                yield seg_low + i

        seg_low = seg_high + 1
