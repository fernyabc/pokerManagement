import Foundation

/// GTO suggestion with fold/call/raise weights for full strategy display.
struct GTOSuggestion: Codable {
    let action: String
    let raiseSize: Double?
    let ev: Double?
    let confidence: Double?
    let reasoning: String?
    let foldWeight: Double?
    let callWeight: Double?
    let raiseWeight: Double?
    let isSolving: Bool?
    let jobId: String?
}

/// Routes requests: preflop/multiway → POST /solve/llm, HU postflop → POST /solve.
class BackendService: ObservableObject {
    @Published var latestSuggestion: GTOSuggestion? = nil
    @Published var isFetching = false

    var texasSolver: GTOSolverProtocol
    var llmSolver: GTOSolverProtocol
    var useMock: Bool

    init(texasSolver: GTOSolverProtocol = MockGTOSolver(),
         llmSolver: GTOSolverProtocol = MockGTOSolver(),
         useMock: Bool = true) {
        self.texasSolver = texasSolver
        self.llmSolver = llmSolver
        self.useMock = useMock
    }

    private func shouldUseLLM(state: DetectedPokerState) -> Bool {
        let isPreflop = state.communityCards.isEmpty
        let isMultiway = state.numPlayers > 2
        return isPreflop || isMultiway
    }

    func queryGTO(state: DetectedPokerState) {
        self.isFetching = true

        Task {
            do {
                let solver: GTOSolverProtocol
                if useMock {
                    solver = texasSolver
                } else {
                    solver = shouldUseLLM(state: state) ? llmSolver : texasSolver
                }

                let suggestion = try await solver.analyzeState(state)

                if suggestion.isSolving == true, let jobId = suggestion.jobId,
                   let ts = self.texasSolver as? TexasSolverAPI {
                    await MainActor.run { self.latestSuggestion = suggestion }
                    let finalResult = try await ts.pollForResult(jobId: jobId)
                    await MainActor.run {
                        self.latestSuggestion = finalResult
                        self.isFetching = false
                    }
                    return
                }

                await MainActor.run {
                    self.latestSuggestion = suggestion
                    self.isFetching = false
                }
            } catch {
                print("Failed to query GTO solver: \(error)")
                await MainActor.run { self.isFetching = false }
            }
        }
    }
}
