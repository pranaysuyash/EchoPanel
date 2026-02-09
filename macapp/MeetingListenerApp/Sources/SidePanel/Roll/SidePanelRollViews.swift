import AppKit
import SwiftUI

extension SidePanelView {
    func rollRenderer(panelWidth: CGFloat) -> some View {
        VStack(spacing: 10) {
            transcriptToolbar(panelWidth: panelWidth, showSurfaceButtons: false)
                .accessibilitySortPriority(300)

            ZStack {
                transcriptScroller(style: .roll)
                    .background(receiptBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    )

                if showSurfaceOverlay {
                    surfaceOverlay
                }
            }
            .accessibilitySortPriority(200)

            rollFooterState
                .accessibilitySortPriority(100)
        }
    }

    var rollFooterState: some View {
        HStack(spacing: 8) {
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

            if !followLive {
                Button("Jump Live") {
                    jumpToLive()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}
