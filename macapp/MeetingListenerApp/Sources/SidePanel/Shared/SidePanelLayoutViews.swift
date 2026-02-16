import AppKit
import SwiftUI

// MARK: - Layout Views Extension
// HIG-compliant top bar, capture bar, and content layout

extension SidePanelView {

    // MARK: - Top Bar
    func topBar(panelWidth: CGFloat) -> some View {
        let isNarrow = panelWidth < 600
        // HIG: Consistent picker width calculation
        let pickerWidth = min(
            max(panelWidth * (viewMode == .full ? 0.32 : 0.42), 170),
            viewMode == .full ? 300 : 250
        )

        return VStack(spacing: 6) {
            HStack(alignment: .top, spacing: Spacing.sm + 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EchoPanel")
                        .font(Typography.titleLarge)
                    Text(statusTitle)
                        .font(Typography.captionSmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.sm)

                if isNarrow {
                    EmptyView()
                } else {
                    Picker("View mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.rawValue)
                                .help(modeHelpText(for: mode))
                                .tag(mode)
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
                    .font(Typography.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(chipBackgroundColor)
                    .clipShape(Capsule())

                if !showCaptureDetails && viewMode != .full {
                    // HIG: Full mode has capture bar integrated, so no button needed
                    Button("Audio Setup") {
                        showCaptureDetails = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Toggle(isOn: $alwaysOnTop) {
                    Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help(alwaysOnTop ? "Always on top (On)" : "Always on top (Off)")
                .accessibilityLabel(alwaysOnTop ? "Disable always on top" : "Enable always on top")

                Spacer()
            }

            if isNarrow {
                Picker("View mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue)
                            .help(modeHelpText(for: mode))
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("View mode")
            }
        }
    }
    
    private func modeHelpText(for mode: ViewMode) -> String {
        switch mode {
        case .roll:
            return "Roll: Live transcript during meetings"
        case .compact:
            return "Compact: Quick glance at current meeting"
        case .full:
            return "Full: Review and search past sessions"
        }
    }

    // MARK: - Capture Bar
    // HIG Note: Full mode has its own capture bar (fullCaptureBar)
    func captureBar(panelWidth: CGFloat) -> some View {
        let stacked = panelWidth < 560
        let collapsed = !showCaptureDetails

        return VStack(spacing: Spacing.sm + 2) {
            if collapsed {
                HStack(spacing: 6) {
                    Text("Audio")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                    Text(appState.audioSource.rawValue)
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                    Toggle("Follow", isOn: $transcriptUI.followLive)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    qualityChip
                    
                    // Voice note recording indicator
                    if appState.isRecordingVoiceNote {
                        voiceNoteRecordingIndicator
                    }
                    
                    // Record voice note button
                    recordVoiceNoteButton
                    
                    if captureNeedsAttention {
                        Text("Attention")
                            .font(Typography.captionSmall)
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
                    .font(Typography.captionSmall)
                    .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
                    .lineLimit(2)
            } else if stacked {
                VStack(spacing: Spacing.sm) {
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

                    HStack(spacing: Spacing.md) {
                        Toggle("Follow", isOn: $transcriptUI.followLive)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel("Follow live")

                        Spacer()
                        
                        // Record voice note button in stacked expanded mode
                        recordVoiceNoteButton

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
            } else {
                HStack(spacing: Spacing.md) {
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

                    Toggle("Follow", isOn: $transcriptUI.followLive)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Follow live")
                    
                    // Voice note recording indicator in expanded mode
                    if appState.isRecordingVoiceNote {
                        voiceNoteRecordingIndicator
                    }
                    
                    // Record voice note button in expanded mode
                    recordVoiceNoteButton

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
                    HStack(spacing: Spacing.md) {
                        if appState.audioSource == .system || appState.audioSource == .both {
                            AudioLevelMeter(label: "Sys", level: appState.systemAudioLevel)
                        }
                        if appState.audioSource == .microphone || appState.audioSource == .both {
                            AudioLevelMeter(label: "Mic", level: appState.microphoneAudioLevel)
                        }

                        Spacer()

                        qualityChip
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.md) {
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
        .padding(Spacing.sm + 2)
        .background(BackgroundStyle.control.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Content Router
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
        // HIG: Respect reduce motion preference
        .animation(reduceMotion ? nil : .easeInOut(duration: AnimationDuration.standard), value: viewMode)
    }
}