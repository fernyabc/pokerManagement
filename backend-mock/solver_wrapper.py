"""
TexasSolver CLI wrapper.

Writes a temporary input file, invokes the `console_solver` binary,
and parses `output_result.json`.  If the binary is not found on $PATH
(or at TEXAS_SOLVER_BIN), falls back to a lightweight mock engine so
development can proceed without compiling the solver.
"""

import asyncio
import json
import os
import tempfile
import shutil
from dataclasses import dataclass, field
from typing import Dict, List, Optional

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class SolverInput:
    """Parameters accepted by the TexasSolver console binary."""
    board: List[str]                       # e.g. ["Qs", "Jh", "2h"]
    range_ip: str = "AA,KK,QQ,JJ,TT,99,88,77,66,55,44,33,22,AKs,AQs,AJs,ATs,A9s,A8s,A7s,A6s,A5s,A4s,A3s,A2s,AKo,AQo,AJo,ATo,KQs,KJs,KTs,K9s,KQo,KJo,QJs,QTs,Q9s,QJo,JTs,J9s,JTo,T9s,T8s,98s,97s,87s,76s,65s,54s"
    range_oop: str = "AA,KK,QQ,JJ,TT,99,88,77,66,55,44,33,22,AKs,AQs,AJs,ATs,A9s,A8s,A7s,A6s,A5s,A4s,A3s,A2s,AKo,AQo,AJo,ATo,KQs,KJs,KTs,K9s,KQo,QJs,QTs,JTs,T9s,98s,87s,76s,65s"
    pot: float = 10.0
    effective_stack: float = 100.0
    bet_sizes_ip: str = "50,100"           # comma-separated % of pot
    bet_sizes_oop: str = "50,100"
    raise_sizes_ip: str = "60"
    raise_sizes_oop: str = "60"
    accuracy: float = 0.5                  # exploitability threshold
    max_iterations: int = 200
    threads: int = 4


@dataclass
class SolverResult:
    """Parsed output from TexasSolver."""
    strategy: Dict[str, float] = field(default_factory=dict)   # e.g. {"Fold": 0.2, "Call": 0.5, "Raise": 0.3}
    ev: float = 0.0
    exploitability: float = 0.0
    iterations: int = 0
    raw: Optional[dict] = None


# ---------------------------------------------------------------------------
# Solver wrapper
# ---------------------------------------------------------------------------

_SOLVER_BIN = os.environ.get("TEXAS_SOLVER_BIN", "console_solver")


def _solver_available() -> bool:
    return shutil.which(_SOLVER_BIN) is not None


def _build_input_file(inp: SolverInput, path: str) -> None:
    """Write an input file in the format expected by console_solver."""
    board_str = ",".join(inp.board)
    lines = [
        f"set_board {board_str}",
        f"set_range_ip {inp.range_ip}",
        f"set_range_oop {inp.range_oop}",
        f"set_pot {inp.pot}",
        f"set_effective_stack {inp.effective_stack}",
        f"set_bet_sizes_ip {inp.bet_sizes_ip}",
        f"set_bet_sizes_oop {inp.bet_sizes_oop}",
        f"set_raise_sizes_ip {inp.raise_sizes_ip}",
        f"set_raise_sizes_oop {inp.raise_sizes_oop}",
        f"set_accuracy {inp.accuracy}",
        f"set_max_iterations {inp.max_iterations}",
        f"set_threads {inp.threads}",
        "build_tree",
        "start_solve",
        "dump_result",
    ]
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def _parse_result(result_path: str) -> SolverResult:
    """Parse output_result.json produced by console_solver."""
    with open(result_path) as f:
        data = json.load(f)

    # TexasSolver outputs per-hand strategies.  We aggregate across all hands
    # to get an overall fold/call/raise frequency.
    fold_sum = call_sum = raise_sum = total = 0.0

    # The output format has a nested structure; handle common layouts.
    strategies = data if isinstance(data, list) else data.get("strategy", data.get("root", []))
    if isinstance(strategies, dict):
        strategies = [strategies]

    for entry in strategies if isinstance(strategies, list) else []:
        actions = entry.get("actions", entry) if isinstance(entry, dict) else {}
        for action_name, freq in (actions.items() if isinstance(actions, dict) else []):
            lower = action_name.lower()
            if "fold" in lower:
                fold_sum += freq
            elif "call" in lower or "check" in lower:
                call_sum += freq
            elif "raise" in lower or "bet" in lower:
                raise_sum += freq
            total += freq

    if total > 0:
        strategy = {
            "Fold": round(fold_sum / total, 4),
            "Call": round(call_sum / total, 4),
            "Raise": round(raise_sum / total, 4),
        }
    else:
        strategy = {"Fold": 0.0, "Call": 0.0, "Raise": 0.0}

    return SolverResult(
        strategy=strategy,
        ev=data.get("ev", 0.0) if isinstance(data, dict) else 0.0,
        exploitability=data.get("exploitability", 0.0) if isinstance(data, dict) else 0.0,
        iterations=data.get("iterations", 0) if isinstance(data, dict) else 0,
        raw=data,
    )


async def solve(inp: SolverInput) -> SolverResult:
    """
    Run TexasSolver on the given input.

    Falls back to a mock engine when the binary is not installed.
    """
    if not _solver_available():
        return _mock_solve(inp)

    tmpdir = tempfile.mkdtemp(prefix="texassolver_")
    input_path = os.path.join(tmpdir, "input.txt")
    result_path = os.path.join(tmpdir, "output_result.json")

    try:
        _build_input_file(inp, input_path)

        proc = await asyncio.create_subprocess_exec(
            _SOLVER_BIN,
            "-i", input_path,
            cwd=tmpdir,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=300)

        if proc.returncode != 0:
            raise RuntimeError(
                f"console_solver exited with code {proc.returncode}: {stderr.decode()}"
            )

        if not os.path.exists(result_path):
            raise FileNotFoundError(f"Solver did not produce {result_path}")

        return _parse_result(result_path)

    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Mock fallback
# ---------------------------------------------------------------------------

def _mock_solve(inp: SolverInput) -> SolverResult:
    """Deterministic mock when TexasSolver binary is not available."""
    board = [c.upper() for c in inp.board]
    high_cards = sum(1 for c in board if c[0] in "AKQJ")

    if high_cards >= 2:
        strategy = {"Fold": 0.15, "Call": 0.45, "Raise": 0.40}
        ev = 3.2
    elif high_cards == 1:
        strategy = {"Fold": 0.25, "Call": 0.50, "Raise": 0.25}
        ev = 1.1
    else:
        strategy = {"Fold": 0.35, "Call": 0.45, "Raise": 0.20}
        ev = -0.5

    return SolverResult(
        strategy=strategy,
        ev=ev,
        exploitability=0.0,
        iterations=0,
        raw={"mock": True, "board": board},
    )
