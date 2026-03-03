# Poker Management Refactoring: Edge CV + Cloud GTO Architecture

## TL;DR
> **Quick Summary**: Refactor the poker application with a **glass-agnostic video input layer** (supporting any smart glasses brand via RTMP/WebRTC/HLS), process card detection locally on the iPhone using CoreML **YOLOv11** (Edge CV), and query a dual-engine backend: **TexasSolver** (hybrid cache + live) for heads-up postflop, and **LLM engine** for preflop + multiway.
>
> **Deliverables**:
> - Glass-agnostic video input abstraction layer (protocol-based, supports RTMP/WebRTC/HLS/camera).
> - iOS CoreML module for real-time playing card detection (YOLOv11 converted).
> - Backend Service (Python FastAPI) wrapping TexasSolver via CLI/pybind11.
> - Backend LLM engine for preflop and multiway pot analysis.
> - Pre-computed solution cache for instant responses on common spots.
> - E2E Integration: iOS sends state JSON to backend, displays GTO results silently.
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Video Input Abstraction → CoreML Detection → Backend Solver API → UI Display

---

## Context

### Original Request
Refactor project to support smart glasses for live streaming input, detect cards using YOLOv11/CoreML, and use TexasSolver + LLM for backend GTO analysis.

### Interview Summary
**Key Decisions**:
- **Edge CV Architecture**: iPhone acts as a smart middleman. It ingests the video stream, runs YOLOv11 via CoreML to detect cards, and sends a lightweight JSON payload to the backend. The backend strictly handles solver execution. No images ever leave the device.
- **Glass-Agnostic Design**: Video input layer is abstracted behind a Swift protocol. Any glasses brand (Mentra, Ray-Ban Meta, XREAL, Brilliant Labs, or even iPhone camera) can be plugged in by conforming to the protocol. The rest of the pipeline doesn't change.
- **Dual Solver Engine**: TexasSolver for heads-up postflop (hybrid cache + live). LLM engine (GPT-4o/Claude) for preflop and multiway pots.
- **Hybrid Latency**: Pre-computed cache for common spots returns instantly. Cache misses trigger live TexasSolver (30-180s with loading UX).
- **Output UI**: Silent visual output only — Dynamic Island and Apple Watch. No TTS/audio.
- **Input Fallback**: If CV cannot detect chip/pot sizes, user can input vocally via speech recognition.
- **Playing Logs**: Hand history stored in backend database for post-game analysis.

### Research Findings
- **YOLOv11 vs YOLOv8**: YOLOv11 has 22% fewer parameters, 95% mAP (vs ~90%), 13.5ms inference (vs 23ms), 4x faster training. Strongly recommended for new projects.
- **TexasSolver**: Open-source CFR++ solver. Solves flop in ~172 seconds (6 threads). Only supports heads-up postflop — no preflop, no multiway. AGPL-3.0 license (commercial license needed for internet services, deferred to pre-deployment).
- **Smart Glasses Streaming**: Most smart glasses support some combination of RTMP, WebRTC, or HLS. Abstracting behind a protocol makes the app future-proof.
- **CoreML on iPhone**: Neural Engine can run YOLOv11n at 30-60+ FPS with minimal battery impact.

---

## Work Objectives

### Core Objective
Implement an ultra-low latency, cost-effective, glass-agnostic poker assistant using Edge AI for vision and Cloud compute for GTO math.

### Concrete Deliverables
- Glass-Agnostic Video Input Layer (Swift protocol + adapters)
- iOS CoreML YOLOv11 Card Detector
- Backend TexasSolver FastAPI Wrapper (with pre-computed cache)
- Backend LLM Engine for Preflop + Multiway
- iOS API Client & Silent UI overlay (Dynamic Island & Apple Watch)
- Voice Input Module (Speech Recognition for Pot/Bet Sizes)
- Backend Playing Logs Database (Hand History)

### Definition of Done
- [ ] iOS app can display video from any supported glasses (or iPhone camera as fallback).
- [ ] iOS app correctly identifies cards on screen in real-time using YOLOv11 CoreML.
- [ ] Backend API accepts postflop game state and returns GTO strategy (from cache or live solver).
- [ ] Backend LLM API accepts preflop/multiway state and returns action + reasoning.
- [ ] End-to-end: Recognized cards → classified request → correct backend engine → GTO advice shown silently.

### Must Have
- Local CoreML processing (no video/images sent to backend).
- Glass-agnostic video input protocol.
- Pre-computed solution cache for common postflop spots.

### Must NOT Have (Guardrails)
- Do NOT send images or video streams to the backend server.
- Do NOT implement custom solver math; strictly wrap TexasSolver.
- Do NOT use audio or Text-to-Speech (TTS) for output. The app must remain strictly silent.
- Do NOT hard-code any specific glasses brand into the video pipeline.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│               Glass-Agnostic Video Input              │
│                                                       │
│  ┌─────────────┐  ┌──────────┐  ┌────────────────┐  │
│  │   Mentra     │  │ Ray-Ban  │  │ iPhone Camera  │  │
│  │   (RTMP)     │  │ Meta     │  │ (AVCapture)    │  │
│  │             │  │ (WebRTC) │  │                │  │
│  └──────┬──────┘  └────┬─────┘  └───────┬────────┘  │
│         └───────────────┼───────────────-┘            │
│                         ▼                             │
│         VideoInputProtocol (Swift protocol)           │
│         → provides CMSampleBuffer frames              │
│         → onFrameCaptured callback                    │
└─────────────────────────┬────────────────────────────┘
                          │
                          ▼
              CoreML YOLOv11n (13ms/frame)
                          │
              State Lock Engine (0.5s stable)
                          │
                ┌─────────┴─────────┐
                │  Classify Request  │
                └─────────┬─────────┘
                   ┌──────┼──────┐
                   ▼      ▼      ▼
              Preflop  HU Post  Multiway
                │       flop      │
                ▼       │         ▼
            LLM Engine  │    LLM Engine
            (<2s)       ▼     (<2s)
                   ┌─────────┐
                   │ Cache?  │
                   └────┬────┘
                    Y/  \N
                   ▼     ▼
                Instant  TexasSolver
                result   (30-180s)
                   │      │
                   ▼      ▼
            ┌───────────────────────┐
            │ Silent UI: Dynamic    │
            │ Island + Apple Watch  │
            └───────────────────────┘
```

### Glass-Agnostic Video Input Layer

The key abstraction: a Swift protocol that any video source conforms to.

```swift
protocol VideoInputSource: ObservableObject {
    var isStreaming: Bool { get }
    var connectionStatus: String { get }
    var onFrameCaptured: ((CMSampleBuffer) -> Void)? { get set }

    func startCapture()
    func stopCapture()
}
```

**Planned adapters:**

| Adapter | Protocol | Use Case |
|---------|----------|----------|
| `WebRTCVideoInput` | WebRTC (Starscream signaling) | Glasses with WebRTC support (Mentra, custom) |
| `RTMPVideoInput` | RTMP client | Glasses streaming to RTMP endpoint |
| `HLSVideoInput` | HLS playback | Glasses with managed HLS streaming |
| `CameraVideoInput` | AVCaptureSession | iPhone camera fallback (no glasses) |

The existing `WebRTCStreamCaptureService` becomes `WebRTCVideoInput` — a conforming adapter. `ContentView` holds a `any VideoInputSource` and the rest of the pipeline (VisionService, BackendService, etc.) is completely unaware of which glasses are connected.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Foundation — parallel, no dependencies):
├── Task 1: Backend TexasSolver FastAPI wrapper
├── Task 2: Glass-agnostic video input abstraction + adapters
└── Task 7: Backend hand history database

Wave 2 (Core Logic — depends on Wave 1):
├── Task 3: CoreML YOLOv11 card detection (depends: 2)
├── Task 4: Backend Dockerization + pre-computed cache (depends: 1)
└── Task 8: Backend LLM engine for preflop + multiway (depends: 1)

Wave 3 (Integration — depends on Wave 2):
├── Task 5: iOS backend API integration + silent UI (depends: 3, 4, 8)
└── Task 6: Voice input for bet sizes (depends: 5)

Wave FINAL (Verification):
├── F1: Plan compliance audit
├── F2: Code quality review
├── F3: End-to-end manual QA
├── F4: Scope fidelity check
└── F5: Silent mode & glass-agnostic verification
```

---

## TODOs

### Task 1: Backend TexasSolver FastAPI Wrapper

**What to do**:
- Compile TexasSolver `console_solver` binary from the `console` branch.
- Implement a Python wrapper: write temp input file → invoke binary (or use pybind11 bindings from `src/pybind/bindSolver.cpp`) → parse `output_result.json`.
- FastAPI `POST /solve` endpoint accepting game state JSON (board, ranges, pot, stacks, bet sizes).
- `GET /health` health check.
- Reuse existing `PokerState` and `GTOSuggestion` Pydantic models from `main.py`.

**Must NOT do**: Do not implement any custom Texas Hold'em logic. Just wrap the CLI/FFI.

**Files**: `backend-mock/main.py` (update), new `backend-mock/solver_wrapper.py`

**References**: `https://github.com/bupticybee/TexasSolver` (console branch), FFI API at `resources/ffi_api/README.MD`

**Acceptance Criteria**:
- [ ] Start FastAPI server and test `POST /solve` with mock board data.
- [ ] Returns JSON with fold/call/raise probability weights.

**QA Scenarios**:
```
Scenario: Send game state JSON and receive GTO solution
  Tool: Bash (curl)
  Preconditions: FastAPI server running, TexasSolver binary available.
  Steps:
    1. Send POST request with board: Qs,Jh,2h and ranges for IP/OOP.
    2. Verify response format.
  Expected Result: HTTP 200 with JSON payload containing weights for Fold/Call/Raise.
  Evidence: .sisyphus/evidence/task-1-backend-solve.json
```

---

### Task 2: Glass-Agnostic Video Input Abstraction

**What to do**:
- Define `VideoInputProtocol` (Swift protocol) with `startCapture()`, `stopCapture()`, `isStreaming`, `connectionStatus`, `onFrameCaptured` callback.
- Refactor existing `WebRTCStreamCaptureService` into `WebRTCVideoInput` conforming to the protocol.
- Implement `CameraVideoInput` adapter using `AVCaptureSession` as a local fallback (no glasses needed for development/testing).
- Add a `VideoInputFactory` or settings-driven picker so the user can select their video source.
- Update `ContentView` to use `any VideoInputSource` instead of the concrete `WebRTCStreamCaptureService`.

**Files**:
- `pokerManagement/Services/WebRTCStreamCaptureService.swift` → refactor into `WebRTCVideoInput`
- New `pokerManagement/Services/VideoInputProtocol.swift`
- New `pokerManagement/Services/CameraVideoInput.swift`
- `pokerManagement/ContentView.swift` (update to use protocol)

**Acceptance Criteria**:
- [ ] `CameraVideoInput` displays iPhone camera feed and fires `onFrameCaptured`.
- [ ] `WebRTCVideoInput` connects to a test WebRTC source and fires `onFrameCaptured`.
- [ ] Switching between sources does not affect downstream services.

**QA Scenarios**:
```
Scenario: Render camera feed via CameraVideoInput
  Tool: XCUITest
  Preconditions: iOS simulator or device with camera access.
  Steps:
    1. Select "iPhone Camera" as video source in settings.
    2. Open dashboard. Verify frames are being captured.
  Expected Result: onFrameCaptured fires continuously. VisionService receives buffers.
  Evidence: .sisyphus/evidence/task-2-camera-input.txt

Scenario: Swap video source at runtime
  Tool: XCUITest
  Preconditions: Both sources available.
  Steps:
    1. Start with Camera source. Verify streaming.
    2. Switch to WebRTC source in settings. Verify streaming resumes.
  Expected Result: Downstream pipeline continues without errors.
  Evidence: .sisyphus/evidence/task-2-swap-source.txt
```

---

### Task 3: CoreML YOLOv11 Card Detection

**What to do**:
- Train or obtain YOLOv11n model on playing card dataset (52 classes + jokers).
- Convert to CoreML: `yolo export model=yolo11n.pt format=coreml`
- Replace `CardDetectionService.swift` model loading to use YOLOv11 `.mlpackage`.
- Implement state lock engine: track detected cards across frames, lock after 0.5s stability.
- Classify cards by bounding box position: bottom 30% = hole cards, middle = community cards.
- Reuse existing `CardDetectionService.loadModel()` and `detectCards(in:completion:)` patterns.

**Files**: `pokerManagement/Services/CardDetectionService.swift`, `pokerManagement/Services/VisionService.swift`

**References**: `cadyze/card-vision` (training data/approach), `mcgovey/compvision-playing-card-detection` (CoreML deployment pattern)

**Blocked By**: Task 2

**Acceptance Criteria**:
- [ ] CoreML YOLOv11 model loaded successfully in iOS app.
- [ ] Inference runs on video frames at 30+ FPS without crashing.
- [ ] State locks after 0.5s of stable card detection.

**QA Scenarios**:
```
Scenario: Detect cards from video frame
  Tool: XCUITest
  Preconditions: iOS simulator running, test video feed active via CameraVideoInput.
  Steps:
    1. Feed a static image of Qs, Jh, 2h to the video input.
    2. Wait 1 second.
    3. Assert the state machine has locked the detected cards.
  Expected Result: State machine outputs locked state with correct cards.
  Evidence: .sisyphus/evidence/task-3-coreml-detect.txt
```

---

### Task 4: Backend Dockerization + Pre-computed Solution Cache

**What to do**:
- Create `Dockerfile` for the Python FastAPI backend with TexasSolver binary.
- **Pre-computed cache**: Run TexasSolver offline in batch mode for common scenarios:
  - Top 200 flop textures × common range matchups × standard bet sizes.
  - Store results in SQLite (or Redis).
- Cache lookup middleware: check cache before invoking live solver.
- If cache hit → return instantly. If miss → queue live solve, return job ID, push result via WebSocket when done.
- Create a suite of mock test JSON payloads for iOS development.

**Files**: new `backend-mock/Dockerfile`, new `backend-mock/cache.py`, new `backend-mock/batch_solve.py`, update `backend-mock/main.py`

**Blocked By**: Task 1

**Acceptance Criteria**:
- [ ] Docker container builds and runs.
- [ ] `POST /solve` returns cached result instantly for a pre-computed board.
- [ ] `POST /solve` queues live solve for an uncached board and returns job ID.

**QA Scenarios**:
```
Scenario: Cache hit returns instantly
  Tool: Bash (curl)
  Preconditions: Cache pre-populated with Qs,Jh,2h scenario.
  Steps:
    1. curl POST /solve with board Qs,Jh,2h.
    2. Measure response time.
  Expected Result: Response in < 100ms with correct GTO weights.
  Evidence: .sisyphus/evidence/task-4-cache-hit.json

Scenario: Cache miss queues live solve
  Tool: Bash (curl + wscat)
  Preconditions: Board not in cache.
  Steps:
    1. curl POST /solve with uncached board.
    2. Receive job_id in response.
    3. Connect to WebSocket, wait for result.
  Expected Result: Job ID returned immediately. Result pushed via WS within timeout.
  Evidence: .sisyphus/evidence/task-4-cache-miss.json
```

---

### Task 5: iOS Backend API Integration + Silent UI

**What to do**:
- Update `BackendService.swift` to route requests:
  - Preflop or multiway → `POST /solve/llm`
  - Heads-up postflop → `POST /solve` (TexasSolver)
- Handle async solve: if cache miss, show "Solving..." in Dynamic Island, poll/WebSocket for result.
- Update `LiveActivityManager.swift` and `PokerWidget.swift` for new GTO response format (fold/call/raise weights instead of single action).
- Remove TTS from `FeedbackService.swift` (silent mode).
- Add `TexasSolverAPI` conforming to existing `GTOSolverProtocol`.

**Files**: `pokerManagement/Services/BackendService.swift`, `pokerManagement/Services/GTOSolverAPI.swift`, `pokerManagement/Services/LiveActivityManager.swift`, `pokerManagement/Services/FeedbackService.swift`, `PokerWidget/PokerWidget.swift`

**Blocked By**: Task 3, Task 4, Task 8

**Acceptance Criteria**:
- [ ] App sends correct JSON payload to backend upon state lock.
- [ ] App correctly routes preflop to LLM, postflop to TexasSolver.
- [ ] Dynamic Island displays GTO suggestion silently.
- [ ] No audio output anywhere.

**QA Scenarios**:
```
Scenario: End-to-end detection and GTO display
  Tool: XCUITest
  Preconditions: Backend API running locally, iOS simulator with test feed.
  Steps:
    1. Feed test video of a poker hand.
    2. Wait for state lock.
    3. Wait for API response.
    4. Assert Dynamic Island shows GTO weights.
  Expected Result: UI displays correct GTO suggestion. No audio emitted.
  Evidence: .sisyphus/evidence/task-5-e2e-ui.png
```

---

### Task 6: Voice Input for Bet Sizes (Fallback)

**What to do**:
- Implement `SpeechInputService.swift` using `SFSpeechRecognizer` for iOS 17+.
- Add silent UI trigger (Dynamic Island tap or Apple Watch) to start listening.
- `RegexBuilder` pipeline to extract numbers from "pot is fifty, bet is twenty".
- Pass parsed values into the game state before calling backend.

**Files**: new `pokerManagement/Services/SpeechInputService.swift`

**Blocked By**: Task 5

**Acceptance Criteria**:
- [ ] App can transcribe spoken audio locally.
- [ ] App correctly extracts pot and bet integers from spoken text.

**QA Scenarios**:
```
Scenario: Speak bet size and extract integers
  Tool: XCUITest
  Preconditions: Microphone permissions granted.
  Steps:
    1. Trigger voice input.
    2. Feed audio file saying "the pot is one hundred, facing a bet of fifty".
    3. Wait for transcription and parsing.
  Expected Result: Internal state updates to Pot: 100, Bet: 50.
  Evidence: .sisyphus/evidence/task-6-voice-input.txt
```

---

### Task 7: Backend Hand History Database

**What to do**:
- SQLAlchemy + SQLite in the FastAPI backend.
- `HandHistory` model: round_id, hero_hand, community_cards per street, player_actions per street, gto_suggestion, timestamp.
- `POST /log_hand` endpoint to persist a completed round.
- Each full round = one record.

**Files**: new `backend-mock/models.py`, new `backend-mock/database.py`, update `backend-mock/main.py`

**Acceptance Criteria**:
- [ ] Database schema created successfully on startup.
- [ ] `POST /log_hand` saves round data. Querying DB confirms record.

**QA Scenarios**:
```
Scenario: Save a played round to the database
  Tool: Bash (sqlite3)
  Preconditions: FastAPI server running, SQLite DB initialized.
  Steps:
    1. Send POST request with a full river state.
    2. Query the SQLite database for the latest HandHistory record.
  Expected Result: The record exists and contains the correct community cards and actions.
  Evidence: .sisyphus/evidence/task-7-db-log.txt
```

---

### Task 8: Backend LLM Engine for Preflop + Multiway

**What to do**:
- FastAPI endpoint `POST /solve/llm` for preflop and multiway scenarios.
- Prompt engineering: board state + player count + positions → LLM returns action + reasoning.
- Embed standard GTO preflop opening range charts in prompt context.
- Use existing `llm_engine.py` pattern with `AsyncOpenAI` client.
- Fallback: if no API key, return static preflop chart lookup (deterministic).

**Files**: `backend-mock/llm_engine.py` (update), `backend-mock/main.py` (add endpoint)

**Blocked By**: Task 1 (shares FastAPI infrastructure)

**Acceptance Criteria**:
- [ ] `POST /solve/llm` returns action + reasoning for a preflop scenario.
- [ ] Fallback works without API key (static chart lookup).
- [ ] Multiway scenario returns reasonable advice.

**QA Scenarios**:
```
Scenario: Preflop advice via LLM
  Tool: Bash (curl)
  Preconditions: FastAPI running, OPENAI_API_KEY set (or mock mode).
  Steps:
    1. POST /solve/llm with hero hand AKs, position UTG, 6 players, no community cards.
    2. Verify response.
  Expected Result: Action "Raise" with reasoning referencing position and hand strength.
  Evidence: .sisyphus/evidence/task-8-llm-preflop.json

Scenario: Multiway pot advice
  Tool: Bash (curl)
  Steps:
    1. POST /solve/llm with 4 players on flop Qs,Jh,2h.
    2. Verify response.
  Expected Result: Action with reasoning accounting for multiway dynamics.
  Evidence: .sisyphus/evidence/task-8-llm-multiway.json
```

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `pokerManagement/Services/VideoInputProtocol.swift` | **NEW** — Glass-agnostic video input protocol |
| `pokerManagement/Services/CameraVideoInput.swift` | **NEW** — iPhone camera fallback adapter |
| `pokerManagement/Services/WebRTCStreamCaptureService.swift` | Refactor → `WebRTCVideoInput`, conform to protocol |
| `pokerManagement/Services/CardDetectionService.swift` | YOLOv11 CoreML model loading |
| `pokerManagement/Services/VisionService.swift` | State lock engine, remove mock fallback |
| `pokerManagement/Services/BackendService.swift` | Route preflop/multiway→LLM, postflop→TexasSolver |
| `pokerManagement/Services/GTOSolverAPI.swift` | Add `TexasSolverAPI` conforming to `GTOSolverProtocol` |
| `pokerManagement/Services/LiveActivityManager.swift` | Updated GTO display (weights) |
| `pokerManagement/Services/FeedbackService.swift` | Remove TTS (silent mode) |
| `pokerManagement/Services/SpeechInputService.swift` | **NEW** — Voice input for bet sizes |
| `pokerManagement/ContentView.swift` | Use `any VideoInputSource`, add source picker |
| `PokerWidget/PokerWidget.swift` | Updated Dynamic Island UI for weights |
| `backend-mock/main.py` | TexasSolver wrapper, LLM endpoint, cache middleware, log_hand |
| `backend-mock/llm_engine.py` | Preflop/multiway prompt engineering |
| `backend-mock/solver_wrapper.py` | **NEW** — TexasSolver CLI/FFI wrapper |
| `backend-mock/cache.py` | **NEW** — Pre-computed solution cache |
| `backend-mock/batch_solve.py` | **NEW** — Offline batch solver for cache generation |
| `backend-mock/models.py` | **NEW** — SQLAlchemy HandHistory model |
| `backend-mock/database.py` | **NEW** — Database connection setup |
| `backend-mock/Dockerfile` | **NEW** — Container for backend |
| `project.yml` | Update if new Swift packages needed |

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Frameworks
- **Backend**: pytest
- **iOS**: XCTest

### Verification Plan
1. **Backend solver**: `curl POST /solve` with known board → verify response matches expected GTO weights.
2. **Backend LLM**: `curl POST /solve/llm` with preflop state → verify reasonable action + reasoning.
3. **Backend cache**: Solve same board twice → second request returns instantly (cache hit).
4. **iOS video input**: Connect CameraVideoInput → verify `onFrameCaptured` fires with valid buffers.
5. **iOS video swap**: Switch from Camera to WebRTC source → verify pipeline continues.
6. **iOS detection**: Feed test image of known cards through CoreML → verify correct identification.
7. **iOS state lock**: Feed 15+ identical frames → verify state locks after 0.5s.
8. **E2E**: Stream test video → cards detected → state sent to backend → GTO result displayed in Dynamic Island.
9. **Silent mode**: Verify no audio output anywhere in the app (FeedbackService disabled).
10. **Glass-agnostic**: Verify that no code outside `VideoInputProtocol` adapters references a specific glasses brand.

---

## Final Verification Wave

> Review agents run in PARALLEL. ALL must APPROVE. Rejection → fix → re-run.

- [ ] F1. **Plan Compliance Audit**
- [ ] F2. **Code Quality Review**
- [ ] F3. **End-to-End Manual QA**
- [ ] F4. **Scope Fidelity Check**
- [ ] F5. **Silent Mode & Glass-Agnostic Verification**
  - Verify no audio/TTS output. Output strictly on Dynamic Island / Apple Watch.
  - Verify no glasses-specific code outside adapter implementations.

---

## Glass Adapter Reference

All adapters conform to `VideoInputProtocol` and produce `CMSampleBuffer` frames via the `onFrameCaptured` callback. The rest of the pipeline (VisionService, BackendService, etc.) is completely unaware of which glasses are connected.

### RayNeo X3 Pro

| Spec | Detail |
|------|--------|
| **Camera** | Sony IMX681 12MP RGB + OV depth camera, wide-angle |
| **Connectivity** | WiFi 6, Bluetooth 5.3 |
| **Platform** | Android (runs on-device, Min SDK 31) |
| **Developer SDK** | RayNeo ARSDK for Android ([developer portal](https://open.rayneo.com/)) |
| **Camera access pattern** | Capture-and-upload via `RayNeoDeviceManager` (see [AR-Mahjong-Assistant](https://github.com/LYiHub/AR-Mahjong-Assistant-preview)) |
| **Adapter class** | `RayNeoVideoInput` |

**Integration approach**: The RayNeo X3 Pro is an Android device with direct camera access via the RayNeo ARSDK. Since our iOS app can't run native Android SDK code, the integration follows the AR-Mahjong-Assistant pattern: the glasses run a lightweight companion Android app that captures frames and sends them over local WiFi to the iPhone app. Two options:

1. **HTTP upload (proven)**: Glasses capture photos via `RayNeoDeviceManager` → upload JPEG to iPhone via HTTP (Retrofit-style). iPhone receives image, converts to `CMSampleBuffer`, feeds into pipeline. Latency: ~200-500ms per frame. This mirrors the AR-Mahjong-Assistant architecture exactly.
2. **Local WebRTC relay**: Glasses companion app streams camera via WebRTC to iPhone over local WiFi. Reuses existing `WebRTCVideoInput` adapter. Latency: ~50-150ms. Requires building a small Android WebRTC sender app.

**Note**: Unlike Mentra (which streams to a phone app natively), RayNeo runs its own Android OS. The glasses ARE the "phone" — our iOS app receives frames from it as a network peer, not as a peripheral.

### Ray-Ban Meta

| Spec | Detail |
|------|--------|
| **Camera** | 12MP ultra-wide, 1080p video |
| **Connectivity** | WiFi, Bluetooth 5.2 |
| **Platform** | Pairs with iOS/Android via Meta View app |
| **Developer SDK** | [Meta Wearables Device Access Toolkit (DAT)](https://developers.meta.com/wearables/faq/) — developer preview Dec 2025 |
| **Camera access pattern** | DAT SDK streams ~1 FPS JPEG. Or Instagram Live stream intercept via WebRTC |
| **Adapter class** | `MetaRayBanVideoInput` |

**Integration approaches** (two options, both viable):

1. **Meta DAT SDK (official, new)**: Meta released the Wearables Device Access Toolkit in Dec 2025. Provides direct camera access — streams frames as JPEG images at ~1 FPS. Low frame rate but officially supported. Reference: [VisionClaw project](https://github.com/sseanliu/VisionClaw) demonstrates this pattern (streams to Gemini for visual context).
2. **Instagram Live intercept (original workaround)**: Start a private Instagram Live stream from the glasses → intercept the WebRTC/RTMP stream on the iPhone. Higher frame rate (~15-30 FPS) but fragile — can break with Meta firmware updates. This is what the current `WebRTCStreamCaptureService` in the project already implements.

**Recommendation**: Use DAT SDK for reliability. The 1 FPS is low but sufficient for poker (cards don't change mid-second). Supplement with the state lock engine — once cards are detected, they're locked until the board changes.

### Mentra Live Camera Glasses

| Spec | Detail |
|------|--------|
| **Camera** | 12MP (3024×4032), 118° FOV, 1080p video |
| **Connectivity** | WiFi 802.11 b/g/n (5GHz), Bluetooth 5.0 LE |
| **Platform** | Pairs with iOS/Android via Mentra app (React Native) |
| **Developer SDK** | [@mentra/sdk](https://www.npmjs.com/package/@mentra/sdk) (TypeScript). Native iOS SDK in `sdk_ios/` |
| **Camera access pattern** | Managed streaming (HLS/DASH/WebRTC), unmanaged (RTMP), or `requestPhoto()` for single captures |
| **Adapter class** | `MentraVideoInput` |

**Integration approach**: Skip the TypeScript SDK. Configure glasses to stream via RTMP to a local endpoint on the iPhone. Reuse `WebRTCVideoInput` adapter if using WebRTC, or build `RTMPVideoInput` for RTMP. Battery life: ~40 min continuous streaming.

### iPhone Camera (Fallback / Development)

| Spec | Detail |
|------|--------|
| **Camera** | Device-dependent (12MP+, 4K video) |
| **Connectivity** | N/A (local) |
| **Platform** | Native iOS |
| **Developer SDK** | AVFoundation (`AVCaptureSession`) |
| **Camera access pattern** | `AVCaptureVideoDataOutput` → `CMSampleBuffer` directly |
| **Adapter class** | `CameraVideoInput` |

**Integration approach**: Simplest adapter. Standard `AVCaptureSession` setup. Essential for development and testing without physical glasses. Also serves as a real fallback — user can point their iPhone camera at the table.

### Adapter Selection UX

The `SettingsView` will include a video source picker:

```
Video Source: [ iPhone Camera ▾ ]
              ┌──────────────────┐
              │ iPhone Camera    │  ← AVCaptureSession (always available)
              │ WebRTC Stream    │  ← For Mentra, Ray-Ban Meta intercept, or custom
              │ HTTP Receiver    │  ← For RayNeo X3 Pro companion app
              │ RTMP Stream      │  ← For Mentra unmanaged, or custom
              └──────────────────┘
```

When a new glasses brand is added, only a new adapter class + a new picker option is needed. Zero changes to VisionService, BackendService, or any downstream code.

---

## Success Criteria

### Final Checklist
- [ ] Backend REST API functional wrapping TexasSolver (with cache).
- [ ] Backend LLM API functional for preflop and multiway.
- [ ] iOS app runs CoreML YOLOv11 inference locally at 30+ FPS.
- [ ] No video/image data transmitted to backend.
- [ ] Glass-agnostic: video source swappable without pipeline changes.
- [ ] All output is silent (no TTS, no audio).
- [ ] End-to-end integration successful.
