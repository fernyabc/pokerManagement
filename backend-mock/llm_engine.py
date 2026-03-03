"""
LLM Heuristics Engine — poker coaching analysis.

Provides:
  1. analyze_board()    — postflop reasoning (existing, unchanged API)
  2. analyze_preflop()  — preflop action via LLM or static chart fallback
  3. analyze_multiway() — multiway pot analysis via LLM or heuristic fallback

When OPENAI_API_KEY is not set, every method falls back to deterministic
heuristic / chart-based responses.
"""

import os
from openai import AsyncOpenAI
from typing import Dict, List, Optional

# ---------------------------------------------------------------------------
# OpenAI client (optional)
# ---------------------------------------------------------------------------

try:
    client = AsyncOpenAI()
except Exception:
    client = None

# ---------------------------------------------------------------------------
# Standard GTO preflop opening charts (6-max, 100bb)
# ---------------------------------------------------------------------------

# Tier 1: always raise from any position
_TIER1 = {
    "AA", "KK", "QQ", "JJ", "TT", "AKs", "AQs", "AKo",
}

# Tier 2: raise from MP+
_TIER2 = {
    "99", "88", "AJs", "ATs", "AQo", "AJo", "KQs", "KJs",
}

# Tier 3: raise from CO+
_TIER3 = {
    "77", "66", "A9s", "A8s", "A7s", "A6s", "A5s", "A4s", "A3s", "A2s",
    "ATo", "KTs", "K9s", "KQo", "QJs", "QTs", "JTs", "T9s", "98s", "87s",
}

# Tier 4: raise from BTN only
_TIER4 = {
    "55", "44", "33", "22", "KJo", "KTo", "QJo", "Q9s", "J9s", "T8s",
    "97s", "86s", "76s", "65s", "54s",
}

_POSITIONS_RANK = {
    "UTG": 0, "UTG+1": 1, "MP": 2, "HJ": 2, "CO": 3, "BTN": 4, "SB": 5, "BB": 6,
}


def _normalize_hand(cards: List[str]) -> str:
    """Convert two hole cards like ['Ah','Kd'] into a canonical hand key like 'AKo'."""
    if len(cards) != 2:
        return ""
    r1, s1 = cards[0][0].upper(), cards[0][1].lower()
    r2, s2 = cards[1][0].upper(), cards[1][1].lower()

    rank_order = "AKQJT98765432"
    i1 = rank_order.index(r1) if r1 in rank_order else 99
    i2 = rank_order.index(r2) if r2 in rank_order else 99

    if i1 > i2:
        r1, r2 = r2, r1
        s1, s2 = s2, s1

    if r1 == r2:
        return f"{r1}{r2}"  # pair
    suited = "s" if s1 == s2 else "o"
    return f"{r1}{r2}{suited}"


def _chart_lookup(hand_key: str, position: str) -> Optional[str]:
    """Return 'Raise', 'Fold', or None (let LLM decide) based on static charts."""
    pos_rank = _POSITIONS_RANK.get(position.upper(), 2)

    if hand_key in _TIER1:
        return "Raise"
    if hand_key in _TIER2 and pos_rank >= 2:
        return "Raise"
    if hand_key in _TIER3 and pos_rank >= 3:
        return "Raise"
    if hand_key in _TIER4 and pos_rank >= 4:
        return "Raise"

    # SB/BB defense is complex — defer to LLM when available
    if position.upper() == "BB":
        return None

    return "Fold"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

class LLMHeuristicsEngine:
    # ------------------------------------------------------------------
    # 1. Postflop reasoning (original method, unchanged interface)
    # ------------------------------------------------------------------
    @staticmethod
    async def analyze_board(
        hole_cards: list,
        community_cards: list,
        pot_size: float,
        opponents_profile: dict,
        gto_action: str,
    ) -> str:
        if not os.environ.get("OPENAI_API_KEY"):
            return LLMHeuristicsEngine._generate_mock_reasoning(
                hole_cards, community_cards, gto_action, opponents_profile
            )

        prompt = (
            "You are an expert poker coach. Explain the mathematical and strategic reasoning "
            "behind the following GTO-recommended action. Be concise, using no more than 2 sentences.\n\n"
            f"Current State:\n"
            f"- My Hole Cards: {hole_cards}\n"
            f"- Community Cards: {community_cards}\n"
            f"- Pot Size: ${pot_size}\n"
            f"- Active Opponent Profile: {opponents_profile.get('label', 'Unknown')} "
            f"(VPIP: {opponents_profile.get('vpip', 0)}%, PFR: {opponents_profile.get('pfr', 0)}%)\n\n"
            f"Recommended Action: {gto_action}\n\n"
            f"Explanation:"
        )

        try:
            response = await client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": "You are a professional poker player analyzing a hand."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=60,
                temperature=0.3,
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            print(f"LLM API Error: {e}")
            return LLMHeuristicsEngine._generate_mock_reasoning(
                hole_cards, community_cards, gto_action, opponents_profile
            )

    # ------------------------------------------------------------------
    # 2. Preflop analysis  (Task 8)
    # ------------------------------------------------------------------
    @staticmethod
    async def analyze_preflop(
        hole_cards: List[str],
        position: str,
        num_players: int,
        pot_size: float = 1.5,
        facing_raise: bool = False,
        raise_amount: float = 0.0,
    ) -> Dict:
        """
        Return {"action": str, "reasoning": str} for a preflop spot.
        Falls back to static chart lookup when no API key is set.
        """
        hand_key = _normalize_hand(hole_cards)
        chart_action = _chart_lookup(hand_key, position)

        # --- Deterministic fallback (no LLM) ---
        if not os.environ.get("OPENAI_API_KEY"):
            action = chart_action or "Call"
            reasoning = LLMHeuristicsEngine._mock_preflop_reasoning(
                hand_key, position, action, num_players, facing_raise
            )
            return {"action": action, "reasoning": reasoning}

        # --- LLM path ---
        prompt = (
            "You are an expert 6-max No-Limit Hold'em coach.\n"
            "Given the preflop situation below, recommend exactly ONE action "
            "(Fold, Call, or Raise) and explain why in 2-3 sentences. "
            "Reference standard GTO opening ranges and position dynamics.\n\n"
            f"Hero hand: {hole_cards} ({hand_key})\n"
            f"Position: {position}\n"
            f"Players at table: {num_players}\n"
            f"Pot size: ${pot_size}\n"
            f"Facing raise: {'Yes — $' + str(raise_amount) if facing_raise else 'No (unopened)'}\n"
            f"GTO chart suggestion: {chart_action or 'borderline / position-dependent'}\n\n"
            "Your recommendation:"
        )

        try:
            response = await client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": "You are a professional poker coach specializing in preflop strategy."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=120,
                temperature=0.3,
            )
            text = response.choices[0].message.content.strip()
            action = _extract_action(text) or chart_action or "Call"
            return {"action": action, "reasoning": text}
        except Exception as e:
            print(f"LLM API Error (preflop): {e}")
            action = chart_action or "Call"
            return {
                "action": action,
                "reasoning": LLMHeuristicsEngine._mock_preflop_reasoning(
                    hand_key, position, action, num_players, facing_raise
                ),
            }

    # ------------------------------------------------------------------
    # 3. Multiway pot analysis  (Task 8)
    # ------------------------------------------------------------------
    @staticmethod
    async def analyze_multiway(
        hole_cards: List[str],
        community_cards: List[str],
        position: str,
        num_players: int,
        pot_size: float,
        facing_bet: float = 0.0,
    ) -> Dict:
        """
        Return {"action": str, "reasoning": str} for a multiway (3+ players) pot.
        Falls back to conservative heuristics when no API key is set.
        """
        hand_key = _normalize_hand(hole_cards)

        # --- Deterministic fallback ---
        if not os.environ.get("OPENAI_API_KEY"):
            return LLMHeuristicsEngine._mock_multiway(
                hole_cards, community_cards, position, num_players, pot_size, facing_bet
            )

        # --- LLM path ---
        prompt = (
            "You are an expert No-Limit Hold'em coach.\n"
            "Analyze this MULTIWAY pot (3+ players still in) and recommend ONE action "
            "(Fold, Check, Call, Bet, or Raise). Explain in 2-3 sentences, "
            "accounting for multiway dynamics (tighter ranges, less bluffing, "
            "stronger hands needed to continue).\n\n"
            f"Hero hand: {hole_cards} ({hand_key})\n"
            f"Community cards: {community_cards}\n"
            f"Position: {position}\n"
            f"Players in pot: {num_players}\n"
            f"Pot size: ${pot_size}\n"
            f"Facing bet: {'$' + str(facing_bet) if facing_bet > 0 else 'No (checked to us)'}\n\n"
            "Your recommendation:"
        )

        try:
            response = await client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": "You are a professional poker coach. In multiway pots, emphasize tighter play."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=150,
                temperature=0.3,
            )
            text = response.choices[0].message.content.strip()
            action = _extract_action(text) or "Check"
            return {"action": action, "reasoning": text}
        except Exception as e:
            print(f"LLM API Error (multiway): {e}")
            return LLMHeuristicsEngine._mock_multiway(
                hole_cards, community_cards, position, num_players, pot_size, facing_bet
            )

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------
    @staticmethod
    def _generate_mock_reasoning(hole_cards, community_cards, gto_action, profile):
        label = profile.get("label", "Unknown")
        if "Raise" in gto_action:
            if "Loose" in label:
                return f"Opponent is a {label}. Isolate them for value with your strong equity."
            return "You have the range advantage here. A raise applies maximum fold equity."
        elif "Call" in gto_action:
            if "Aggressive" in label:
                return f"Opponent is {label}. Keep their bluffs in the pot with a call."
            return "You have pot odds to draw, but not enough equity to inflate the pot."
        else:
            return "Your equity is too low against the opponent's range to continue."

    @staticmethod
    def _mock_preflop_reasoning(hand_key, position, action, num_players, facing_raise):
        if action == "Raise":
            return (
                f"{hand_key} is a strong opening hand from {position}. "
                f"With {num_players} players, raising for value and to thin the field."
            )
        elif action == "Call":
            return (
                f"{hand_key} is a borderline hand in {position}. "
                "Calling to see a flop with implied odds."
            )
        else:
            return (
                f"{hand_key} is too weak to play profitably from {position} "
                f"at a {num_players}-handed table."
            )

    @staticmethod
    def _mock_multiway(hole_cards, community_cards, position, num_players, pot_size, facing_bet):
        hand_key = _normalize_hand(hole_cards)
        high_cards = sum(1 for c in community_cards if c and c[0].upper() in "AKQJ")

        is_strong = hand_key and hand_key[:2] in ("AA", "KK", "QQ", "AK")
        if is_strong:
            action = "Raise" if facing_bet == 0 else "Call"
            reasoning = (
                f"With {hand_key} in a {num_players}-way pot, you have a premium holding. "
                "Bet for value since multiple players can pay you off."
            )
        elif facing_bet > 0 and facing_bet > pot_size * 0.5:
            action = "Fold"
            reasoning = (
                f"Facing a large bet in a {num_players}-way pot with {hand_key}. "
                "Multiway pots require stronger hands to continue — fold and wait for a better spot."
            )
        else:
            action = "Check" if facing_bet == 0 else "Call"
            reasoning = (
                f"{hand_key} has moderate equity on this board. "
                f"In a {num_players}-way pot, proceed cautiously."
            )
        return {"action": action, "reasoning": reasoning}


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

def _extract_action(text: str) -> Optional[str]:
    """Pull the first poker action keyword from LLM output."""
    text_lower = text.lower()
    for action in ("raise", "bet", "call", "check", "fold"):
        if action in text_lower:
            return action.capitalize()
    return None
