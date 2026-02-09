import AppKit
import SwiftUI

extension SidePanelView {
    var shortcutOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    showShortcutOverlay = false
                }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Keyboard")
                        .font(.headline)
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(width: 340)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .onTapGesture {
                // Consume taps so only backdrop closes the overlay.
            }
        }
    }

    var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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

    var receiptBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.34 : 0.94),
                Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.22 : 0.88)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var qualityChip: some View {
        Text("Audio \(appState.audioQuality.rawValue)")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(qualityColor(appState.audioQuality).opacity(0.14))
            .foregroundColor(qualityColor(appState.audioQuality))
            .clipShape(Capsule())
    }

    var sourceDiagnosticsStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                .font(.caption2)
                .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
                .lineLimit(2)
        }
    }

    func sourceProbeChip(_ probe: AppState.SourceProbe) -> some View {
        HStack(spacing: 5) {
            Text(probe.label)
                .font(.caption2)
                .fontWeight(.semibold)

            Circle()
                .fill(probe.inputIsFresh ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 5, height: 5)

            Text("In \(probe.inputAgeText)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("ASR \(probe.asrAgeText)")
                .font(.caption2)
                .foregroundColor(probe.asrIsFresh ? .green : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.24 : 0.72))
        .clipShape(Capsule())
    }

    var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(sessionStatusColor)
                .frame(width: 7, height: 7)
            Text(statusShort)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(sessionStatusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    var noAudioBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.slash.fill")
                .foregroundColor(.orange)
            Text(appState.silenceMessage)
                .font(.caption)
                .foregroundColor(.orange)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var emptyTranscriptState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Waiting for speech")
                .font(.callout)
                .fontWeight(.semibold)
            Text("Source: \(appState.audioSource.rawValue) · first transcript usually appears in 2-5 seconds.")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(appState.sourceTroubleshootingHint ?? appState.captureRouteDescription)
                .font(.caption2)
                .foregroundColor(appState.sourceTroubleshootingHint == nil ? .secondary : .orange)
            Text("Use ↑/↓ to move focus, Enter for lens, P to pin.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    func focusLens(segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Focus Lens")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Line \(focusedLineLabel)")
                    .font(.caption2)
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(contentBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
    }

    func lensTag(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16))
            .foregroundColor(tint)
            .clipShape(Capsule())
    }

    func smallStateBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2)
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
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.3 : 0.66))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func surfaceItemCard(tag: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tag)
                    .font(.caption2)
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
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.56))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tag). \(title)")
        .accessibilityValue(subtitle)
    }

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

    var chipBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.45 : 0.65)
    }

    var contentBackgroundColor: Color {
        Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.26 : 0.86)
    }

    var strokeColor: Color {
        Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.58 : 0.24)
    }

    func performAnimatedUpdate(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeOut(duration: 0.2), updates)
        }
    }
}
