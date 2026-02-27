import SwiftUI
import CoreMedia
import SwiftData

struct ContentView: View {
    // MARK: - State Objects & Environment
    @StateObject private var streamService = StreamCaptureService()
    @StateObject private var visionService = VisionService()
    @StateObject private var feedbackService = FeedbackService()
    @StateObject private var backendService: BackendService
    
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - AppStorage for Settings
    @AppStorage("useMockSolver") private var useMockSolver = true
    @AppStorage("solverAPIKey") private var solverAPIKey = ""
    @AppStorage("solverEndpoint") private var solverEndpoint = "http://localhost:8000/v1/solve"

    init() {
        // Initialize backendService in the init, as it depends on AppStorage values.
        // The default here is Mock, but it gets updated immediately .onAppear via updateBackendSolver()
        _backendService = StateObject(wrappedValue: BackendService(solver: MockGTOSolver()))
    }

    var body: some View {
        TabView {
            // Main Dashboard Tab
            NavigationView {
                ZStack {
                    Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 16) {
                        statusBanner
                        PokerTableView(state: visionService.currentState)
                            .padding(.horizontal)
                        suggestionCard
                        Spacer()
                        Button(action: {
                            if streamService.isStreaming {
                                streamService.stopCapture()
                            } else {
                                streamService.startCaptureWorkaround()
                            }
                        }) {
                            Text(streamService.isStreaming ? "Stop Streaming" : "Start Meta Stream")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(streamService.isStreaming ? Color.red : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(radius: 3)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                    }
                }
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.doc.horizontal")
            }
            
            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            
            // History Tab
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .onAppear(perform: setupServices)
        .onChange(of: useMockSolver) { updateBackendSolver() }
        .onChange(of: solverEndpoint) { updateBackendSolver() }
        .onChange(of: solverAPIKey) { updateBackendSolver() }
        .onChange(of: visionService.currentState.holeCards) {
            // Do not query GTO if cards are not detected
            guard !visionService.currentState.holeCards.isEmpty else { return }
            backendService.queryGTO(state: visionService.currentState)
        }
        .onChange(of: backendService.latestSuggestion) {
            guard let suggestion = backendService.latestSuggestion else { return }
            
            // 1. Give audio feedback
            feedbackService.speakSuggestion(suggestion)
            
            // 2. Save the hand history to the database
            let history = HandHistory(
                holeCards: visionService.currentState.holeCards,
                communityCards: visionService.currentState.communityCards,
                numPlayers: visionService.currentState.numPlayers,
                myPosition: visionService.currentState.myPosition,
                potSize: visionService.currentState.potSize,
                recommendedAction: suggestion.action,
                recommendedRaiseSize: suggestion.raiseSize,
                ev: suggestion.ev
            )
            modelContext.insert(history)
        }
    }
    
    // MARK: - Subviews
    
    private var statusBanner: some View {
        HStack {
            Circle()
                .fill(streamService.isStreaming ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            Text(streamService.connectionStatus)
                .font(.subheadline)
                .foregroundColor(streamService.isStreaming ? .green : .orange)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var suggestionCard: some View {
        VStack {
            if backendService.isFetching {
                ProgressView("Analyzing Board...")
                    .padding()
            } else if let suggestion = backendService.latestSuggestion {
                VStack(spacing: 8) {
                    HStack {
                        Text("GTO Output")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let conf = suggestion.confidence {
                            Text("\(Int(conf * 100))% Freq")
                                .font(.caption).bold()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    
                    Text(suggestion.action.uppercased())
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundColor(suggestion.action == "Raise" ? .red : .blue)
                    
                    if let size = suggestion.raiseSize, suggestion.action == "Raise" {
                        Text("to $\(String(format: "%.1f", size))")
                            .font(.title2).bold()
                    }
                    
                    if let reason = suggestion.reasoning {
                        Text(reason)
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5)
                .padding(.horizontal)
            } else {
                // Placeholder when there's no suggestion yet
                Text("Start the stream to get GTO suggestions.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minHeight: 140)
    }
    
    // MARK: - Helpers
    
    private func setupServices() {
        updateBackendSolver()
        streamService.onFrameCaptured = { buffer in
            visionService.processFrame(buffer)
        }
    }
    
    private func updateBackendSolver() {
        if useMockSolver {
            backendService.solver = MockGTOSolver()
        } else if let url = URL(string: solverEndpoint) {
            backendService.solver = ThirdPartyGTOSolver(apiKey: solverAPIKey, endpoint: url)
        }
    }
}

// Add a specific Equatable conformance for GTOSuggestion to use it in .onChange
extension GTOSuggestion: Equatable {
    static func == (lhs: GTOSuggestion, rhs: GTOSuggestion) -> Bool {
        return lhs.action == rhs.action && lhs.raiseSize == rhs.raiseSize && lhs.ev == rhs.ev
    }
}


#Preview {
    ContentView()
        .modelContainer(for: HandHistory.self, inMemory: true)
}
