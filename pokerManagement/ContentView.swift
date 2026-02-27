import SwiftUI
import CoreMedia

struct ContentView: View {
    @StateObject private var streamService = StreamCaptureService()
    @StateObject private var visionService = VisionService()
    
    // Using @AppStorage to react to settings changes
    @AppStorage("useMockSolver") private var useMockSolver = true
    @AppStorage("solverAPIKey") private var solverAPIKey = ""
    @AppStorage("solverEndpoint") private var solverEndpoint = "http://localhost:8000/v1/solve"
    
    // We create the BackendService instance manually since we want it to react to AppStorage changes
    @StateObject private var backendService = BackendService(solver: MockGTOSolver())
    @StateObject private var feedbackService = FeedbackService()
    
    var body: some View {
        TabView {
            // Main Dashboard Tab
            NavigationView {
                ZStack {
                    Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 16) {
                        // Connection Status Banner
                        statusBanner
                        
                        // Poker Table Visualizer
                        PokerTableView(state: visionService.currentState)
                            .padding(.horizontal)
                        
                        // Suggestion Card
                        suggestionCard
                        
                        Spacer()
                        
                        // Capture Controls
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
        }
        .onAppear {
            setupServices()
        }
        .onChange(of: useMockSolver) { _ in updateBackendSolver() }
        .onChange(of: solverEndpoint) { _ in updateBackendSolver() }
        .onChange(of: solverAPIKey) { _ in updateBackendSolver() }
        
        // Trigger Backend on vision state changes
        .onChange(of: visionService.currentState.holeCards) { newCards in
            guard !newCards.isEmpty else { return }
            backendService.queryGTO(state: visionService.currentState)
        }
        
        // Trigger Audio Feedback on new suggestions
        .onChange(of: backendService.latestSuggestion?.action) { action in
            guard let suggestion = backendService.latestSuggestion else { return }
            feedbackService.speakSuggestion(suggestion)
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
            }
        }
        .frame(minHeight: 140)
    }
    
    // MARK: - Helpers
    
    private func setupServices() {
        updateBackendSolver()
        streamService.onFrameCaptured = { (buffer: CMSampleBuffer) in
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

#Preview {
    ContentView()
}
