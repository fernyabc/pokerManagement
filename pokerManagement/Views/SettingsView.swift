import SwiftUI

struct SettingsView: View {
    @Binding var useMockSolver: Bool
    @Binding var solverEndpoint: String
    @Binding var solverAPIKey: String
    @Binding var selectedVideoInput: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Video Input") {
                    Picker("Source", selection: $selectedVideoInput) {
                        ForEach(VideoInputType.allCases) { type in
                            Text(type.rawValue).tag(type.rawValue)
                        }
                    }
                }

                Section("Solver") {
                    Toggle("Use Mock Solver", isOn: $useMockSolver)
                    if !useMockSolver {
                        TextField("Endpoint", text: $solverEndpoint)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                        SecureField("API Key", text: $solverAPIKey)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
