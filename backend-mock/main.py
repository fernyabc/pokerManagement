import asyncio
import json
from contextlib import asynccontextmanager
from fastapi import WebSocket, WebSocketDisconnect, Depends
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
from typing import List, Optional
from sqlalchemy.orm import Session

from player_profile import hud_memory
from llm_engine import LLMHeuristicsEngine
from solver_wrapper import SolverInput, solve as solver_solve
from database import init_db, get_db
from models import HandHistory


# ---------------------------------------------------------------------------
# App lifecycle
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="Poker GTO Solver API", lifespan=lifespan)

# Setup for serving the HTML template
templates = Jinja2Templates(directory="templates")


# ---------------------------------------------------------------------------
# WebSocket connection manager
# ---------------------------------------------------------------------------

class ConnectionManager:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: str, sender: WebSocket):
        for connection in self.active_connections:
            if connection is not sender:
                await connection.send_text(message)

manager = ConnectionManager()


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class PokerState(BaseModel):
    holeCards: List[str] = []
    communityCards: List[str] = []
    numPlayers: int = 0
    dealerPosition: int = 0
    myPosition: int = 0
    activeAction: Optional[str] = None
    potSize: float = 0.0

class PlayerActionUpdate(BaseModel):
    player_id: str
    played_hand: bool
    voluntarily_entered: bool
    pre_flop_raise: bool

class GTOSuggestion(BaseModel):
    action: str
    raiseSize: Optional[float] = None
    ev: Optional[float] = None
    confidence: Optional[float] = None
    reasoning: Optional[str] = None

class SolveRequest(BaseModel):
    """Request body for the TexasSolver endpoint."""
    board: List[str]                       # e.g. ["Qs", "Jh", "2h"]
    range_ip: Optional[str] = None
    range_oop: Optional[str] = None
    pot: float = 10.0
    effective_stack: float = 100.0
    bet_sizes_ip: str = "50,100"
    bet_sizes_oop: str = "50,100"
    raise_sizes_ip: str = "60"
    raise_sizes_oop: str = "60"
    accuracy: float = 0.5
    max_iterations: int = 200

class SolveResponse(BaseModel):
    strategy: dict                        # {"Fold": 0.2, "Call": 0.5, "Raise": 0.3}
    ev: float
    exploitability: float
    iterations: int

class LLMSolveRequest(BaseModel):
    """Request body for the LLM preflop/multiway endpoint."""
    holeCards: List[str]
    communityCards: List[str] = []
    position: str = "BTN"
    numPlayers: int = 6
    potSize: float = 1.5
    facingRaise: bool = False
    raiseAmount: float = 0.0
    facingBet: float = 0.0

class LLMSolveResponse(BaseModel):
    action: str
    reasoning: str

class HandLogRequest(BaseModel):
    """Request body for logging a completed hand."""
    round_id: str
    hero_hand: str                        # e.g. "Ah,Kd"
    community_cards_flop: str = ""
    community_cards_turn: str = ""
    community_cards_river: str = ""
    player_actions_preflop: str = ""      # JSON string
    player_actions_flop: str = ""
    player_actions_turn: str = ""
    player_actions_river: str = ""
    pot_size: float = 0.0
    gto_suggestion: str = ""              # JSON string
    result: str = ""


# ---------------------------------------------------------------------------
# Auth helper
# ---------------------------------------------------------------------------

def _check_auth(authorization: Optional[str]) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")


# ---------------------------------------------------------------------------
# Endpoints — HUD
# ---------------------------------------------------------------------------

@app.post("/v1/hud/update")
async def update_player_hud(update: PlayerActionUpdate, authorization: Optional[str] = Header(None)):
    _check_auth(authorization)
    hud_memory.update_player(
        player_id=update.player_id,
        played_hand=update.played_hand,
        voluntarily_entered=update.voluntarily_entered,
        pre_flop_raise=update.pre_flop_raise,
    )
    return hud_memory.get_player(update.player_id).dict()


# ---------------------------------------------------------------------------
# Endpoints — Legacy mock solver (existing /v1/solve)
# ---------------------------------------------------------------------------

@app.post("/v1/solve", response_model=GTOSuggestion)
async def solve_poker_state(state: PokerState, authorization: Optional[str] = Header(None)):
    _check_auth(authorization)

    if not state.holeCards:
        return GTOSuggestion(
            action="Fold",
            ev=-0.5,
            confidence=0.99,
            reasoning="No hole cards detected. Defaulting to fold.",
        )

    active_opponent_stats = hud_memory.get_player("Seat_1")
    profile_dict = {
        "label": active_opponent_stats.profile_label(),
        "vpip": active_opponent_stats.vpip,
        "pfr": active_opponent_stats.pfr,
    }

    has_pair = len(state.holeCards) == 2 and state.holeCards[0][0] == state.holeCards[1][0]

    if has_pair:
        base_action = "Raise"
        base_ev = 4.5
        base_conf = 0.85
        base_size = state.potSize * 0.75 if state.potSize > 0 else 3.0
        if "Nit" in profile_dict["label"]:
            base_ev -= 1.0
        elif "Calling Station" in profile_dict["label"]:
            base_size *= 1.5
            base_ev += 2.0
    else:
        base_action = "Call"
        base_ev = 0.1
        base_conf = 0.6
        base_size = None

    reasoning = await LLMHeuristicsEngine.analyze_board(
        hole_cards=state.holeCards,
        community_cards=state.communityCards,
        pot_size=state.potSize,
        opponents_profile=profile_dict,
        gto_action=base_action,
    )

    return GTOSuggestion(
        action=base_action,
        raiseSize=base_size,
        ev=base_ev,
        confidence=base_conf,
        reasoning=reasoning,
    )


# ---------------------------------------------------------------------------
# Endpoints — TexasSolver wrapper  (Task 1)
# ---------------------------------------------------------------------------

@app.post("/solve", response_model=SolveResponse)
async def solve_with_texas_solver(req: SolveRequest, authorization: Optional[str] = Header(None)):
    """Heads-up postflop GTO solve via TexasSolver (or mock fallback)."""
    _check_auth(authorization)

    if len(req.board) < 3:
        raise HTTPException(status_code=422, detail="Board must have at least 3 cards (flop).")

    inp = SolverInput(
        board=req.board,
        pot=req.pot,
        effective_stack=req.effective_stack,
        bet_sizes_ip=req.bet_sizes_ip,
        bet_sizes_oop=req.bet_sizes_oop,
        raise_sizes_ip=req.raise_sizes_ip,
        raise_sizes_oop=req.raise_sizes_oop,
        accuracy=req.accuracy,
        max_iterations=req.max_iterations,
    )
    if req.range_ip:
        inp.range_ip = req.range_ip
    if req.range_oop:
        inp.range_oop = req.range_oop

    result = await solver_solve(inp)

    return SolveResponse(
        strategy=result.strategy,
        ev=result.ev,
        exploitability=result.exploitability,
        iterations=result.iterations,
    )


# ---------------------------------------------------------------------------
# Endpoints — LLM preflop + multiway  (Task 8)
# ---------------------------------------------------------------------------

@app.post("/solve/llm", response_model=LLMSolveResponse)
async def solve_llm(req: LLMSolveRequest, authorization: Optional[str] = Header(None)):
    """Preflop or multiway analysis via LLM (falls back to static charts)."""
    _check_auth(authorization)

    is_preflop = len(req.communityCards) == 0
    is_multiway = req.numPlayers >= 3 and not is_preflop

    if is_preflop:
        result = await LLMHeuristicsEngine.analyze_preflop(
            hole_cards=req.holeCards,
            position=req.position,
            num_players=req.numPlayers,
            pot_size=req.potSize,
            facing_raise=req.facingRaise,
            raise_amount=req.raiseAmount,
        )
    elif is_multiway:
        result = await LLMHeuristicsEngine.analyze_multiway(
            hole_cards=req.holeCards,
            community_cards=req.communityCards,
            position=req.position,
            num_players=req.numPlayers,
            pot_size=req.potSize,
            facing_bet=req.facingBet,
        )
    else:
        # Heads-up postflop — use the existing board analysis
        result = await LLMHeuristicsEngine.analyze_preflop(
            hole_cards=req.holeCards,
            position=req.position,
            num_players=req.numPlayers,
            pot_size=req.potSize,
            facing_raise=req.facingRaise,
            raise_amount=req.raiseAmount,
        )

    return LLMSolveResponse(action=result["action"], reasoning=result["reasoning"])


# ---------------------------------------------------------------------------
# Endpoints — Hand history logging  (Task 7)
# ---------------------------------------------------------------------------

@app.post("/log_hand")
async def log_hand(req: HandLogRequest, authorization: Optional[str] = Header(None), db: Session = Depends(get_db)):
    """Persist a completed poker round to the database."""
    _check_auth(authorization)

    record = HandHistory(
        round_id=req.round_id,
        hero_hand=req.hero_hand,
        community_cards_flop=req.community_cards_flop,
        community_cards_turn=req.community_cards_turn,
        community_cards_river=req.community_cards_river,
        player_actions_preflop=req.player_actions_preflop,
        player_actions_flop=req.player_actions_flop,
        player_actions_turn=req.player_actions_turn,
        player_actions_river=req.player_actions_river,
        pot_size=req.pot_size,
        gto_suggestion=req.gto_suggestion,
        result=req.result,
    )
    db.add(record)
    db.commit()
    db.refresh(record)

    return {"id": record.id, "round_id": record.round_id, "status": "saved"}


@app.get("/hands")
async def list_hands(limit: int = 50, db: Session = Depends(get_db)):
    """Retrieve recent hand history records."""
    hands = db.query(HandHistory).order_by(HandHistory.timestamp.desc()).limit(limit).all()
    return [
        {
            "id": h.id,
            "round_id": h.round_id,
            "hero_hand": h.hero_hand,
            "community_cards_flop": h.community_cards_flop,
            "pot_size": h.pot_size,
            "result": h.result,
            "timestamp": h.timestamp.isoformat() if h.timestamp else None,
        }
        for h in hands
    ]


# ---------------------------------------------------------------------------
# Health & root
# ---------------------------------------------------------------------------

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/", response_class=HTMLResponse)
async def read_root():
    with open("templates/index.html") as f:
        return HTMLResponse(content=f.read(), status_code=200)


# ---------------------------------------------------------------------------
# WebSocket signaling relay
# ---------------------------------------------------------------------------

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            await manager.broadcast(data, websocket)
    except WebSocketDisconnect:
        manager.disconnect(websocket)
