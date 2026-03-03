import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var visionService = VisionService()
    @StateObject private var backendService = BackendService()
    @StateObject private var feedbackService = FeedbackService()
    @StateObject private var speechService = SpeechInputService()
    @StateObject private var liveActivityManager = LiveActivityManager.shared

    @AppStorage("useMockSolver") private var useMockSolver = true
    @AppStorage("solverEndpoint") private var solverEndpoint = "http://localhost:8000"
    @AppStorage("solverAPIKey") private var solverAPIKey = ""
    @AppStorage("selectedVideoInput") private var selectedVideoInput = VideoInputType.camera.rawValue

    @State private var cameraInput = CameraVideoInput()
    @State private var webRTCInput = WebRTCVideoInput()
    @State private var showSettings = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            mainTab
                .tabItem { Label("Live", systemImage: "eye") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(1)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                useMockSolver: $useMockSolver,
                solverEndpoint: $solverEndpoint,
                solverAPIKey: $solverAPIKey,
                selectedVideoInput: $selectedVideoInput
            )
        }
        .onAppear { configureAndStart() }
        .onChange(of: selectedVideoInput) { _, _ in switchVideoInput() }
        .onChange(of: useMockSolver) { _, _ in configureSolvers() }
    }

    // MARK: - Main Tab

    private var mainTab: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Poker Assistant")
                    .font(.headline)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gear")
                }
            }
            .padding(.horizontal)

            // Status bar
            HStack(spacing: 8) {
                Circle()
                    .fill(activeInput.isStreaming ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(activeInput.connectionStatus)
                    .font(.caption)
                Spacer()
                if visionService.isStateLocked {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal)

            // Detected state
            PokerTableView(state: visionService.currentState)

            // GTO suggestion
            suggestionView

            // Voice input bar
            voiceInputBar

            Spacer()
        }
        .padding(.top)
    }

    // MARK: - Suggestion View

    private var suggestionView: some View {
        GroupBox("GTO Suggestion") {
            if backendService.isFetching {
                ProgressView("Solving...")
            } else if let s = backendService.latestSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(s.action)
                            .font(.title2).bold()
                        if let raise = s.raiseSize {
                            Text("$\(raise, specifier: "%.0f")")
                                .font(.title3)
                        }
                        Spacer()
                        if let ev = s.ev {
                            Text("EV: \(ev, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Weight bars
                    if let f = s.foldWeight, let c = s.callWeight, let r = s.raiseWeight {
                        HStack(spacing: 4) {
                            weightBar(label: "F", value: f, color: .red)
                            weightBar(label: "C", value: c, color: .blue)
                            weightBar(label: "R", value: r, color: .green)
                        }
                        .frame(height: 24)
                    }

                    if let reasoning = s.reasoning {
                        Text(reasoning)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Waiting for detection...")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func weightBar(label: String, value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * value)
                Text("\(label) \(Int(value * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Voice Input

    private var voiceInputBar: some View {
        HStack {
            if speechService.isListening {
                Text(speechService.transcribedText.isEmpty ? "Listening..." : speechService.transcribedText)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if let pot = speechService.parsedPotSize {
                    Text("Pot: $\(pot, specifier: "%.0f")")
                        .font(.caption)
                }
                if let bet = speechService.parsedBetSize {
                    Text("Bet: $\(bet, specifier: "%.0f")")
                        .font(.caption)
                }
                Spacer()
            }
            Button {
                if speechService.isListening {
                    speechService.stopListening()
                } else {
                    speechService.startListening()
                }
            } label: {
                Image(systemName: speechService.isListening ? "mic.fill" : "mic")
                    .foregroundColor(speechService.isListening ? .red : .primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }

    // MARK: - Configuration

    private var activeInput: any VideoInputSource {
        selectedVideoInput == VideoInputType.webRTC.rawValue ? webRTCInput as any VideoInputSource : cameraInput as any VideoInputSource
    }

    private func configureAndStart() {
        configureSolvers()
        connectVisionPipeline()
        switchVideoInput()
        liveActivityManager.startActivity()
    }

    private func configureSolvers() {
        if useMockSolver {
            backendService.useMock = true
        } else {
            guard let base = URL(string: solverEndpoint) else { return }
            backendService.texasSolver = TexasSolverAPI(apiKey: solverAPIKey, endpoint: base.appendingPathComponent("solve"))
            backendService.llmSolver = LLMSolverAPI(apiKey: solverAPIKey, endpoint: base.appendingPathComponent("solve/llm"))
            backendService.useMock = false
        }
    }

    private func connectVisionPipeline() {
        // When state locks, query the backend
        visionService.$isStateLocked
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak backendService, weak visionService] _ in
                guard let backend = backendService, let vision = visionService else { return }
                var state = vision.currentState
                // Apply voice-parsed pot/bet if available
                if let pot = self.speechService.parsedPotSize { state.potSize = pot }
                backend.queryGTO(state: state)
            }
            .store(in: &cancellables)

        // Forward suggestions to feedback + live activity
        backendService.$latestSuggestion
            .compactMap { $0 }
            .sink { [weak feedbackService, weak liveActivityManager] suggestion in
                feedbackService?.handleSuggestion(suggestion)
                liveActivityManager?.updateActivity(suggestion: suggestion)
                self.saveHandHistory(suggestion: suggestion)
            }
            .store(in: &cancellables)
    }

    @State private var cancellables = Set<AnyCancellable>()

    private func switchVideoInput() {
        cameraInput.stopCapture()
        webRTCInput.stopCapture()

        if selectedVideoInput == VideoInputType.webRTC.rawValue {
            webRTCInput.onFrameCaptured = { [weak visionService] buffer in
                visionService?.processFrame(buffer)
            }
            webRTCInput.startCapture()
        } else {
            cameraInput.onFrameCaptured = { [weak visionService] buffer in
                visionService?.processFrame(buffer)
            }
            cameraInput.startCapture()
        }
    }

    @Environment(\.modelContext) private var modelContext

    private func saveHandHistory(suggestion: GTOSuggestion) {
        let state = visionService.currentState
        let hand = HandHistory(
            holeCards: state.holeCards,
            communityCards: state.communityCards,
            action: suggestion.action,
            potSize: state.potSize,
            reasoning: suggestion.reasoning
        )
        modelContext.insert(hand)
    }
}

import Combine
