import SwiftUI

// MARK: - Specialized Empty State Views

// NOTE: Base EmptyStateView is defined in DesignTokens.swift

// MARK: - Empty Sessions View

struct EmptySessionsView: View {
    @Binding var showOnboarding: Bool
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "waveform")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.accentColor)
            }
            
            VStack(spacing: Spacing.sm) {
                Text("No Sessions Yet")
                    .font(.title2.weight(.semibold))
                
                Text("Start your first recording to capture meeting transcripts, highlights, and insights.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            
            VStack(spacing: Spacing.md) {
                Button(action: { /* Start recording */ }) {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: { showOnboarding = true }) {
                    Text("View Onboarding")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty Search Results

struct EmptySearchResultsView: View {
    let query: String
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: Spacing.sm) {
                Text("No Results")
                    .font(.headline)
                
                Text("No sessions found matching \"\(query)\"")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - No Highlights View

struct NoHighlightsView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: Spacing.sm) {
                Text("No Highlights Yet")
                    .font(.headline)
                
                Text("Highlights and decisions will appear here as your meeting progresses.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - No Participants View

struct NoParticipantsView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: Spacing.sm) {
                Text("No Participants Detected")
                    .font(.headline)
                
                Text("Participants will appear here as they're identified from the conversation.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Coming Soon View

struct ComingSoonView: View {
    let feature: String
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            VStack(spacing: Spacing.sm) {
                Text("Coming Soon")
                    .font(.headline)
                
                Text("\(feature) will be available in a future update.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
