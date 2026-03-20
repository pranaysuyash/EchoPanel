import SwiftUI

// MARK: - Loading State View (Skeleton Cards)

struct LoadingStateView: View {
    let type: LoadingType
    
    enum LoadingType {
        case transcript
        case highlights
        case people
        case session
    }
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            switch type {
            case .transcript:
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonTranscriptCard()
                }
            case .highlights:
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonHighlightCard()
                }
            case .people:
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonPersonCard()
                }
            case .session:
                SkeletonSessionCard()
            }
        }
        .padding()
    }
}

struct SkeletonTranscriptCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SkeletonBox(width: 100, height: 14)
                Spacer()
                SkeletonBox(width: 50, height: 12)
            }
            
            SkeletonBox(width: nil, height: 16)
            SkeletonBox(width: nil, height: 16)
            SkeletonBox(width: 200, height: 16)
            
            HStack {
                Spacer()
                SkeletonBox(width: 60, height: 12)
            }
        }
        .padding()
        .background(AppMaterial.cardBackground)
        .cornerRadius(CornerRadius.md)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
    }
}

struct SkeletonHighlightCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            SkeletonBox(width: 24, height: 24)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SkeletonBox(width: nil, height: 16)
                SkeletonBox(width: 80, height: 12)
            }
            
            Spacer()
        }
        .padding()
        .background(AppMaterial.cardBackground)
        .cornerRadius(CornerRadius.md)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
    }
}

struct SkeletonPersonCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonBox(width: 120, height: 14)
                SkeletonBox(width: 80, height: 12)
            }
            
            Spacer()
        }
        .padding()
        .background(AppMaterial.cardBackground)
        .cornerRadius(CornerRadius.md)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
    }
}

struct SkeletonSessionCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonBox(width: 180, height: 16)
                SkeletonBox(width: 120, height: 12)
            }
            
            Spacer()
        }
        .padding(.vertical, Spacing.sm)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
    }
}

struct SkeletonBox: View {
    let width: CGFloat?
    let height: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.xs)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: width, height: height)
    }
}

// MARK: - Streaming Transcript View (Live Loading)

struct StreamingTranscriptView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isAnimatingDots = false
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            ForEach(appState.liveTranscript) { item in
                TranscriptCard(item: item)
            }
            
            // Live indicator
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.statusSuccess)
                    .frame(width: 8, height: 8)
                
                Text("Listening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Animated dots
                Text(dots)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isAnimatingDots = true
                }
            }
        }
        .padding()
    }
    
    private var dots: String {
        isAnimatingDots ? "..." : "   "
    }
}

// MARK: - Long Transcript Demo View

struct LongTranscriptDemoView: View {
    let transcript: [TranscriptItem]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(transcript) { item in
                    TranscriptCard(item: item)
                }
            }
            .padding()
        }
    }
}

// MARK: - Progress Loading View

struct ProgressLoadingView: View {
    let message: String
    let progress: Double?
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            if let progress = progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
            }
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Retry Loading View

struct RetryLoadingView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: Spacing.sm) {
                Text("Loading...")
                    .font(.headline)
                
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
