import SwiftUI

struct DemoPanelView: View {
    @ObservedObject var appState: AppState
    let onSeedData: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("EchoPanel Demo Mode")
                .font(.title)
                .padding()
            
            Text("This window demonstrates the EchoPanel interface with sample data.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button("Load Demo Data") {
                onSeedData()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            
            Spacer()
            
            if !appState.transcriptSegments.isEmpty {
                VStack(alignment: .leading) {
                    Text("Transcript Segments: \(appState.transcriptSegments.count)")
                    Text("Entities: \(appState.entities.count)")
                    Text("Actions: \(appState.actions.count)")
                    Text("Decisions: \(appState.decisions.count)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .padding()
    }
}

#Preview {
    DemoPanelView(appState: AppState()) {
        print("Seed data")
    }
}
