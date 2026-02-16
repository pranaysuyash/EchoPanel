import AppKit
import SwiftUI

// MARK: - Compact View Mode
// HIG-compliant minimal companion view

extension SidePanelView {
    func compactRenderer(panelWidth: CGFloat) -> some View {
        VStack(spacing: Spacing.sm) {  // 8pt spacing per HIG
            transcriptToolbar(panelWidth: panelWidth, showSurfaceButtons: false)
                .accessibilitySortPriority(Accessibility.SortPriority.content)

            ZStack {
                transcriptScroller(style: .compact)
                    // HIG Fix: Standardized background color
                    .background(BackgroundStyle.container.color(for: colorScheme))
                    // HIG Fix: Standardized corner radius (12pt)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .stroke(StrokeStyle.standard.color(for: colorScheme), lineWidth: 1)
                    )

                if showSurfaceOverlay {
                    surfaceOverlay
                }
            }
            .accessibilitySortPriority(Accessibility.SortPriority.content)

            // HIG Fix: Added Surfaces button for feature parity (C1)
            HStack(spacing: Spacing.sm) {
                smallStateBadge(title: transcriptUI.followLive ? "Follow ON" : "Follow OFF", tint: transcriptUI.followLive ? .green : .orange)
                smallStateBadge(title: "Focus \(focusedLineLabel)", tint: .blue)
                smallStateBadge(title: "Pins \(transcriptUI.pinnedSegmentIDs.count)", tint: .indigo)

                Spacer()

                // HIG Fix: Added Surfaces button (was missing in Compact)
                Button("Surfaces") {
                    if showSurfaceOverlay {
                        showSurfaceOverlay = false
                    } else {
                        showSurfaceOverlay = true
                        activeSurface = .summary
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Toggle surfaces overlay")
                .accessibilityHint("Shows summary, actions, pins, and entities")

                // HIG Fix: Standardized button label to "Jump Live"
                if !transcriptUI.followLive {
                    Button("Jump Live") {
                        jumpToLive()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Jump to live transcript")
                    .accessibilityHint("Press J to jump to latest transcript")
                }
            }
            .accessibilitySortPriority(Accessibility.SortPriority.footer)
        }
    }
}
