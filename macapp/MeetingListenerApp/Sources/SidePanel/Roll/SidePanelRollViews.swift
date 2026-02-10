import AppKit
import SwiftUI

// MARK: - Roll View Mode
// HIG-compliant receipt-style transcript view

extension SidePanelView {
    func rollRenderer(panelWidth: CGFloat) -> some View {
        VStack(spacing: Spacing.sm + 2) {  // 10pt spacing
            transcriptToolbar(panelWidth: panelWidth, showSurfaceButtons: false)
                .accessibilitySortPriority(Accessibility.SortPriority.content)

            ZStack {
                transcriptScroller(style: .roll)
                    // HIG Fix: Using container background for consistency
                    // Receipt background was unique but inconsistent
                    .background(BackgroundStyle.container.color(for: colorScheme))
                    // HIG Fix: Standardized corner radius to 12pt (was 16pt)
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

            rollFooter
                .accessibilitySortPriority(Accessibility.SortPriority.footer)
        }
    }

    // HIG Fix: Renamed from rollFooterState to rollFooter for consistency
    var rollFooter: some View {
        HStack(spacing: Spacing.sm) {
            smallStateBadge(title: followLive ? "Follow ON" : "Follow OFF", tint: followLive ? .green : .orange)
            smallStateBadge(title: "Focus \(focusedLineLabel)", tint: .blue)
            smallStateBadge(title: "Pins \(pinnedSegmentIDs.count)", tint: .indigo)

            Spacer()

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

            if !followLive {
                Button("Jump Live") {
                    jumpToLive()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Jump to live transcript")
                .accessibilityHint("Press J to jump to latest transcript")
            }
        }
    }
}
