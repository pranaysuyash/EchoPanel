import AppKit
import SwiftUI

extension SidePanelView {
    func compactRenderer(panelWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            transcriptToolbar(panelWidth: panelWidth, showSurfaceButtons: false)
                .accessibilitySortPriority(300)

            ZStack {
                transcriptScroller(style: .compact)
                    .background(contentBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    )

                if showSurfaceOverlay {
                    surfaceOverlay
                }
            }
            .accessibilitySortPriority(200)

            HStack(spacing: 8) {
                smallStateBadge(title: followLive ? "Follow ON" : "Follow OFF", tint: followLive ? .green : .orange)
                smallStateBadge(title: "Focus \(focusedLineLabel)", tint: .blue)
                smallStateBadge(title: "Pins \(pinnedSegmentIDs.count)", tint: .indigo)
                Spacer()
                if !followLive {
                    Button("Live") { jumpToLive() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .accessibilitySortPriority(100)
        }
    }
}
