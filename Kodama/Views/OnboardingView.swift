//
//  OnboardingView.swift
//  Kodama
//

import SceneKit
import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 10 / 255, green: 26 / 255, blue: 18 / 255),
                    Color(red: 13 / 255, green: 40 / 255, blue: 24 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            TabView(selection: $currentPage) {
                onboardingPage(
                    title: "This is your tree. It's alive.",
                    subtitle: "A small sapling, waiting to grow.",
                    showButton: false
                )
                .tag(0)

                onboardingPage(
                    title: "It grows on its own.\nTouch it, and it grows with you.",
                    subtitle: "Give it color, give it words.",
                    showButton: false
                )
                .tag(1)

                onboardingPage(
                    title: "There's nothing to do.\nJust be here.",
                    subtitle: nil,
                    showButton: true
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }

    private func onboardingPage(title: String, subtitle: String?, showButton: Bool) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top 2/3: Mini SceneKit view
                OnboardingSaplingView()
                    .frame(maxWidth: .infinity)
                    .frame(height: geometry.size.height * 0.55)
                    .clipped()

                Spacer()
                    .frame(height: 24)

                // Bottom 1/3: Text content
                VStack(spacing: 16) {
                    Text(title)
                        .font(.system(size: 20, weight: .light, design: .default))
                        .foregroundStyle(Color.softWhite.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .light, design: .default))
                            .foregroundStyle(Color.softWhite.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }

                    if showButton {
                        Button {
                            withAnimation(.easeInOut(duration: 1.0)) {
                                appState.hasCompletedOnboarding = true
                            }
                        } label: {
                            Text("Begin")
                                .font(.system(size: 18, weight: .light, design: .default))
                                .foregroundStyle(Color.softWhite.opacity(0.9))
                                .padding(.horizontal, 48)
                                .padding(.vertical, 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(Color.softWhite.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
        }
    }
}

// MARK: - OnboardingSaplingView

private struct OnboardingSaplingView: UIViewRepresentable {
    func makeUIView(context _: Context) -> SCNView {
        let scnView = SCNView()
        let bonsaiScene = BonsaiScene()

        // Build a small static sapling
        let saplingBlocks = TreeBuilder.buildSapling(seed: 42)
        let renderer = BonsaiRenderer(bonsaiScene: bonsaiScene)
        renderer.renderTree(from: saplingBlocks)

        scnView.scene = bonsaiScene.scene
        scnView.pointOfView = bonsaiScene.cameraNode
        scnView.preferredFramesPerSecond = 30
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.isUserInteractionEnabled = false

        return scnView
    }

    func updateUIView(_: SCNView, context _: Context) {}
}
