import asyncio
from fastapi import WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
from typing import List, Optional
import random
import time

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
    holeCards: List[String] = []
    communityCards: List[String] = []
    numPlayers: int = 0
    dealerPosition: int = 0
    myPosition: int = 0
    activeAction: Optional[str] = None
    potSize: float = 0.0

# Replicate the GTOSuggestion struct from iOS
class GTOSuggestion(BaseModel):
    action: str
    raiseSize: Optional[float] = None
    ev: Optional[float] = None
    confidence: Optional[float] = None
    reasoning: Optional[str] = None

@app.post("/v1/solve", response_model=GTOSuggestion)
async def solve_poker_state(state: PokerState, authorization: Optional[str] = Header(None)):
    """
    Mock endpoint that simulates a GTO solver analysis.
    """
    # Simulate API Key check
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    
    # Simulate processing time of a solver or LLM (1 to 3 seconds)
    time.sleep(random.uniform(1.0, 3.0))
    
    # Generate some dynamic mock logic based on the state
    if not state.holeCards:
        return GTOSuggestion(
            action="Fold",
            ev=-0.5,
            confidence=0.99,
            reasoning="No hole cards detected. Defaulting to fold."
        )
        
    has_pair = len(state.holeCards) == 2 and state.holeCards[0][0] == state.holeCards[1][0]
    
    if has_pair:
        return GTOSuggestion(
            action="Raise",
            raiseSize=state.potSize * 0.75 if state.potSize > 0 else 3.0,
            ev=4.5,
            confidence=0.85,
            reasoning=f"You have a pocket pair ({state.holeCards[0]}). Raising is mathematically optimal."
        )
    else:
        return GTOSuggestion(
            action="Call",
            ev=0.1,
            confidence=0.6,
            reasoning="Playing speculatively with connectors."
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

