from typing import Dict
from pydantic import BaseModel

class PlayerStats(BaseModel):
    hands_played: int = 0
    voluntarily_put_in_pot: int = 0
    pre_flop_raises: int = 0

    @property
    def vpip(self) -> float:
        return (self.voluntarily_put_in_pot / self.hands_played * 100) if self.hands_played > 0 else 0.0

    @property
    def pfr(self) -> float:
        return (self.pre_flop_raises / self.hands_played * 100) if self.hands_played > 0 else 0.0

    def profile_label(self) -> str:
        if self.hands_played < 10:
            return "Unknown (need more data)"
        if self.vpip > 30 and self.pfr > 20:
            return "Loose Aggressive (LAG)"
        if self.vpip > 30 and self.pfr <= 10:
            return "Loose Passive (Calling Station)"
        if self.vpip <= 20 and self.pfr >= 15:
            return "Tight Aggressive (TAG)"
        return "Tight Passive (Nit)"

class PlayerHUDMemory:
    """
    A simple in-memory store for player statistics across a session.
    In a real app, this would be backed by a database (SQLite, Postgres, etc.)
    """
    def __init__(self):
        self.players: Dict[str, PlayerStats] = {}

    def update_player(self, player_id: str, played_hand: bool, voluntarily_entered: bool, pre_flop_raise: bool):
        if player_id not in self.players:
            self.players[player_id] = PlayerStats()
            
        stats = self.players[player_id]
        if played_hand:
            stats.hands_played += 1
        if voluntarily_entered:
            stats.voluntarily_put_in_pot += 1
        if pre_flop_raise:
            stats.pre_flop_raises += 1

    def get_player(self, player_id: str) -> PlayerStats:
        return self.players.get(player_id, PlayerStats())

hud_memory = PlayerHUDMemory()
