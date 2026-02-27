# pokerManagement

An iOS application and backend mock designed to work with smart glasses (specifically Ray-Ban Meta glasses) as a real-time poker assistant. 

The system captures the state of a live poker game via a video stream, analyzes the situation using a Game Theory Optimal (GTO) solver backend, and discretely delivers actionable suggestions back to the user via Text-to-Speech (TTS).

Inspired by projects like [pokerglass](https://github.com/gcheng713/pokerglass), [AR-Mahjong-Assistant](https://github.com/LYiHub/AR-Mahjong-Assistant-preview), [meta-vision-project](https://github.com/sahitid/meta-vision-project), and [pokerAssist](https://github.com/sw5813/pokerAssist).

## Features

- **Vision Pipeline:** Uses Apple's Vision framework (ready for CoreML YOLO integration) to detect hole cards, community cards, players, and pot sizes.
- **Backend Solver Integration:** Connects to a FastAPI mock server (pluggable for PioSolver or LLM engines) to receive EV (Expected Value) and play suggestions.
- **Discrete Audio Feedback:** Automatically routes Text-to-Speech suggestions (e.g., "Raise to 30. 85% frequency") to paired Bluetooth glasses.
- **Stream Workaround:** Built to support streaming intercepts (e.g., WhatsApp/Instagram Live) to bypass Ray-Ban Meta's camera API restrictions.

## Prerequisites

- **macOS** with Xcode 15+ (targets iOS 17.0+)
- **XcodeGen** (for generating the Xcode project file)
- **Python 3.9+** (for running the mock backend)

## Getting Started

### 1. Run the Backend Mock

We provide a Python FastAPI backend that simulates GTO solver responses based on the poker state sent by the iOS app.

```bash
# Make sure the script is executable
chmod +x scripts/start-backend.sh

# Start the local server
./scripts/start-backend.sh
```
The server will run on `http://0.0.0.0:8000`.

### 2. Build and Run the iOS App

The Xcode project is generated using `xcodegen` to keep the repository clean.

```bash
# Install XcodeGen if you haven't already
# brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Open the project in Xcode
open pokerManagement.xcodeproj
```

1. Select your target device or simulator in Xcode.
2. Hit `Cmd + R` to build and run.

## Usage & Configuration

Once the app is running:
1. Navigate to the **Settings** tab.
2. Ensure **"Use Local Mock Solver"** is checked (or uncheck it and provide a real API endpoint and key if you have a live GTO solver deployed).
3. The default Endpoint URL is `http://localhost:8000/v1/solve`.
4. Navigate to the **Dashboard** tab and tap **"Start Meta Stream"**.
5. The app will mock a video stream, parse the "cards", send them to the backend, and speak the resulting GTO suggestion.

## Architecture & Roadmap

Please refer to the [PRD.md](./PRD.md) for detailed architecture, milestones, and risks.
