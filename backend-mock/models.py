"""
SQLAlchemy models for the poker backend.
"""

import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Float, Text, DateTime
from database import Base


class HandHistory(Base):
    """One row per completed poker round."""
    __tablename__ = "hand_history"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    round_id = Column(String, nullable=False, index=True)
    hero_hand = Column(String, nullable=False)                # e.g. "Ah,Kd"
    community_cards_flop = Column(String, default="")         # e.g. "Qs,Jh,2h"
    community_cards_turn = Column(String, default="")         # e.g. "7c"
    community_cards_river = Column(String, default="")        # e.g. "3s"
    player_actions_preflop = Column(Text, default="")         # JSON string
    player_actions_flop = Column(Text, default="")
    player_actions_turn = Column(Text, default="")
    player_actions_river = Column(Text, default="")
    pot_size = Column(Float, default=0.0)
    gto_suggestion = Column(Text, default="")                 # JSON string
    result = Column(String, default="")                       # e.g. "won", "lost", "folded"
    timestamp = Column(DateTime, default=lambda: datetime.now(timezone.utc))
