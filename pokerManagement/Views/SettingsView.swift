import SwiftUI

struct SettingsView: View {
    @AppStorage("useMockSolver") private var useMockSolver = true
    @AppStorage("solverAPIKey") private var solverAPIKey = ""
    @AppStorage("solverEndpoint") private var solverEndpoint = "http://localhost:8000/v1/solve"
    @AppStorage("visionModelName") private var visionModelName = "YOLO_Cards_v2.mlmodel"
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("GTO Solver Backend")) {
                    Toggle("Use Local Mock Solver", isOn: $useMockSolver)
                    
                    if !useMockSolver {
                        TextField("Endpoint URL", text: $solverEndpoint)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        
                        SecureField("API Key", text: $solverAPIKey)
                    }
                }
                
                Section(header: Text("Vision Configuration"), footer: Text("Configure the underlying CoreML models for the Meta glasses video stream.")) {
                    TextField("Model File", text: $visionModelName)
                        .autocapitalization(.none)
                }
                
                Section {
                    Button("Reset to Defaults") {
                        useMockSolver = true
                        solverAPIKey = ""
                        solverEndpoint = "http://localhost:8000/v1/solve"
                        visionModelName = "YOLO_Cards_v2.mlmodel"
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
