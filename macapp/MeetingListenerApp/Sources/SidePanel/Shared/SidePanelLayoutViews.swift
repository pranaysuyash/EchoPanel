import AppKit
import SwiftUI

extension SidePanelView {
    func topBar(panelWidth: CGFloat) -> some View {
        let isNarrow = panelWidth < 600
        let pickerWidth = min(
            max(panelWidth * (viewMode == .full ? 0.32 : 0.42), 170),
            viewMode == .full ? 300 : 250
        )

        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EchoPanel")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(statusTitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isNarrow {
                    EmptyView()
                } else {
                    Picker("View mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: pickerWidth)
                    .accessibilityLabel("View mode")
                }
            }

            HStack(spacing: 6) {
                statusPill

                Text(appState.timerText)
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(chipBackgroundColor)
                    .clipShape(Capsule())

                if !showCaptureDetails {
                    Button("Audio Setup") {
                        showCaptureDetails = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }

            if isNarrow {
                Picker("View mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("View mode")
            }
        }
    }

    func captureBar(panelWidth: CGFloat) -> some View {
        let stacked = panelWidth < 560
        let collapsed = !showCaptureDetails

        return VStack(spacing: 8) {
            if collapsed {
                HStack(spacing: 6) {
                    Text("Audio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.audioSource.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Toggle("Follow", isOn: $followLive)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    qualityChip
                    if captureNeedsAttention {
                        Text("Attention")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Button("Audio Setup") {
                        showCaptureDetails = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(appState.sourceTroubleshootingHint ?? appState.captureRouteDescription)
                    .font(.caption2)
                    .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
                    .lineLimit(2)
            } else if stacked {
                Picker("Audio source", selection: $appState.audioSource) {
                    ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(appState.sessionState == .listening)
                .accessibilityLabel("Audio source")
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    Toggle("Follow", isOn: $followLive)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Follow live")

                    Spacer()

                    Button("?") {
                        showShortcutOverlay.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Keyboard shortcuts")
                    .accessibilityLabel("Keyboard shortcuts")

                    Button("Hide") {
                        showCaptureDetails = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                HStack(spacing: 10) {
                    Picker("Audio source", selection: $appState.audioSource) {
                        ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(appState.sessionState == .listening)
                    .accessibilityLabel("Audio source")
                    .layoutPriority(1)

                    Toggle("Follow", isOn: $followLive)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Follow live")

                    Button("?") {
                        showShortcutOverlay.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Keyboard shortcuts")
                    .accessibilityLabel("Keyboard shortcuts")

                    Button("Hide") {
                        showCaptureDetails = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if !collapsed {
                ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if appState.audioSource == .system || appState.audioSource == .both {
                        AudioLevelMeter(label: "Sys", level: appState.systemAudioLevel)
                    }
                    if appState.audioSource == .microphone || appState.audioSource == .both {
                        AudioLevelMeter(label: "Mic", level: appState.microphoneAudioLevel)
                    }

                    Spacer()

                    qualityChip
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        if appState.audioSource == .system || appState.audioSource == .both {
                            AudioLevelMeter(label: "Sys", level: appState.systemAudioLevel)
                        }
                        if appState.audioSource == .microphone || appState.audioSource == .both {
                            AudioLevelMeter(label: "Mic", level: appState.microphoneAudioLevel)
                        }
                    }

                    qualityChip
                }
                }

                sourceDiagnosticsStrip
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.42 : 0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    func content(panelWidth: CGFloat) -> some View {
        Group {
            switch viewMode {
            case .roll:
                rollRenderer(panelWidth: panelWidth)
            case .compact:
                compactRenderer(panelWidth: panelWidth)
            case .full:
                fullRenderer(panelWidth: panelWidth)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: viewMode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: visibleTranscriptSegments)
    }
}
