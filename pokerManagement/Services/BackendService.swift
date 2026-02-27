import Foundation

/// Defines the expected action payload from the solver (inspired by pokerAssist)
struct GTOSuggestion: Codable {
    let action: String        // Fold, Call, Raise
    let raiseSize: Double?    // If action == Raise
    let ev: Double?           // Expected value
    let confidence: Double?   // Frequency or Confidence score
    let reasoning: String?    // LLM/Heuristic text explanation
}

/// Communicates the vision state to the GTO solver/LLM backend
class BackendService: ObservableObject {
    @Published var latestSuggestion: GTOSuggestion? = nil
    @Published var isFetching = false
    
    // Abstracting the solver behind a protocol
    var solver: GTOSolverProtocol
    
    // Defaulting to MockGTOSolver.
    // In production, swap with ThirdPartyGTOSolver(apiKey: "...", endpoint: "...")
    init(solver: GTOSolverProtocol = MockGTOSolver()) {
        self.solver = solver
    }
    
    func queryGTO(state: DetectedPokerState) {
        self.isFetching = true
        
        Task {
            do {
                let suggestion = try await solver.analyzeState(state)
                await MainActor.run {
                    self.latestSuggestion = suggestion
                    self.isFetching = false
                }
            } catch {
                print("Failed to query GTO solver: \(error)")
                await MainActor.run {
                    self.isFetching = false
                }
            }
        }
    }
}
