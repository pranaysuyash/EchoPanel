import SwiftUI

// MARK: - Icon Styles

enum IconSize {
    case small     // 12-14pt (inline, status)
    case medium    // 18-22pt (buttons, list items)
    case large     // 28-32pt (toolbar, header)
    case extraLarge // 40-48pt (hero, empty states)
    
    var dimension: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 20
        case .large: return 30
        case .extraLarge: return 44
        }
    }
}

enum IconColorTheme {
    case recording    // Red/Orange
    case recordingStop // Red
    case audio        // Blue/Purple
    case analysis     // Purple/Pink
    case people       // Green/Teal
    case system       // Gray/Blue-Gray
    case success      // Green
    case warning      // Orange
    case error        // Red
    case info         // Blue
    case accent       // App accent
    
    var gradient: LinearGradient {
        switch self {
        case .recording:
            return LinearGradient(
                colors: [Color(hex: "FF3B30"), Color(hex: "FF9500")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .recordingStop:
            return LinearGradient(
                colors: [Color(hex: "FF3B30"), Color(hex: "FF6B6B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .audio:
            return LinearGradient(
                colors: [Color(hex: "007AFF"), Color(hex: "AF52DE")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .analysis:
            return LinearGradient(
                colors: [Color(hex: "AF52DE"), Color(hex: "FF2D55")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .people:
            return LinearGradient(
                colors: [Color(hex: "34C759"), Color(hex: "5AC8FA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .system:
            return LinearGradient(
                colors: [Color(hex: "8E8E93"), Color(hex: "636366")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .success:
            return LinearGradient(
                colors: [Color(hex: "34C759"), Color(hex: "30D158")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .warning:
            return LinearGradient(
                colors: [Color(hex: "FF9500"), Color(hex: "FFCC00")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .error:
            return LinearGradient(
                colors: [Color(hex: "FF3B30"), Color(hex: "FF6B6B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .info:
            return LinearGradient(
                colors: [Color(hex: "007AFF"), Color(hex: "5AC8FA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .accent:
            return LinearGradient(
                colors: [.accentColor, .accentColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var primaryColor: Color {
        switch self {
        case .recording, .recordingStop, .error:
            return Color(hex: "FF3B30")
        case .audio, .info:
            return Color(hex: "007AFF")
        case .analysis:
            return Color(hex: "AF52DE")
        case .people, .success:
            return Color(hex: "34C759")
        case .system:
            return Color(hex: "8E8E93")
        case .warning:
            return Color(hex: "FF9500")
        case .accent:
            return .accentColor
        }
    }
    
    var backgroundOpacity: Double {
        0.15
    }
}

// MARK: - Styled Icon Component

struct StyledIcon: View {
    let systemName: String
    let theme: IconColorTheme
    let size: IconSize
    let hasBackground: Bool
    let isAnimating: Bool
    
    init(
        _ systemName: String,
        theme: IconColorTheme = .accent,
        size: IconSize = .medium,
        hasBackground: Bool = true,
        isAnimating: Bool = false
    ) {
        self.systemName = systemName
        self.theme = theme
        self.size = size
        self.hasBackground = hasBackground
        self.isAnimating = isAnimating
    }
    
    var body: some View {
        ZStack {
            if hasBackground {
                backgroundShape
            }
            
            Image(systemName: systemName)
                .font(.system(size: iconFontSize, weight: iconWeight))
                .foregroundStyle(theme.gradient)
                .symbolRenderingMode(.multicolor)
                .overlay(
                    Image(systemName: systemName)
                        .font(.system(size: iconFontSize, weight: iconWeight))
                        .foregroundStyle(.white.opacity(0.3))
                        .offset(x: 0.5, y: 0.5)
                        .blur(radius: 0.5)
                )
        }
        .frame(width: size.dimension, height: size.dimension)
    }
    
    @ViewBuilder
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: backgroundCornerRadius)
            .fill(theme.primaryColor.opacity(theme.backgroundOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: backgroundCornerRadius)
                    .stroke(theme.primaryColor.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var iconFontSize: CGFloat {
        switch size {
        case .small: return 10
        case .medium: return 14
        case .large: return 20
        case .extraLarge: return 28
        }
    }
    
    private var iconWeight: Font.Weight {
        switch size {
        case .small: return .medium
        case .medium: return .semibold
        case .large, .extraLarge: return .bold
        }
    }
    
    private var backgroundCornerRadius: CGFloat {
        switch size {
        case .small: return 4
        case .medium: return 6
        case .large: return 8
        case .extraLarge: return 10
        }
    }
}

// MARK: - Recording Pulse Icon

struct RecordingPulseIcon: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Outer pulse rings
            ForEach(0..<3) { index in
                Circle()
                    .stroke(Color.red.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                    .frame(width: 20 + CGFloat(index) * 10, height: 20 + CGFloat(index) * 10)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: false)
                        .delay(Double(index) * 0.3),
                        value: isAnimating
                    )
            }
            
            // Center recording icon
            StyledIcon(
                "record.circle.fill",
                theme: .recordingStop,
                size: .large,
                hasBackground: false
            )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Waveform Animation Icon

struct WaveformIcon: View {
    @State private var phase = 0.0
    let isAnimating: Bool
    
    var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 2
            let totalBars = 5
            let totalWidth = CGFloat(totalBars) * barWidth + CGFloat(totalBars - 1) * spacing
            let startX = (size.width - totalWidth) / 2
            
            for i in 0..<totalBars {
                let x = startX + CGFloat(i) * (barWidth + spacing)
                let normalizedIndex = Double(i) / Double(totalBars - 1)
                let waveOffset = normalizedIndex * .pi
                let heightMultiplier = isAnimating 
                    ? (sin(phase + waveOffset) + 1) / 2 
                    : 0.5
                let barHeight = size.height * 0.3 + (size.height * 0.4 * heightMultiplier)
                let y = (size.height - barHeight) / 2
                
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                
                context.fill(path, with: .color(.accentColor))
            }
        }
        .frame(width: 24, height: 24)
        .onAppear {
            if isAnimating {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: true)) {
                    phase = .pi * 2
                }
            }
        }
    }
}

// MARK: - Session Type Icon

struct SessionTypeIcon: View {
    let sessionType: SessionType
    let size: IconSize
    
    enum SessionType {
        case standup
        case client
        case sprint
        case planning
        case review
        case general
        
        var icon: String {
            switch self {
            case .standup: return "person.3"
            case .client: return "briefcase"
            case .sprint: return "arrow.forward.circle"
            case .planning: return "calendar"
            case .review: return "checkmark.circle"
            case .general: return "waveform"
            }
        }
        
        var theme: IconColorTheme {
            switch self {
            case .standup: return .people
            case .client: return .analysis
            case .sprint: return .success
            case .planning: return .info
            case .review: return .accent
            case .general: return .system
            }
        }
    }
    
    var body: some View {
        StyledIcon(
            sessionType.icon,
            theme: sessionType.theme,
            size: size
        )
    }
}

// MARK: - Status Icon

struct StatusIcon: View {
    let status: RecordingState
    let size: IconSize
    
    var body: some View {
        switch status {
        case .idle:
            StyledIcon("waveform", theme: .system, size: size)
        case .recording:
            RecordingPulseIcon()
        case .paused:
            StyledIcon("pause.circle.fill", theme: .warning, size: size)
        case .error:
            StyledIcon("exclamationmark.triangle.fill", theme: .error, size: size)
        }
    }
}

// MARK: - Audio Source Icon

struct AudioSourceIcon: View {
    let source: AudioSource
    let size: IconSize
    
    var body: some View {
        switch source {
        case .systemAndMic:
            StyledIcon("speaker.wave.2.fill", theme: .audio, size: size)
        case .systemOnly:
            StyledIcon("speaker.wave.3.fill", theme: .audio, size: size)
        case .micOnly:
            StyledIcon("mic.fill", theme: .people, size: size)
        }
    }
}

// MARK: - Highlight Type Icon

struct HighlightTypeIcon: View {
    let type: Highlight.HighlightType
    let size: IconSize
    
    var body: some View {
        switch type {
        case .action:
            StyledIcon("checkmark.circle", theme: .success, size: size)
        case .decision:
            StyledIcon("arrow.decision", theme: .analysis, size: size)
        case .risk:
            StyledIcon("exclamationmark.triangle", theme: .warning, size: size)
        case .keyPoint:
            StyledIcon("star", theme: .accent, size: size)
        }
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

struct StyledIcon_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                StyledIcon("record.circle", theme: .recording, size: .extraLarge)
                StyledIcon("waveform", theme: .audio, size: .extraLarge)
                StyledIcon("person.3", theme: .people, size: .extraLarge)
                StyledIcon("brain", theme: .analysis, size: .extraLarge)
            }
            
            HStack(spacing: 20) {
                StyledIcon("checkmark.circle", theme: .success, size: .large)
                StyledIcon("exclamationmark.triangle", theme: .warning, size: .large)
                StyledIcon("xmark.circle", theme: .error, size: .large)
                StyledIcon("info.circle", theme: .info, size: .large)
            }
            
            HStack(spacing: 20) {
                StyledIcon("mic", theme: .people, size: .medium)
                StyledIcon("speaker.wave.2", theme: .audio, size: .medium)
                StyledIcon("gearshape", theme: .system, size: .medium)
                StyledIcon("square.and.arrow.up", theme: .accent, size: .medium)
            }
            
            RecordingPulseIcon()
        }
        .padding()
    }
}
