import asyncio
from fastapi import WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
from typing import List, Optional
import random

from player_profile import hud_memory
from llm_engine import LLMHeuristicsEngine

app = FastAPI(title="Poker GTO Solver Mock API")

# Setup for serving the HTML template
templates = Jinja2Templates(directory="templates")

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

# Replicate the DetectedPokerState struct from iOS
class PokerState(BaseModel):
    holeCards: List[str] = []
    communityCards: List[str] = []
    numPlayers: int = 0
    dealerPosition: int = 0
    myPosition: int = 0
    activeAction: Optional[str] = None
    potSize: float = 0.0

# Request body for tracking player actions (HUD Update)
class PlayerActionUpdate(BaseModel):
    player_id: str
    played_hand: bool
    voluntarily_entered: bool
    pre_flop_raise: bool

# Replicate the GTOSuggestion struct from iOS
class GTOSuggestion(BaseModel):
    action: str
    raiseSize: Optional[float] = None
    ev: Optional[float] = None
    confidence: Optional[float] = None
    reasoning: Optional[str] = None

@app.post("/v1/hud/update")
async def update_player_hud(update: PlayerActionUpdate, authorization: Optional[str] = Header(None)):
    """
    Endpoint to log an opponent's action to update their VPIP/PFR profile.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    
    hud_memory.update_player(
        player_id=update.player_id,
        played_hand=update.played_hand,
        voluntarily_entered=update.voluntarily_entered,
        pre_flop_raise=update.pre_flop_raise
    )
    return hud_memory.get_player(update.player_id).dict()

@app.post("/v1/solve", response_model=GTOSuggestion)
async def solve_poker_state(state: PokerState, authorization: Optional[str] = Header(None)):
    """
    Endpoint that simulates a GTO solver analysis and augments it with LLM reasoning.
    """
    # Simulate API Key check
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    
    if not state.holeCards:
        return GTOSuggestion(
            action="Fold",
            ev=-0.5,
            confidence=0.99,
            reasoning="No hole cards detected. Defaulting to fold."
        )
        
    # Get active opponent profile (simulated as player "Seat_1" for this mock)
    # In a real app, the vision pipeline would identify which opponent is acting.
    active_opponent_stats = hud_memory.get_player("Seat_1")
    profile_dict = {
        "label": active_opponent_stats.profile_label(),
        "vpip": active_opponent_stats.vpip,
        "pfr": active_opponent_stats.pfr
    }

    has_pair = len(state.holeCards) == 2 and state.holeCards[0][0] == state.holeCards[1][0]
    
    # 1. Base GTO Matrix Engine Mock
    # (Here we'd bridge to PioSolver in a full implementation)
    if has_pair:
        base_action = "Raise"
        base_ev = 4.5
        base_conf = 0.85
        base_size = state.potSize * 0.75 if state.potSize > 0 else 3.0
        
        # Adjust EV based on player profile
        if "Nit" in profile_dict["label"]:
            base_ev -= 1.0 # Less EV raising against a Nit
        elif "Calling Station" in profile_dict["label"]:
            base_size *= 1.5 # Bet bigger against calling stations
            base_ev += 2.0
            
    else:
        base_action = "Call"
        base_ev = 0.1
        base_conf = 0.6
        base_size = None

    # 2. LLM Heuristics Engine Analysis
    # Translate the raw math into plain English coaching advice
    reasoning = await LLMHeuristicsEngine.analyze_board(
        hole_cards=state.holeCards,
        community_cards=state.communityCards,
        pot_size=state.potSize,
        opponents_profile=profile_dict,
        gto_action=base_action
    )

    return GTOSuggestion(
        action=base_action,
        raiseSize=base_size,
        ev=base_ev,
        confidence=base_conf,
        reasoning=reasoning
    )

@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/", response_class=HTMLResponse)
async def read_root():
    with open("templates/index.html") as f:
        return HTMLResponse(content=f.read(), status_code=200)

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            # Broadcast the signaling message to the other peer
            await manager.broadcast(data, websocket)
    except WebSocketDisconnect:
        manager.disconnect(websocket)
