// DesignTokens.swift
// EchoPanel Design System
// Following Apple Human Interface Guidelines for macOS

import SwiftUI

// MARK: - Corner Radii
/// Standard corner radius values following HIG consistency principles
enum CornerRadius {
    /// 6pt - Badges, small chips, tags
    static let xs: CGFloat = 6
    /// 8pt - Buttons, controls, small containers
    static let sm: CGFloat = 8
    /// 10pt - Cards, list items, transcript rows
    static let md: CGFloat = 10
    /// 12pt - Containers, panels, surface overlays
    static let lg: CGFloat = 12
    /// 16pt - Main panel, modal containers
    static let xl: CGFloat = 16
}

// MARK: - Spacing
/// 8pt grid spacing system following HIG layout guidelines
enum Spacing {
    /// 4pt - Tight spacing, icon gaps
    static let xs: CGFloat = 4
    /// 8pt - Standard control spacing
    static let sm: CGFloat = 8
    /// 12pt - Card padding, section gaps
    static let md: CGFloat = 12
    /// 16pt - Container padding
    static let lg: CGFloat = 16
    /// 20pt - Section separation
    static let xl: CGFloat = 20
}

// MARK: - Animation Durations
/// Animation durations that respect reduce motion preferences
enum AnimationDuration {
    /// 0.10s - Micro-interactions, hover states
    static let instant: Double = 0.10
    /// 0.15s - Quick transitions, button feedback
    static let quick: Double = 0.15
    /// 0.20s - Standard transitions, view changes
    static let standard: Double = 0.20
    /// 0.30s - Emphasis animations, important changes
    static let emphasis: Double = 0.30
}

// MARK: - Semantic Background Colors
/// Background colors organized by hierarchy level per HIG
enum BackgroundStyle {
    /// Main panel background - ultra thin material with subtle tint
    case panel
    /// Transcript containers, main content areas
    case container
    /// Individual cards, rows, list items
    case card
    /// Controls, buttons, input fields
    case control
    /// Elevated elements: popovers, overlays, modals
    case elevated
    /// Input fields, text backgrounds
    case input
    /// Row hover/focus states
    case rowHover
    /// Row selected/focused states
    case rowSelected
    /// Pinned item highlight
    case rowPinned
    
    func color(for scheme: ColorScheme) -> Color {
        switch self {
        case .panel:
            // Ultra thin material with window background
            return Color.clear
            
        case .container:
            return Color(nsColor: .textBackgroundColor)
                .opacity(scheme == .dark ? 0.26 : 0.86)
            
        case .card:
            return Color(nsColor: .textBackgroundColor)
                .opacity(scheme == .dark ? 0.18 : 0.75)
            
        case .control:
            return Color(nsColor: .controlBackgroundColor)
                .opacity(scheme == .dark ? 0.45 : 0.65)
            
        case .elevated:
            return Color(nsColor: .windowBackgroundColor)
                .opacity(scheme == .dark ? 0.90 : 0.95)
            
        case .input:
            return Color(nsColor: .textBackgroundColor)
                .opacity(scheme == .dark ? 0.24 : 0.90)
            
        case .rowHover:
            return Color.accentColor
                .opacity(scheme == .dark ? 0.15 : 0.08)
            
        case .rowSelected:
            return Color.blue
                .opacity(scheme == .dark ? 0.20 : 0.10)
            
        case .rowPinned:
            return Color.indigo
                .opacity(scheme == .dark ? 0.15 : 0.10)
        }
    }
}

// MARK: - Stroke/Border Colors
/// Separator and border colors
enum StrokeStyle {
    /// Standard separators between sections
    case standard
    /// Subtle separators for grouped content
    case subtle
    /// Focus rings and selected states
    case focus
    /// Pinned item borders
    case pinned
    
    func color(for scheme: ColorScheme) -> Color {
        switch self {
        case .standard:
            return Color(nsColor: .separatorColor)
                .opacity(scheme == .dark ? 0.50 : 0.25)
        case .subtle:
            return Color(nsColor: .separatorColor)
                .opacity(scheme == .dark ? 0.30 : 0.15)
        case .focus:
            return Color.blue.opacity(0.50)
        case .pinned:
            return Color.indigo.opacity(scheme == .dark ? 0.45 : 0.35)
        }
    }
}

// MARK: - Typography
/// Typography scale following HIG text styles
enum Typography {
    /// Large titles - Panel headers
    static let titleLarge = Font.system(size: 19, weight: .semibold, design: .rounded)
    /// Standard titles - Section headers
    static let title = Font.headline
    /// Subheadings - Card titles
    static let subtitle = Font.subheadline
    /// Body text - Transcript content
    static let body = Font.body
    /// Captions - Metadata, timestamps
    static let caption = Font.caption
    /// Small captions - Secondary metadata
    static let captionSmall = Font.caption2
    /// Monospace - Timestamps, technical data
    static let mono = Font.system(.caption, design: .monospaced)
    static let monoSmall = Font.system(.caption2, design: .monospaced)
}

// MARK: - Layout Constants
/// Fixed layout dimensions
enum Layout {
    /// Timestamp column width (00:00 format)
    static let timestampWidth: CGFloat = 44
    /// Speaker badge size (circle)
    static let speakerBadgeSize: CGFloat = 24
    /// Action buttons container width (3 buttons + spacing)
    static let actionContainerWidth: CGFloat = 84
    /// Row minimum height
    static let rowMinHeight: CGFloat = 16
    /// Confidence label minimum width
    static let confidenceMinWidth: CGFloat = 32
    /// Audio level meter width
    static let audioMeterWidth: CGFloat = 72
    /// Audio level meter height
    static let audioMeterHeight: CGFloat = 7
    /// Minimum touch target (HIG accessibility)
    static let minTouchTarget: CGFloat = 44
}

// MARK: - Accessibility
/// Accessibility constants following HIG
enum Accessibility {
    /// Minimum contrast ratio for normal text (HIG requirement)
    static let normalTextContrast: CGFloat = 4.5
    /// Minimum contrast ratio for large text (HIG requirement)
    static let largeTextContrast: CGFloat = 3.0
    /// Sort priority for major UI sections
    enum SortPriority {
        static let chrome: Double = 500
        static let navigation: Double = 400
        static let content: Double = 300
        static let secondary: Double = 200
        static let footer: Double = 100
    }
}

// MARK: - Confidence Thresholds
/// Confidence score thresholds for transcript display
enum ConfidenceThreshold {
    /// High confidence - green indicator
    static let high: Double = 0.8
    /// Medium confidence - neutral indicator
    static let medium: Double = 0.5
    /// Low confidence - orange indicator + needs review badge
    static let low: Double = 0.5
    /// Filter threshold - hide segments below this
    static let filter: Double = 0.3
}

// MARK: - View Mode Limits
/// Transcript segment limits per view mode
enum TranscriptLimits {
    static let roll: Int = 120
    static let compact: Int = 36
    static let full: Int = 500
}

// MARK: - View Mode Spacing
/// Spacing configuration per view mode
enum ViewModeSpacing {
    case roll
    case compact
    case full
    
    var rowSpacing: CGFloat {
        switch self {
        case .roll: return Spacing.sm + 2  // 10
        case .compact: return Spacing.sm   // 8
        case .full: return Spacing.sm      // 8
        }
    }
    
    var verticalPadding: CGFloat {
        switch self {
        case .roll: return Spacing.md + 2   // 14
        case .compact: return Spacing.md - 2 // 10
        case .full: return Spacing.md       // 12
        }
    }
    
    var horizontalPadding: CGFloat {
        switch self {
        case .roll: return Spacing.md + 2   // 14
        case .compact: return Spacing.md - 2 // 10
        case .full: return Spacing.md       // 12
        }
    }
    
    var containerCornerRadius: CGFloat {
        switch self {
        case .roll: return CornerRadius.lg      // 12
        case .compact: return CornerRadius.lg   // 12
        case .full: return CornerRadius.lg      // 12
        }
    }
}

// MARK: - Color Extensions for HIG Compliance
extension Color {
    /// Returns the color with appropriate opacity for the color scheme
    func adaptiveOpacity(dark: Double, light: Double, for scheme: ColorScheme) -> Color {
        self.opacity(scheme == .dark ? dark : light)
    }
}

// MARK: - View Modifiers
/// HIG-compliant view modifiers
struct HIGCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let isFocused: Bool
    let isPinned: Bool
    
    func body(content: Content) -> some View {
        content
            .padding(Spacing.sm + 2)  // 10pt padding
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
    
    private var backgroundColor: Color {
        if isFocused {
            return BackgroundStyle.rowSelected.color(for: colorScheme)
        }
        if isPinned {
            return BackgroundStyle.rowPinned.color(for: colorScheme)
        }
        return BackgroundStyle.card.color(for: colorScheme)
    }
    
    private var strokeColor: Color {
        if isFocused {
            return StrokeStyle.focus.color(for: colorScheme)
        }
        if isPinned {
            return StrokeStyle.pinned.color(for: colorScheme)
        }
        return StrokeStyle.standard.color(for: colorScheme)
    }
}

extension View {
    /// Apply HIG-compliant card styling
    func higCard(focused: Bool = false, pinned: Bool = false) -> some View {
        modifier(HIGCardStyle(isFocused: focused, isPinned: pinned))
    }
}
