//
//  OnboardingView.swift
//  Mobile Terminal
//
//  First launch onboarding flow
//

import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var serverManager: ServerManager

    @State private var currentPage = 0
    @State private var showingAddServer = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage
                    .tag(0)

                featuresPage
                    .tag(1)

                getStartedPage
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Bottom buttons
            bottomButtons
                .padding()
                .background(Color(UIColor.systemBackground))
        }
        .sheet(isPresented: $showingAddServer) {
            ServerEditView(mode: .add)
                .interactiveDismissDisabled()
        }
        .onChange(of: serverManager.servers.count) { _, newCount in
            if newCount > 0 {
                showingAddServer = false
                hasCompletedOnboarding = true
            }
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Mobile Terminal")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Use CLI on your Phone")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Connect to your remote servers from anywhere using your iPhone")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Features Page

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Features")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 24) {
                FeatureRow(
                    icon: "server.rack",
                    title: "Multiple Servers",
                    description: "Save and manage all your server connections"
                )

                FeatureRow(
                    icon: "faceid",
                    title: "Secure Access",
                    description: "Use Face ID or Touch ID for quick, secure connections"
                )

                FeatureRow(
                    icon: "hand.tap",
                    title: "Touch Optimized",
                    description: "Gestures and toolbar designed for mobile use"
                )

                FeatureRow(
                    icon: "mic",
                    title: "Voice Commands",
                    description: "Speak commands instead of typing"
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Get Started Page

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "plus.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Add Your First Server")
                .font(.title)
                .fontWeight(.bold)

            Text("Connect to a ttyd server running on your remote machine")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Text("You'll need:")
                    .font(.headline)

                BulletPoint(text: "Server hostname or IP address")
                BulletPoint(text: "ttyd port (default: 7681)")
                BulletPoint(text: "Authentication token (if configured)")
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack {
            if currentPage > 0 {
                Button("Back") {
                    withAnimation {
                        currentPage -= 1
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentPage < 2 {
                Button("Next") {
                    withAnimation {
                        currentPage += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Add Server") {
                    showingAddServer = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Bullet Point

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(ServerManager.shared)
}
