# Poker Management

A real-time poker assistant that pairs with smart glasses (or an iPhone camera) to detect cards using on-device CoreML, queries a dual GTO solver backend, and delivers silent strategy advice via Dynamic Island and Apple Watch.

**Key principle**: All computer vision runs locally on the iPhone — no images or video ever leave the device. The backend only receives lightweight JSON game state.

## Architecture

```
Smart Glasses / iPhone Camera
        │
        ▼
VideoInputProtocol (glass-agnostic)
        │  CMSampleBuffer frames
        ▼
CoreML YOLOv11 Card Detection (on-device, ~13ms/frame)
        │
State Lock Engine (0.5s stable detection)
        │
        ├── Preflop / Multiway ──► POST /v1/solve/llm  (LLM Engine)
        │                                    │
        └── HU Postflop ────────► POST /v1/solve/gto  (TexasSolver)
                                             │
                                    ┌────────┴────────┐
                                    │  GTO Strategy    │
                                    │  Fold/Call/Raise │
                                    └────────┬────────┘
                                             │
                               Dynamic Island + Apple Watch
                                      (silent output)
```

## Components

### iOS App (`pokerManagement/`)

| Component | File | Description |
|-----------|------|-------------|
| **Video Input Protocol** | `Services/VideoInputProtocol.swift` | Glass-agnostic protocol. Any video source conforms to `VideoInputSource` and provides `CMSampleBuffer` frames. |
| **Camera Input** | `Services/CameraVideoInput.swift` | `AVCaptureSession` adapter for iPhone's rear camera. Works as fallback when no glasses are connected. |
| **WebRTC Input** | `Services/WebRTCVideoInput.swift` | WebRTC + Starscream adapter for glasses that stream via WebRTC (Ray-Ban Meta, Mentra, custom). |
| **Card Detection** | `Services/CardDetectionService.swift` | CoreML model loader. Tries YOLOv11 first, falls back to YOLOv8. Gracefully degrades to mock if no model is bundled. |
| **Vision Service** | `Services/VisionService.swift` | Processes frames from video input. Includes a **state lock engine** that waits for 0.5s of stable card detection before triggering a backend query. |
| **Backend Service** | `Services/BackendService.swift` | Routes requests: preflop/multiway to LLM engine, heads-up postflop to TexasSolver. Handles async solve polling for cache misses. |
| **GTO Solver APIs** | `Services/GTOSolverAPI.swift` | `GTOSolverProtocol` with three implementations: `MockGTOSolver`, `TexasSolverAPI`, and `LLMSolverAPI`. |
| **Speech Input** | `Services/SpeechInputService.swift` | `SFSpeechRecognizer` for voice input of pot/bet sizes when CV can't detect chips. On-device only. |
| **Live Activity** | `Services/LiveActivityManager.swift` | Manages iOS Live Activity / Dynamic Island for stealth GTO display. |
| **Feedback Service** | `Services/FeedbackService.swift` | Silent mode — no TTS or audio output. Logging only. |
| **Widget** | `PokerWidget/PokerWidget.swift` | Lock screen and Dynamic Island widget showing fold/call/raise weight bars. |
| **Views** | `Views/SettingsView.swift`, `Views/HistoryView.swift`, `Views/PokerTableView.swift` | Settings (video source picker, solver config), hand history list, and table visualization. |

### Backend (`backend-mock/`)

| Component | File | Description |
|-----------|------|-------------|
| **FastAPI Server** | `main.py` | Main application with all API endpoints (see API Reference below). |
| **TexasSolver Wrapper** | `solver_wrapper.py` | Wraps the TexasSolver CFR++ binary. Writes temp input files, invokes the solver, parses results. Falls back to a deterministic mock when the binary is not installed. |
| **LLM Engine** | `llm_engine.py` | GPT-4o powered analysis for preflop (with embedded GTO opening charts) and multiway pots. Falls back to static chart lookup when no API key is set. |
| **Player Profiling** | `player_profile.py` | In-memory HUD tracking per-player VPIP/PFR stats and labeling (LAG, TAG, Nit, Calling Station). |
| **Hand History DB** | `database.py` + `models.py` | SQLAlchemy + SQLite persistence for completed hands. |

### API Reference

All endpoints require a `Bearer <token>` header (any value accepted in dev mode).

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/solve` | Legacy mock GTO solver (heuristic + LLM reasoning) |
| `POST` | `/v1/solve/gto` | TexasSolver — heads-up postflop GTO analysis. Returns fold/call/raise weights. |
| `POST` | `/v1/solve/llm` | LLM engine — preflop and multiway analysis. Returns action + reasoning. |
| `POST` | `/v1/hud/update` | Update opponent VPIP/PFR profile |
| `POST` | `/v1/log_hand` | Save a completed hand to the database |
| `GET`  | `/v1/hands` | List recent hand history |
| `GET`  | `/health` | Health check |
| `WS`   | `/ws` | WebRTC signaling relay |

## Prerequisites

- **macOS** with Xcode 15+ (targets iOS 17.0+)
- **XcodeGen** (`brew install xcodegen`)
- **Python 3.9+** (for the backend)

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/fernyabc/pokerManagement.git
cd pokerManagement
```

### 2. Start the Backend

```bash
# One-command setup and start (creates venv, installs deps, launches server):
chmod +x scripts/start-backend.sh
./scripts/start-backend.sh
```

Or manually:

```bash
cd backend-mock
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

The server runs on `http://0.0.0.0:8000`.

#### Backend Environment Variables

Copy `.env.example` to `.env` and configure:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | No | unset | Enables GPT-4o reasoning for LLM engine. Falls back to static charts if unset. |
| `DATABASE_URL` | No | `sqlite:///./poker_hands.db` | SQLAlchemy database URL. |
| `TEXAS_SOLVER_BIN` | No | auto-detect | Path to TexasSolver `console_solver` binary. Uses mock solver if unset. |

#### Quick Test

```bash
# Health check
curl http://localhost:8000/health

# Test the GTO solver (mock mode)
curl -X POST http://localhost:8000/v1/solve/gto \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -d '{"board": ["Qs", "Jh", "2h"], "pot": 10.0, "effective_stack": 100.0}'

# Test the LLM engine (preflop, static chart fallback)
curl -X POST http://localhost:8000/v1/solve/llm \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -d '{"holeCards": ["Ah", "Kd"], "position": "UTG", "numPlayers": 6}'

# Test hand logging
curl -X POST http://localhost:8000/v1/log_hand \
  -H "Authorization: Bearer test" \
  -H "Content-Type: application/json" \
  -d '{"round_id": "test-001", "hero_hand": "Ah,Kd", "community_cards_flop": "Qs,Jh,2h", "pot_size": 25.0, "result": "won"}'

# List hand history
curl http://localhost:8000/v1/hands
```

### 3. Build the iOS App

```bash
# Generate Xcode project (required after modifying project.yml)
xcodegen generate

# Open in Xcode
open pokerManagement.xcodeproj
```

1. Select your target device or simulator.
2. Press `Cmd+R` to build and run.
3. On first launch, the app uses the **Mock Solver** (no backend needed).

### 4. Connect to Backend

1. Go to **Settings** (gear icon).
2. Turn off **"Use Mock Solver"**.
3. Set the **Endpoint URL** to your backend (default: `http://localhost:8000`).
4. Enter any value for **API Key** (e.g., `test`).

### 5. Choose Video Source

In **Settings**, select your video source:

| Source | When to Use |
|--------|-------------|
| **iPhone Camera** | Development/testing, or pointing phone at the table |
| **WebRTC Stream** | Ray-Ban Meta (Instagram Live intercept), Mentra, or custom WebRTC source |

The video source can be changed at runtime without restarting the app.

## Supported Smart Glasses

The app is glass-agnostic — any video source that provides frames can be plugged in via the `VideoInputSource` protocol.

| Glasses | Integration | Adapter |
|---------|------------|---------|
| **Ray-Ban Meta** | Meta DAT SDK (~1 FPS) or Instagram Live WebRTC intercept | `WebRTCVideoInput` |
| **Mentra Live** | RTMP or WebRTC streaming | `WebRTCVideoInput` / `RTMPVideoInput` (planned) |
| **RayNeo X3 Pro** | Companion Android app → HTTP upload over WiFi | `HTTPVideoInput` (planned) |
| **iPhone Camera** | Native AVCaptureSession | `CameraVideoInput` |

Adding a new glasses brand requires only implementing a new adapter class conforming to `VideoInputSource`.

## CoreML Model

The YOLOv11 playing card detection model (`yolov11-playing-cards.mlmodelc` or `.mlpackage`) is **not included** in the repository due to size. The app gracefully falls back to mock text recognition when no model is bundled.

To add a model:
1. Train or obtain a YOLOv11 model for playing card detection (52 classes).
2. Export to CoreML: `yolo export model=yolo11n.pt format=coreml`
3. Add the resulting `.mlpackage` or `.mlmodelc` to the Xcode project bundle.

## Project Structure

```
pokerManagement/
├── pokerManagement/              # iOS app source
│   ├── Services/                 # Core services
│   │   ├── VideoInputProtocol.swift    # Glass-agnostic video input
│   │   ├── CameraVideoInput.swift      # iPhone camera adapter
│   │   ├── WebRTCVideoInput.swift      # WebRTC adapter
│   │   ├── CardDetectionService.swift  # CoreML YOLOv11 loader
│   │   ├── VisionService.swift         # Frame processing + state lock
│   │   ├── BackendService.swift        # Dual solver routing
│   │   ├── GTOSolverAPI.swift          # Solver protocol + implementations
│   │   ├── SpeechInputService.swift    # Voice input for bet sizes
│   │   ├── LiveActivityManager.swift   # Dynamic Island manager
│   │   └── FeedbackService.swift       # Silent mode (no TTS)
│   ├── Views/                    # SwiftUI views
│   ├── Models/                   # Data models
│   └── ContentView.swift         # Main app view
├── PokerWidget/                  # Widget extension (Dynamic Island)
├── backend-mock/                 # Python FastAPI backend
│   ├── main.py                   # API server + endpoints
│   ├── solver_wrapper.py         # TexasSolver CLI wrapper
│   ├── llm_engine.py             # LLM analysis engine
│   ├── player_profile.py         # Opponent HUD profiling
│   ├── database.py               # SQLAlchemy + SQLite setup
│   ├── models.py                 # HandHistory model
│   ├── requirements.txt          # Python dependencies
│   └── .env.example              # Environment variable template
├── scripts/
│   └── start-backend.sh          # One-command backend launcher
├── project.yml                   # XcodeGen project spec
├── CLAUDE.md                     # AI assistant project guide
└── poker-refactor-architecture.md # Architecture plan
```

## Inspirations

- [pokerglass](https://github.com/gcheng713/pokerglass)
- [AR-Mahjong-Assistant](https://github.com/LYiHub/AR-Mahjong-Assistant-preview)
- [meta-vision-project](https://github.com/sahitid/meta-vision-project)
- [pokerAssist](https://github.com/sw5813/pokerAssist)
- [TexasSolver](https://github.com/bupticybee/TexasSolver)
