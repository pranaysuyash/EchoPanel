import SwiftUI

// MARK: - Colors
extension Color {
    // Semantic colors that adapt to system settings
    static let appBackground = Color(NSColor.windowBackgroundColor)
    static let appSecondaryBackground = Color(NSColor.underPageBackgroundColor)
    static let appTertiaryBackground = Color(NSColor.controlBackgroundColor)
    
    // Semantic status colors
    static let statusSuccess = Color.green
    static let statusWarning = Color.orange
    static let statusError = Color.red
    static let statusInfo = Color.blue
    
    // Card backgrounds
    static let cardBackground = Color(NSColor.controlBackgroundColor)
    static let cardBorder = Color(NSColor.separatorColor)
}

// MARK: - Spacing
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Corner Radii
enum CornerRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

// MARK: - Typography
extension Font {
    static let appTitle = Font.title3.weight(.semibold)
    static let appHeadline = Font.headline
    static let appBody = Font.body
    static let appCaption = Font.caption
    static let appCaption2 = Font.caption2
    static let appMonospaced = Font.body.monospaced()
}

// MARK: - Materials
enum AppMaterial {
    static let sidebar = Material.ultraThinMaterial
    static let toolbar = Material.thinMaterial
    static let card = Material.regularMaterial
    static let popover = Material.thinMaterial
}

// MARK: - View Modifiers
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .background(AppMaterial.card)
            .cornerRadius(CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Color.cardBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Status Indicator
struct StatusDot: View {
    enum Status {
        case idle
        case active
        case warning
        case error
    }
    
    let status: Status
    
    var color: Color {
        switch status {
        case .idle: return .secondary
        case .active: return .statusSuccess
        case .warning: return .statusWarning
        case .error: return .statusError
        }
    }
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.appHeadline)
                
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
