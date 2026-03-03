import Foundation

protocol GTOSolverProtocol {
    func analyzeState(_ state: DetectedPokerState) async throws -> GTOSuggestion
}

// MARK: - Mock

class MockGTOSolver: GTOSolverProtocol {
    func analyzeState(_ state: DetectedPokerState) async throws -> GTOSuggestion {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        return GTOSuggestion(
            action: "Raise", raiseSize: 45.0, ev: 2.34, confidence: 0.85,
            reasoning: "AK suited facing a single raiser — 3-bet. (Mock)",
            foldWeight: 0.05, callWeight: 0.10, raiseWeight: 0.85,
            isSolving: false, jobId: nil
        )
    }
}

// MARK: - TexasSolver (POST /v1/solve/gto)

/// Backend response from the TexasSolver endpoint.
private struct SolveResponse: Decodable {
    let strategy: [String: Double]   // {"Fold": 0.2, "Call": 0.5, "Raise": 0.3}
    let ev: Double
    let exploitability: Double
    let iterations: Int
}

class TexasSolverAPI: GTOSolverProtocol {
    let apiKey: String
    let baseURL: URL    // e.g. http://localhost:8000

    init(apiKey: String, baseURL: URL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func analyzeState(_ state: DetectedPokerState) async throws -> GTOSuggestion {
        let endpoint = baseURL.appendingPathComponent("v1/solve/gto")
        // Build the request body the backend expects
        struct SolveRequest: Encodable {
            let board: [String]
            let pot: Double
            let effective_stack: Double
        }

        let body = SolveRequest(
            board: state.communityCards,
            pot: state.potSize > 0 ? state.potSize : 10.0,
            effective_stack: 100.0
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let res = try JSONDecoder().decode(SolveResponse.self, from: data)

        let fold = res.strategy["Fold"] ?? 0
        let call = res.strategy["Call"] ?? 0
        let raise = res.strategy["Raise"] ?? 0
        let primary = res.strategy.max(by: { $0.value < $1.value })?.key ?? "Call"
        let raiseSize: Double? = primary == "Raise" ? state.potSize * 0.75 : nil

        return GTOSuggestion(
            action: primary, raiseSize: raiseSize, ev: res.ev, confidence: raise,
            reasoning: "GTO weights — F:\(Int(fold*100))% C:\(Int(call*100))% R:\(Int(raise*100))%  (iter: \(res.iterations))",
            foldWeight: fold, callWeight: call, raiseWeight: raise,
            isSolving: false, jobId: nil
        )
    }

    func pollForResult(jobId: String, maxAttempts: Int = 60, interval: UInt64 = 3) async throws -> GTOSuggestion {
        let pollURL = baseURL.appendingPathComponent("v1/solve/status/\(jobId)")
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: interval * 1_000_000_000)
            var req = URLRequest(url: pollURL)
            req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
            let suggestion = try JSONDecoder().decode(GTOSuggestion.self, from: data)
            if suggestion.isSolving != true { return suggestion }
        }
        throw URLError(.timedOut)
    }
}

// MARK: - LLM Engine (POST /v1/solve/llm)

/// Backend response from the LLM endpoint.
private struct LLMSolveResponse: Decodable {
    let action: String
    let reasoning: String
}

class LLMSolverAPI: GTOSolverProtocol {
    let apiKey: String
    let baseURL: URL    // e.g. http://localhost:8000

    init(apiKey: String, baseURL: URL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func analyzeState(_ state: DetectedPokerState) async throws -> GTOSuggestion {
        let endpoint = baseURL.appendingPathComponent("v1/solve/llm")
        struct LLMRequest: Encodable {
            let holeCards: [String]
            let communityCards: [String]
            let position: String
            let numPlayers: Int
            let potSize: Double
        }

        let positions = ["UTG", "MP", "CO", "BTN", "SB", "BB"]
        let pos = state.myPosition < positions.count ? positions[state.myPosition] : "BTN"

        let body = LLMRequest(
            holeCards: state.holeCards,
            communityCards: state.communityCards,
            position: pos,
            numPlayers: state.numPlayers > 0 ? state.numPlayers : 6,
            potSize: state.potSize > 0 ? state.potSize : 1.5
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let res = try JSONDecoder().decode(LLMSolveResponse.self, from: data)

        return GTOSuggestion(
            action: res.action, raiseSize: res.action == "Raise" ? state.potSize * 2.5 : nil,
            ev: nil, confidence: nil, reasoning: res.reasoning,
            foldWeight: nil, callWeight: nil, raiseWeight: nil,
            isSolving: false, jobId: nil
        )
    }
}
