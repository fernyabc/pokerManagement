# Product Requirements Document (PRD) - pokerManagement

## 1. Overview
`pokerManagement` is an iOS application designed to work in tandem with smart glasses (specifically targeting Ray-Ban Meta glasses and potentially other AR glasses). The system acts as a real-time poker assistant. Drawing inspiration from existing AR board game assistants (like AR-Mahjong-Assistant) and poker vision tools, it captures the state of a live poker game via the glasses' camera, analyzes the situation using GTO (Game Theory Optimal) solvers or LLM-based heuristics on a backend server, and discretely delivers actionable suggestions back to the user.

## 2. Inspiration & Reference Projects
This PRD is synthesized from the following reference architectures:
1. **AR-Mahjong-Assistant-preview:** Demonstrates using AR glasses to collect game states (hands, players, positions) and routing it to a backend solver for real-time suggestions.
2. **pokerglass:** Provides the foundational concept of integrating smart glasses specifically for live poker analysis and state detection.
3. **meta-vision-project:** Solves the hardware constraint of Ray-Ban Meta glasses by providing a "scrappy" vision pipeline workaround (e.g., streaming via WhatsApp/Instagram to intercept the camera feed).
4. **pokerAssist:** Demonstrates the backend analysis methodology, integrating poker state data with GTO solvers (like PioSolver) or AI models (like Gemini/GPT) to generate optimal play recommendations.

## 3. Core Features

### 3.1. Vision Pipeline & Hardware Integration
- **Target Hardware:** Ray-Ban Meta smart glasses (primary) with fallback to iPhone camera.
- **Image/Video Capture:** Since Ray-Ban Meta glasses do not provide direct camera APIs, the app will utilize the streaming workaround demonstrated in `meta-vision-project` (intercepting a live stream to extract frames).
- **State Detection (inspired by AR-Mahjong-Assistant & pokerglass):**
  - **Hole Cards:** Identify the user's two hole cards.
  - **Community Cards:** Identify Flop, Turn, and River cards on the board.
  - **Table State:** Identify the number of players at the table, their relative positions to the dealer button, and the user's position.
  - **Action Tracking:** Attempt to track chip stacks, bet sizes, and player actions (fold, call, raise).

### 3.2. Backend Analysis & GTO Solver Integration
- **State Representation:** The iOS app formats the parsed visual data into a standardized poker state JSON payload.
- **Backend API:** A backend service receives the state and queries the analysis engine (inspired by `pokerAssist`).
- **Suggestion Generation:** The backend utilizes a GTO solver or a tuned LLM (e.g., Gemini 1.5 Pro / GPT-4o) to compute the expected value (EV) of various actions and returns the optimal play (Fold, Call, Raise to X).

### 3.3. Discrete Feedback Delivery
- **Audio Prompts:** The primary feedback mechanism will be discrete Text-to-Speech (TTS) routed directly into the Ray-Ban Meta glasses' built-in speakers via Bluetooth.
- **Companion iOS UI:** A SwiftUI dashboard on the iPhone to visualize the current hand state, display the exact mathematical breakdown of the GTO suggestion, and allow manual correction of vision errors if the glasses miss a card.

## 4. Architecture & Tech Stack
- **Client (iOS):** 
  - Language: Swift 6 / SwiftUI.
  - Frameworks: CoreBluetooth (for glasses connection/audio routing), AVFoundation (TTS), Vision / CoreML (for on-device ML preprocessing or card detection if applicable).
- **Computer Vision (Backend or Edge):**
  - OpenCV / YOLO models fine-tuned on playing cards and poker chips.
  - Stream interception pipeline (WebRTC or RTMP).
- **Backend/Solver:**
  - Node.js / Python FastAPI.
  - Integration with poker analysis engines (as seen in `pokerAssist`).

## 5. User Flow
1. **Setup:** User launches iOS app, puts on Ray-Ban Meta glasses, and starts the capture workaround stream.
2. **Pre-flop:** User looks at their hole cards. The vision pipeline extracts the frames, detects cards and dealer button, calculates position, and pings the backend. Audio feedback: *"Raise to 3 big blinds."*
3. **Post-flop:** Dealer deals flop. User looks at the board. App detects the 3 cards, merges with pre-flop state, estimates pot size. Audio feedback: *"Check, 100% frequency."*
4. **Correction:** If the camera misses a card, the user can tap their iPhone screen to manually input the card or action.

## 6. Risks & Limitations
- **Ray-Ban Meta Restrictions:** Dependence on streaming workarounds which can be fragile or break with Meta firmware updates.
- **Latency:** Vision processing -> Backend GTO -> TTS Audio must happen in under 3-5 seconds to be viable in a live game.
- **Accuracy:** Lighting conditions, card variations, and blocked views in live poker make 100% accurate vision tracking highly difficult.

## 7. Development Milestones
- **Phase 1:** iOS App UI scaffold, connection to a mock backend, and manual state input.
- **Phase 2:** Implement the vision pipeline workaround from `meta-vision-project` and integrate card detection from `pokerglass`.
- **Phase 3:** Backend solver integration based on `pokerAssist` logic and complete the end-to-end loop (Camera -> Backend -> Audio feedback).
- **Phase 4:** Advanced features (chip counting, automated action tracking, player profiling) similar to `AR-Mahjong-Assistant`.

## 8. Future / Advanced Features (Roadmap & TODOs)

### 8.1. Advanced Computer Vision Pipeline
- [ ] **CoreML YOLOv8 Integration:** Replace Apple Vision stubs with a trained object-detection model (`yolov8-playing-cards.mlmodel`) to detect cards in real-time.
- [ ] **Chip Stack & Pot Counting:** Train the model to identify poker chips by color/size to estimate the exact pot size and opponent chip stacks visually without manual input.
- [ ] **Automated Action Tracking:** Visually track when a player tosses chips into the middle or mucks their cards to automatically update the state (Fold, Call, Raise).
- [ ] **Dealer Button & Position Detection:** Detect the physical dealer button on the table to automatically calculate user position (UTG, Hijack, Button, etc.).

### 8.2. Live Stream Interception (Ray-Ban Meta Workaround)
- [ ] **WebRTC / RTMP Server Setup:** Implement stream-ripping logic. Set up a local server to intercept a private Instagram/WhatsApp live stream from the glasses and feed raw frames directly into the iOS VisionService.

### 8.3. Backend & GTO Solver Upgrades
- [ ] **PioSolver / GTO+ Integration:** Write a Python bridge in the backend that translates the JSON poker state into a PioSolver script, runs the simulation, and parses the exact EV matrix back to the iOS app.
- [ ] **LLM Heuristics Engine:** Integrate OpenAI's `GPT-4o` or Google's `Gemini 1.5 Pro` into the backend. The LLM can interpret board states and explain *why* a play is good in plain English.
- [ ] **Player Profiling (HUD):** Keep a running database of opponents. Track their VPIP (Voluntarily Put in Pot) and PFR (Pre-Flop Raise) over the session, allowing the GTO solver to adjust its suggestions based on whether the opponent is "tight" or "loose".

### 8.4. Stealth & Feedback Mechanisms
- [ ] **Apple Watch Companion App:** If audio TTS is too risky or loud, build a watchOS companion app that delivers suggestions via stealthy haptic taps (e.g., 1 tap = Fold, 2 taps = Call, 3 taps = Raise).
- [ ] **Lock Screen / Dynamic Island UI:** Implement iOS Live Activities to glance at the iPhone resting on the table to see the GTO matrix without unlocking the phone.
- [ ] **AR Visual Overlays:** Support glasses with physical displays (like Brilliant Labs *Frame* or XREAL) to draw AR overlays (EV percentages floating above the cards) like the *AR-Mahjong-Assistant*.

### 8.5. Session Management & Analytics
- [ ] **Hand History Logger:** Automatically save every detected hand, the board runout, action taken, and the GTO suggestion to a local database (CoreData/SwiftData) for post-game review and leak analysis.
