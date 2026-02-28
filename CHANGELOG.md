# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Implemented WebRTC live streaming functionality.
- Added `WebRTCStreamCaptureService` to handle WebRTC connections in the Swift client.
- Added Python backend-mock endpoints and templates (`main.py`, `templates/index.html`) to support WebRTC signaling and stream reception.
- Updated Swift Package Manager dependencies to include WebRTC.

### Removed
- Removed the legacy `StreamCaptureService`.
- Cleaned up obsolete stream handling logic from `ContentView`.
