import os
from openai import AsyncOpenAI
from typing import Optional

# Setup the client (expects OPENAI_API_KEY environment variable)
# If not present, we will fallback to mock reasoning
try:
    client = AsyncOpenAI()
except Exception:
    client = None

class LLMHeuristicsEngine:
    @staticmethod
    async def analyze_board(
        hole_cards: list,
        community_cards: list,
        pot_size: float,
        opponents_profile: dict,
        gto_action: str
    ) -> str:
        """
        Takes the current board state and the raw GTO action, and asks an LLM
        to provide a plain-English explanation for WHY the action makes sense.
        """
        
        # If no API key is set, use a mock response mechanism to simulate the LLM
        if not os.environ.get("OPENAI_API_KEY"):
            return LLMHeuristicsEngine._generate_mock_reasoning(hole_cards, community_cards, gto_action, opponents_profile)
        
        prompt = f"""
        You are an expert poker coach. Explain the mathematical and strategic reasoning 
        behind the following GTO-recommended action. Be concise, using no more than 2 sentences.
        
        Current State:
        - My Hole Cards: {hole_cards}
        - Community Cards: {community_cards}
        - Pot Size: ${pot_size}
        - Active Opponent Profile: {opponents_profile.get('label', 'Unknown')} 
          (VPIP: {opponents_profile.get('vpip', 0)}%, PFR: {opponents_profile.get('pfr', 0)}%)
          
        Recommended Action: {gto_action}
        
        Explanation:
        """
        
        try:
            response = await client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": "You are a professional poker player analyzing a hand."},
                    {"role": "user", "content": prompt}
                ],
                max_tokens=60,
                temperature=0.3
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            print(f"LLM API Error: {e}")
            return LLMHeuristicsEngine._generate_mock_reasoning(hole_cards, community_cards, gto_action, opponents_profile)

    @staticmethod
    def _generate_mock_reasoning(hole_cards: list, community_cards: list, gto_action: str, profile: dict) -> str:
        # Mock fallback based on simple heuristics
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
