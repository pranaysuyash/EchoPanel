import AppKit
import SwiftUI

// MARK: - Chrome Views Extension
// HIG-compliant chrome, backgrounds, and shared UI components

extension SidePanelView {

    // MARK: - Shortcut Overlay
    var shortcutOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    showShortcutOverlay = false
                }

            VStack(alignment: .leading, spacing: Spacing.sm + 2) {
                HStack {
                    Text("Keyboard")
                        .font(Typography.title)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        showShortcutOverlay = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close keyboard help")
                }

                ShortcutRow(label: "Move focus", key: "↑ / ↓")
                ShortcutRow(label: "Toggle lens", key: "Enter")
                ShortcutRow(label: "Pin / unpin", key: "P")
                ShortcutRow(label: "Follow live", key: "Space")
                ShortcutRow(label: "Jump to live", key: "J")
                ShortcutRow(label: "Surfaces", key: "← / →")
                ShortcutRow(label: "Close layer", key: "Esc")
                ShortcutRow(label: "Help", key: "?")

                Text("Arrows move focus unless a surface overlay is open.")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, Spacing.xs)
            }
            .padding(Spacing.md + 2)
            .frame(width: 340)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
            )
            .onTapGesture {
                // Consume taps so only backdrop closes the overlay.
            }
        }
    }

    // MARK: - Panel Background
    var panelBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.38),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.08),
                                Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 14, x: 0, y: 8)
    }

    // MARK: - Receipt Background (Deprecated - kept for compatibility)
    // HIG Note: Using container background for consistency
    var receiptBackground: some View {
        BackgroundStyle.container.color(for: colorScheme)
    }

    // MARK: - Quality Chip
    var qualityChip: some View {
        Text("Audio \(appState.audioQuality.rawValue)")
            .font(Typography.captionSmall)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(qualityColor(appState.audioQuality).opacity(0.14))
            .foregroundColor(qualityColor(appState.audioQuality))
            .clipShape(Capsule())
            .accessibilityLabel("Audio quality: \(appState.audioQuality.rawValue)")
    }

    // MARK: - Source Diagnostics Strip
    var sourceDiagnosticsStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(appState.activeSourceProbes) { probe in
                        sourceProbeChip(probe)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.activeSourceProbes) { probe in
                        sourceProbeChip(probe)
                    }
                }
            }

            Text(appState.sourceTroubleshootingHint ?? appState.captureRouteDescription)
                .font(Typography.captionSmall)
                .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
                .lineLimit(2)
        }
    }

    func sourceProbeChip(_ probe: AppState.SourceProbe) -> some View {
        HStack(spacing: 5) {
            Text(probe.label)
                .font(Typography.captionSmall)
                .fontWeight(.semibold)

            Circle()
                .fill(probe.inputIsFresh ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 5, height: 5)

            Text("In \(probe.inputAgeText)")
                .font(Typography.captionSmall)
                .foregroundColor(.secondary)

            Text("ASR \(probe.asrAgeText)")
                .font(Typography.captionSmall)
                .foregroundColor(probe.asrIsFresh ? .green : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(BackgroundStyle.input.color(for: colorScheme))
        .clipShape(Capsule())
    }

    // MARK: - Status Pill
    var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sessionStatusColor)
                .frame(width: 7, height: 7)
            Text(statusShort)
                .font(Typography.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(sessionStatusColor.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityLabel("Session status: \(statusShort)")
    }

    // MARK: - No Audio Banner
    var noAudioBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.slash.fill")
                .foregroundColor(.orange)
            Text(appState.silenceMessage)
                .font(Typography.caption)
                .foregroundColor(.orange)
                .lineLimit(2)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm + 2, style: .continuous))
        .accessibilityLabel("No audio detected: \(appState.silenceMessage)")
    }

    func userNoticeBanner(_ notice: AppState.UserNotice) -> some View {
        let palette: (text: Color, background: Color, icon: String)
        switch notice.level {
        case .info:
            palette = (.secondary, Color.secondary.opacity(0.12), "info.circle.fill")
        case .success:
            palette = (.green, Color.green.opacity(0.12), "checkmark.circle.fill")
        case .error:
            palette = (.red, Color.red.opacity(0.12), "exclamationmark.triangle.fill")
        }

        return HStack(spacing: 6) {
            Image(systemName: palette.icon)
                .foregroundColor(palette.text)
            Text(notice.message)
                .font(Typography.caption)
                .foregroundColor(palette.text)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                appState.clearUserNotice()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundColor(palette.text)
            .accessibilityLabel("Dismiss notice")
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm + 2, style: .continuous))
        .accessibilityLabel(notice.message)
    }

    // MARK: - Empty Transcript State
    var emptyTranscriptState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Waiting for speech")
                .font(.callout)
                .fontWeight(.semibold)
            Text("Source: \(appState.audioSource.rawValue) · first transcript usually appears in 2-5 seconds.")
                .font(Typography.caption)
                .foregroundColor(.secondary)
            Text(appState.sourceTroubleshootingHint ?? appState.captureRouteDescription)
                .font(Typography.captionSmall)
                .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
            Text("Use ↑/↓ to move focus, Enter for lens, P to pin.")
                .font(Typography.captionSmall)
                .foregroundColor(.secondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BackgroundStyle.container.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Focus Lens
    func focusLens(segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm + 2) {
            HStack {
                Text("Focus Lens")
                    .font(Typography.caption)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Line \(focusedLineLabel)")
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                lensTag("Decision", tint: .green)
                lensTag("Trade-off", tint: .orange)
                lensTag("Risk", tint: .red)
                lensTag("Entity", tint: .blue)
            }

            HStack(spacing: 6) {
                ForEach(Surface.allCases) { surface in
                    Button(surface.rawValue) {
                        activeSurface = surface
                        if viewMode == .full {
                            showSurfaceOverlay = false
                        } else {
                            showSurfaceOverlay = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel("Open \(surface.rawValue) surface")
                    .accessibilityHint("Switches the insight surface to \(surface.rawValue).")
                }
            }
        }
        .padding(Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BackgroundStyle.container.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
        )
    }

    func lensTag(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(Typography.captionSmall)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }

    func smallStateBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(Typography.captionSmall)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }

    func surfaceEmptyState(text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(Spacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BackgroundStyle.card.color(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm + 2, style: .continuous))
    }

    func surfaceItemCard(tag: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tag)
                    .font(Typography.captionSmall)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.14))
                    .clipShape(Capsule())
                Spacer()
            }

            Text(title)
                .font(.footnote)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(subtitle)
                .font(Typography.captionSmall)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BackgroundStyle.control.color(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md + 1, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tag). \(title)")
        .accessibilityValue(subtitle)
    }

    // MARK: - Window Backdrop
    var windowBackdrop: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Legacy Color Properties (for backward compatibility)
    var chipBackgroundColor: Color {
        BackgroundStyle.control.color(for: colorScheme)
    }

    var contentBackgroundColor: Color {
        BackgroundStyle.container.color(for: colorScheme)
    }

    var strokeColor: Color {
        StrokeStyle.standard.color(for: colorScheme)
    }

    // MARK: - Animation Helper
    func performAnimatedUpdate(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeOut(duration: AnimationDuration.standard), updates)
        }
    }
    
    // MARK: - Voice Note UI
    /// Recording indicator shown when voice note is being recorded
    var voiceNoteRecordingIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .modifier(PulsingDot())
            Text("Recording")
                .font(Typography.captionSmall)
                .foregroundColor(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityLabel("Voice note recording in progress")
    }
    
    /// Button to toggle voice note recording
    var recordVoiceNoteButton: some View {
        Button {
            Task {
                await appState.toggleVoiceNoteRecording()
            }
        } label: {
            Image(systemName: appState.isRecordingVoiceNote ? "stop.circle.fill" : "mic.circle")
                .font(.title3)
                .foregroundColor(appState.isRecordingVoiceNote ? .red : .accentColor)
        }
        .buttonStyle(.plain)
        .help(appState.isRecordingVoiceNote ? "Stop voice note (⌘⇧V)" : "Record voice note (⌘⇧V)")
        .accessibilityLabel(appState.isRecordingVoiceNote ? "Stop voice note recording" : "Start voice note recording")
        .disabled(appState.sessionState != .listening)
    }
    
    // MARK: - Pulsing Dot Animation
    struct PulsingDot: ViewModifier {
        @State private var isPulsing = false
        
        func body(content: Content) -> some View {
            content
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .opacity(isPulsing ? 0.7 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear {
                    isPulsing = true
                }
        }
    }
}
