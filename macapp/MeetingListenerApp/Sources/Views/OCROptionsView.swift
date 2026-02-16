import SwiftUI

struct OCROptionsView: View {
    @AppStorage("ocrEnabled") private var enabled = false
    @AppStorage("ocrInterval") private var interval = 30
    @AppStorage("ocrShowIndicator") private var showIndicator = true
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Screen Content Capture", isOn: $enabled)
                
                if enabled {
                    Picker("Capture Interval", selection: $interval) {
                        Text("10 seconds").tag(10)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("5 minutes").tag(300)
                    }
                    
                    Toggle("Show Menu Bar Indicator", isOn: $showIndicator)
                }
            } footer: {
                Text("Screen content capture helps EchoPanel understand presentations and documents shared during meetings. Content is processed locally and stored as searchable text.")
                    .font(.caption)
            }
            
            if enabled {
                Section("Privacy") {
                    Label("Screen content is opt-in", systemImage: "checkmark.shield")
                        .foregroundColor(.green)
                    Text("Images are processed immediately and discarded. Only extracted text is stored.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Screen Capture")
    #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
    #endif
    }
}
