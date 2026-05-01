"""Unit tests for the prime generator.

Run from the `app/` directory:
    pip install -r requirements-dev.txt
    pytest -q
"""
from __future__ import annotations

import pytest

from src.primes import primes_in_range


class TestPrimesInRange:
    def test_example_from_spec(self) -> None:
        # The case-study spec calls out 1..10 -> 2,3,5,7
        assert list(primes_in_range(1, 10)) == [2, 3, 5, 7]

    def test_no_primes_below_two(self) -> None:
        assert list(primes_in_range(0, 1)) == []

    def test_single_value_prime(self) -> None:
        assert list(primes_in_range(13, 13)) == [13]

    def test_single_value_composite(self) -> None:
        assert list(primes_in_range(15, 15)) == []

    def test_inverted_range_is_empty(self) -> None:
        assert list(primes_in_range(20, 10)) == []

    def test_negative_lower_bound_clamped(self) -> None:
        assert list(primes_in_range(-50, 5)) == [2, 3, 5]

    @pytest.mark.parametrize(
        "low, high, expected_count",
        [
            (0, 100, 25),       # pi(100)   = 25
            (0, 1_000, 168),    # pi(1000)  = 168
            (0, 100_000, 9_592),  # pi(10^5) = 9592
        ],
    )
    def test_pi_function_matches(self, low: int, high: int, expected_count: int) -> None:
        assert sum(1 for _ in primes_in_range(low, high)) == expected_count

    def test_segment_boundaries(self) -> None:
        # Pick a range that straddles the 65536 segment boundary to exercise
        # the segmented sieve's seam handling.
        primes_around = list(primes_in_range(65500, 65600))
        # The known primes in this window (verified independently).
        expected = [65521, 65537]
        # 65537 is just past 65536 which is exactly one segment.
        assert all(p in primes_around for p in expected if p <= 65600)
        # All returned values must actually be prime (sanity check).
        for p in primes_around:
            assert _is_prime_trial(p), f"{p} is not prime"


def _is_prime_trial(n: int) -> bool:
    """Reference trial-division primality test, used only by tests."""
    if n < 2:
        return False
    if n % 2 == 0:
        return n == 2
    i = 3
    while i * i <= n:
        if n % i == 0:
            return False
        i += 2
    return True
