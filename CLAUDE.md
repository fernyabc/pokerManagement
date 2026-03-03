# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`pokerManagement` is an iOS 17+ application and Python FastAPI backend that serves as a real-time poker assistant. It intercepts a video stream from Ray-Ban Meta smart glasses (via WebRTC), runs card detection using Apple Vision / CoreML (YOLOv8), sends the parsed poker state to a GTO solver backend, and delivers actionable suggestions as TTS audio routed to the glasses via Bluetooth.

## Commands

### iOS App

The Xcode project is generated via XcodeGen — never edit `.xcodeproj` directly.

```bash
# Install XcodeGen (one-time)
brew install xcodegen

# Regenerate Xcode project after modifying project.yml
xcodegen generate

# Open in Xcode and build/run with Cmd+R
open pokerManagement.xcodeproj
```

### Backend Mock

```bash
# Install dependencies (one-time)
cd backend-mock && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt

# Start the backend server (runs on http://0.0.0.0:8000 with hot-reload)
./scripts/start-backend.sh

# Optional: enable LLM reasoning (falls back to mock heuristics if unset)
export OPENAI_API_KEY=sk-...
```

Backend API endpoints:
- `POST /v1/solve` — Main GTO analysis endpoint (requires `Bearer <token>` header)
- `POST /v1/hud/update` — Update opponent VPIP/PFR profile
- `GET /health` — Health check
- `WS /ws` — WebRTC signaling relay (used by the iOS app)

## Architecture

### iOS App (`pokerManagement/`)

The data flow is: **WebRTC stream → VisionService → BackendService → FeedbackService + LiveActivityManager**

**Key services (all `ObservableObject`):**
- `WebRTCStreamCaptureService` — Connects to the backend's WebSocket signaling server (`ws://localhost:8000/ws`) to establish a WebRTC peer connection and receive video frames from the Ray-Ban Meta stream. Calls `onFrameCaptured` callback with each `CMSampleBuffer`.
- `VisionService` — Processes frames. Prefers `CardDetectionService` (CoreML YOLOv8 model named `yolov8-playing-cards.mlmodelc`) when loaded; falls back to `VNRecognizeTextRequest` with a hardcoded mock state. Produces `DetectedPokerState`.
- `CardDetectionService` — Wraps the CoreML model. Sets `modelLoaded = true` only if the `.mlmodelc` file is present in the bundle. Cards in the bottom 30% of the frame are classified as hole cards; the rest as community cards.
- `BackendService` — Sends `DetectedPokerState` to whichever `GTOSolverProtocol` is active. Publishes `latestSuggestion: GTOSuggestion?`.
- `FeedbackService` — Converts a `GTOSuggestion` to TTS via `AVSpeechSynthesizer`. Audio routes automatically to paired Bluetooth (glasses) if connected.
- `LiveActivityManager` — Singleton managing the iOS Live Activity / Dynamic Island for stealth viewing.

**Solver protocol (`GTOSolverProtocol`):**
- `MockGTOSolver` — Default; returns hardcoded "Raise" suggestion after 1.5s delay.
- `ThirdPartyGTOSolver` — POSTs `DetectedPokerState` JSON to a configurable endpoint with a Bearer token.

Solver selection is driven by `@AppStorage` keys (`useMockSolver`, `solverEndpoint`, `solverAPIKey`) in `ContentView`.

**Models:**
- `DetectedPokerState` — Codable struct passed iOS → backend (hole cards, community cards, positions, pot size).
- `GTOSuggestion` — Codable struct returned backend → iOS (action, raiseSize, ev, confidence, reasoning).
- `HandHistory` — SwiftData `@Model` persisting each hand for the History tab.
- `PokerSuggestionAttributes` — `ActivityAttributes` shared between the main app and `PokerWidgetExtension`.

**Widget extension (`PokerWidget/`):**
- `PokerSuggestionLiveActivity` renders GTO suggestions on the lock screen and in the Dynamic Island. It shares `PokerSuggestionAttributes` from the main app's Models directory (declared as a source in both targets in `project.yml`).

### Backend Mock (`backend-mock/`)

- `main.py` — FastAPI app. `/v1/solve` runs a mock GTO matrix engine then calls `LLMHeuristicsEngine.analyze_board()` for plain-English reasoning. `/ws` is the WebRTC signaling relay.
- `llm_engine.py` — Uses `AsyncOpenAI` to call `gpt-4o` if `OPENAI_API_KEY` is set; otherwise returns deterministic mock reasoning strings.
- `player_profile.py` — In-memory `PlayerHUDMemory` tracking per-player VPIP/PFR stats and labeling them (LAG, TAG, Nit, Calling Station).

### Project Configuration

`project.yml` is the XcodeGen spec. Key details:
- Two targets: `pokerManagement` (app) and `PokerWidgetExtension` (widget).
- Swift packages: `WebRTC` (stasel/WebRTC ≥140.0.0) and `Starscream` (≥4.0.0) for WebSocket.
- `PokerSuggestionAttributes.swift` is listed as a source in **both** targets to share the Live Activity type.
- `NSSupportsLiveActivities: YES` is set in the main app's Info.plist properties.

## Key Conventions

- All iOS services are `ObservableObject` and owned as `@StateObject` in `ContentView`.
- Swift 6 / SwiftUI with `@MainActor` pattern for UI updates from background tasks.
- The CoreML model (`yolov8-playing-cards.mlmodelc`) is **not** in the repo — the app gracefully falls back to mock text recognition when it's absent.
- Backend auth is simulated: any `Bearer <anything>` header passes; used as a template for real API key integration.
- Hand persistence uses SwiftData (`@Model` on `HandHistory`, `modelContainer` in the app entry point).
