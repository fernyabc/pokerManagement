import Foundation

/// Protocol defining how the app communicates with any GTO solver.
/// This allows us to easily swap between a Mock, a custom Python backend, or a Third-Party API.
protocol GTOSolverProtocol {
    func analyzeState(_ state: DetectedPokerState) async throws -> GTOSuggestion
}

/// A Mock Service for testing UI and Vision pipeline without hitting a real API
class MockGTOSolver: GTOSolverProtocol {
    func analyzeState(_ state: DetectedPokerState) async throws -> GTOSuggestion {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Return a mock response
        return GTOSuggestion(
            action: "Raise",
            raiseSize: 45.0,
            ev: 2.34,
            confidence: 0.85,
            reasoning: "AK suited from Middle Position facing a single raiser should frequently 3-bet. Mocked response."
        )
    }
}

/// A Template for connecting to a Third-Party GTO API (e.g., PioSolver SaaS, GPT-4 Vision, or Gemini API)
class ThirdPartyGTOSolver: GTOSolverProtocol {
    let apiKey: String
    let endpoint: URL
    
    init(apiKey: String, endpoint: URL) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }
    
    func analyzeState(_ state: DetectedPokerState) async throws -> GTOSuggestion {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encode the detected state into the specific format required by the 3rd party API
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(state)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        // Decode the third-party response into our app's GTOSuggestion model
        let suggestion = try JSONDecoder().decode(GTOSuggestion.self, from: data)
        return suggestion
    }
}
