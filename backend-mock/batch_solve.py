#!/usr/bin/env python3
"""
Batch GTO solver — pre-computes common poker spots and populates the cache.

Generates the top ~200 strategically distinct flop textures paired with
standard IP/OOP ranges and bet sizes, solves each via TexasSolver (or the
mock fallback), and stores the results in the SQLite cache.

Usage:
    python batch_solve.py                     # solve all, store in gto_cache.db
    python batch_solve.py --db custom.db      # custom cache path
    python batch_solve.py --dry-run           # print boards without solving
    python batch_solve.py --limit 50          # only solve first 50 boards
"""

import argparse
import asyncio
import itertools
import sys
import time
from typing import List, Tuple

from solver_wrapper import SolverInput, solve as solver_solve
from cache import SolutionCache

# ---------------------------------------------------------------------------
# Flop texture generation
# ---------------------------------------------------------------------------

RANKS = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]
SUITS = ["h", "d", "c", "s"]

# Representative flop textures (rank patterns).  We pick one suited
# combination per pattern to keep the count manageable while still
# covering the strategic diversity.
#
# Categories:
#   - Monotone (3 of one suit)
#   - Two-tone (2 of one suit)
#   - Rainbow (all different suits)
#   - Paired boards
#   - Connected / gapped
#   - Broadway heavy vs low boards

def _generate_flop_textures() -> List[List[str]]:
    """
    Return ~200 strategically distinct flops covering the major texture
    categories: high/low, connected/disconnected, monotone/two-tone/rainbow,
    and paired boards.
    """
    flops: List[List[str]] = []

    # --- High-card flops (broadways) ---
    high_ranks = ["A", "K", "Q", "J", "T"]
    for combo in itertools.combinations(high_ranks, 3):
        # Rainbow
        flops.append([f"{combo[0]}h", f"{combo[1]}d", f"{combo[2]}c"])
        # Two-tone
        flops.append([f"{combo[0]}h", f"{combo[1]}h", f"{combo[2]}d"])

    # --- Mid-card flops ---
    mid_ranks = ["T", "9", "8", "7", "6"]
    for combo in itertools.combinations(mid_ranks, 3):
        flops.append([f"{combo[0]}s", f"{combo[1]}d", f"{combo[2]}c"])
        flops.append([f"{combo[0]}s", f"{combo[1]}s", f"{combo[2]}d"])

    # --- Low-card flops ---
    low_ranks = ["7", "6", "5", "4", "3", "2"]
    for combo in itertools.combinations(low_ranks, 3):
        flops.append([f"{combo[0]}h", f"{combo[1]}c", f"{combo[2]}d"])

    # --- Monotone flops (3 of same suit) ---
    monotone_combos = [
        ["A", "K", "T"], ["Q", "J", "9"], ["T", "8", "6"],
        ["9", "7", "5"], ["8", "6", "3"], ["7", "5", "2"],
        ["A", "5", "3"], ["K", "9", "4"], ["Q", "8", "2"],
    ]
    for combo in monotone_combos:
        flops.append([f"{combo[0]}h", f"{combo[1]}h", f"{combo[2]}h"])

    # --- Paired flops ---
    for r in RANKS:
        other = "A" if r != "A" else "K"
        flops.append([f"{r}h", f"{r}d", f"{other}c"])

    # --- Connected flops ---
    connected = [
        ["J", "T", "9"], ["T", "9", "8"], ["9", "8", "7"],
        ["8", "7", "6"], ["7", "6", "5"], ["6", "5", "4"],
        ["5", "4", "3"], ["4", "3", "2"], ["A", "K", "Q"],
        ["K", "Q", "J"], ["Q", "J", "T"],
    ]
    for combo in connected:
        # Rainbow
        flops.append([f"{combo[0]}h", f"{combo[1]}d", f"{combo[2]}c"])
        # Two-tone flush draw
        flops.append([f"{combo[0]}h", f"{combo[1]}h", f"{combo[2]}d"])

    # --- Ace-high dry flops ---
    ace_dry = [
        ["A", "7", "2"], ["A", "8", "3"], ["A", "9", "4"],
        ["A", "6", "2"], ["A", "T", "3"], ["A", "5", "2"],
    ]
    for combo in ace_dry:
        flops.append([f"{combo[0]}s", f"{combo[1]}d", f"{combo[2]}c"])

    # Deduplicate (sort cards within each flop for comparison)
    seen = set()
    unique: List[List[str]] = []
    for flop in flops:
        key = tuple(sorted(flop))
        if key not in seen:
            seen.add(key)
            unique.append(flop)

    return unique


# ---------------------------------------------------------------------------
# Bet size / stack configurations
# ---------------------------------------------------------------------------

CONFIGS: List[Tuple[float, float, str, str]] = [
    # (pot, effective_stack, bet_sizes, raise_sizes)
    (10.0, 100.0, "50,100", "60"),
    (20.0, 100.0, "33,66,100", "60"),
    (10.0, 50.0, "50,100", "60"),
]

# Standard ranges
DEFAULT_RANGE_IP = (
    "AA,KK,QQ,JJ,TT,99,88,77,66,55,44,33,22,"
    "AKs,AQs,AJs,ATs,A9s,A8s,A7s,A6s,A5s,A4s,A3s,A2s,"
    "AKo,AQo,AJo,ATo,"
    "KQs,KJs,KTs,K9s,KQo,KJo,"
    "QJs,QTs,Q9s,QJo,"
    "JTs,J9s,JTo,"
    "T9s,T8s,98s,97s,87s,76s,65s,54s"
)

DEFAULT_RANGE_OOP = (
    "AA,KK,QQ,JJ,TT,99,88,77,66,55,44,33,22,"
    "AKs,AQs,AJs,ATs,A9s,A8s,A7s,A6s,A5s,A4s,A3s,A2s,"
    "AKo,AQo,AJo,ATo,"
    "KQs,KJs,KTs,K9s,KQo,"
    "QJs,QTs,JTs,T9s,98s,87s,76s,65s"
)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def batch_solve(
    db_path: str = "gto_cache.db",
    dry_run: bool = False,
    limit: int = 0,
) -> None:
    flops = _generate_flop_textures()
    if limit > 0:
        flops = flops[:limit]

    total_jobs = len(flops) * len(CONFIGS)
    print(f"Generated {len(flops)} unique flop textures × {len(CONFIGS)} configs = {total_jobs} jobs")

    if dry_run:
        for i, flop in enumerate(flops):
            print(f"  [{i+1:3d}] {','.join(flop)}")
        return

    cache = SolutionCache(db_path)
    await cache.init()

    existing = await cache.count()
    print(f"Cache already contains {existing} entries")

    solved = 0
    skipped = 0
    errors = 0
    start = time.monotonic()

    for i, flop in enumerate(flops):
        for pot, stack, bet_sizes, raise_sizes in CONFIGS:
            inp = SolverInput(
                board=flop,
                range_ip=DEFAULT_RANGE_IP,
                range_oop=DEFAULT_RANGE_OOP,
                pot=pot,
                effective_stack=stack,
                bet_sizes_ip=bet_sizes,
                bet_sizes_oop=bet_sizes,
                raise_sizes_ip=raise_sizes,
                raise_sizes_oop=raise_sizes,
            )

            # Skip if already cached
            cached = await cache.lookup(inp)
            if cached is not None:
                skipped += 1
                continue

            try:
                result = await solver_solve(inp)
                await cache.store(inp, result)
                solved += 1
            except Exception as e:
                errors += 1
                print(f"  ERROR solving {','.join(flop)}: {e}")

        # Progress
        pct = (i + 1) / len(flops) * 100
        elapsed = time.monotonic() - start
        print(
            f"  [{i+1:3d}/{len(flops)}] {pct:5.1f}% | "
            f"solved={solved} skipped={skipped} errors={errors} | "
            f"{elapsed:.1f}s elapsed"
        )

    await cache.close()

    total_time = time.monotonic() - start
    final_count = existing + solved
    print(f"\nDone! {solved} new solutions cached ({skipped} skipped, {errors} errors)")
    print(f"Total cache entries: {final_count}")
    print(f"Total time: {total_time:.1f}s")


def main():
    parser = argparse.ArgumentParser(description="Batch GTO solver for cache population")
    parser.add_argument("--db", default="gto_cache.db", help="Cache database path")
    parser.add_argument("--dry-run", action="store_true", help="Print boards without solving")
    parser.add_argument("--limit", type=int, default=0, help="Limit number of flop textures")
    args = parser.parse_args()

    asyncio.run(batch_solve(db_path=args.db, dry_run=args.dry_run, limit=args.limit))


if __name__ == "__main__":
    main()
