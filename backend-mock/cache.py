"""
Pre-computed GTO solution cache — SQLite-backed.

Provides instant lookups for common poker spots that have been pre-solved
by TexasSolver in batch mode.  Cache keys are deterministic hashes of
the board + ranges + bet configuration so identical requests always hit.

Usage in main.py:
    from cache import solution_cache
    hit = await solution_cache.lookup(solver_input)
    if hit:
        return hit  # instant
    # else: invoke live solver, then store the result
    await solution_cache.store(solver_input, result)
"""

import hashlib
import json
import os
from typing import Optional

import aiosqlite

from solver_wrapper import SolverInput, SolverResult

# ---------------------------------------------------------------------------
# Cache key generation
# ---------------------------------------------------------------------------

def _cache_key(inp: SolverInput) -> str:
    """
    Produce a deterministic SHA-256 hex digest for a solver input.

    The key includes board, ranges, pot geometry, and bet sizing so that
    different configurations never collide.
    """
    canonical = json.dumps(
        {
            "board": sorted(c.upper() for c in inp.board),
            "range_ip": inp.range_ip,
            "range_oop": inp.range_oop,
            "pot": inp.pot,
            "effective_stack": inp.effective_stack,
            "bet_sizes_ip": inp.bet_sizes_ip,
            "bet_sizes_oop": inp.bet_sizes_oop,
            "raise_sizes_ip": inp.raise_sizes_ip,
            "raise_sizes_oop": inp.raise_sizes_oop,
        },
        sort_keys=True,
    )
    return hashlib.sha256(canonical.encode()).hexdigest()


# ---------------------------------------------------------------------------
# SolutionCache class
# ---------------------------------------------------------------------------

_DEFAULT_DB = os.environ.get("CACHE_DB_PATH", "gto_cache.db")

_CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS gto_cache (
    key       TEXT PRIMARY KEY,
    board     TEXT NOT NULL,
    strategy  TEXT NOT NULL,
    ev        REAL NOT NULL,
    exploitability REAL NOT NULL,
    iterations INTEGER NOT NULL,
    raw       TEXT
)
"""


class SolutionCache:
    """Async SQLite cache for pre-computed GTO solutions."""

    def __init__(self, db_path: str = _DEFAULT_DB):
        self._db_path = db_path
        self._db: Optional[aiosqlite.Connection] = None

    async def init(self) -> None:
        """Open the database and ensure the table exists."""
        self._db = await aiosqlite.connect(self._db_path)
        await self._db.execute(_CREATE_TABLE)
        await self._db.commit()

    async def close(self) -> None:
        if self._db:
            await self._db.close()
            self._db = None

    async def lookup(self, inp: SolverInput) -> Optional[SolverResult]:
        """Return a cached result or None."""
        if not self._db:
            return None
        key = _cache_key(inp)
        cursor = await self._db.execute(
            "SELECT strategy, ev, exploitability, iterations, raw FROM gto_cache WHERE key = ?",
            (key,),
        )
        row = await cursor.fetchone()
        if row is None:
            return None
        return SolverResult(
            strategy=json.loads(row[0]),
            ev=row[1],
            exploitability=row[2],
            iterations=row[3],
            raw=json.loads(row[4]) if row[4] else None,
        )

    async def store(self, inp: SolverInput, result: SolverResult) -> None:
        """Insert or replace a result in the cache."""
        if not self._db:
            return
        key = _cache_key(inp)
        board_str = ",".join(inp.board)
        await self._db.execute(
            """
            INSERT OR REPLACE INTO gto_cache (key, board, strategy, ev, exploitability, iterations, raw)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                key,
                board_str,
                json.dumps(result.strategy),
                result.ev,
                result.exploitability,
                result.iterations,
                json.dumps(result.raw) if result.raw else None,
            ),
        )
        await self._db.commit()

    async def count(self) -> int:
        """Return the number of cached entries."""
        if not self._db:
            return 0
        cursor = await self._db.execute("SELECT COUNT(*) FROM gto_cache")
        row = await cursor.fetchone()
        return row[0] if row else 0


# Module-level singleton
solution_cache = SolutionCache()
