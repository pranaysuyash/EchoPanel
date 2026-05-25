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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                smallStateBadge(title: transcriptUI.followLive ? "Following live" : "Reviewing backlog", tint: transcriptUI.followLive ? .green : .orange)
                smallStateBadge(title: "Focus \(focusedLineLabel)", tint: .blue)
                smallStateBadge(title: "Pins \(transcriptUI.pinnedSegmentIDs.count)", tint: .indigo)
                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                Text("Use this mode to stay on the live transcript and open insights only when something needs attention.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Spacer(minLength: Spacing.sm)

                Button("Insights") {
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
        }
    }
}
