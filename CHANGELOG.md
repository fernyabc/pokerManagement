# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added [2026-02-28 00:04:36]
- Implemented Live Activities and Dynamic Island support for stealthy feedback mechanisms.
- Created `PokerWidgetExtension` target in `project.yml` with `NSSupportsLiveActivities` enabled.
- Added `LiveActivityManager` to handle lifecycle events (start, update, end) for GTO suggestions.
- Created `PokerSuggestionAttributes` and `PokerSuggestionLiveActivity` UI to display EV, action, and sizing on the lock screen and Dynamic Island.

### Added [2026-02-28 00:00:48]
- Implemented `CardDetectionService` to dynamically load CoreML models (specifically `yolov8-playing-cards.mlmodelc`) to enable real-time detection without crashing if the model is absent.
- Integrated `CardDetectionService` into `VisionService` to parse card ranks and suits based on bounding box positioning (e.g. hole cards vs community cards).
- Preserved mock text detection fallback in `VisionService` when the CoreML model is not loaded.

### Added
- Implemented WebRTC live streaming functionality.
- Added `WebRTCStreamCaptureService` to handle WebRTC connections in the Swift client.
- Added Python backend-mock endpoints and templates (`main.py`, `templates/index.html`) to support WebRTC signaling and stream reception.
- Updated Swift Package Manager dependencies to include WebRTC.

### Removed
- Removed the legacy `StreamCaptureService`.
- Cleaned up obsolete stream handling logic from `ContentView`.
