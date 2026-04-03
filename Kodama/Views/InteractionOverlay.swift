//
//  InteractionOverlay.swift
//  Kodama
//

import SceneKit
import SwiftData
import SwiftUI

// MARK: - InteractionOverlayState

@Observable
final class InteractionOverlayState {
    var interactionState: InteractionPhase = .idle
    var lastTouchPosition: SCNVector3?
    var lastTouchScreenPoint: CGPoint?

    func showPalette(touchPosition: SCNVector3, screenPoint: CGPoint) {
        lastTouchPosition = touchPosition
        lastTouchScreenPoint = screenPoint
        interactionState = .palette
    }

    func reset() {
        interactionState = .idle
        lastTouchPosition = nil
        lastTouchScreenPoint = nil
    }
}

// MARK: - InteractionPhase

enum InteractionPhase {
    case idle
    case palette
    case wordInput
}

// MARK: - InteractionOverlay

struct InteractionOverlay: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: TreeViewModel
    let bonsaiScene: BonsaiScene
    var scnView: SCNView?
    var overlayState: InteractionOverlayState
    var onSettingsTapped: () -> Void = {}

    @State private var autoHideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Settings gear (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: onSettingsTapped) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.softWhite)
                            .opacity(0.5)
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                }
                Spacer()
            }

            // Palette (bottom)
            VStack {
                Spacer()
                if overlayState.interactionState == .palette {
                    ColorPaletteView { hex in
                        handleColorSelected(hex)
                    }
                    .transition(.opacity)
                    .padding(.bottom, 60)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: overlayState.interactionState == .palette)

            // Word input (center-bottom)
            VStack {
                Spacer()
                if overlayState.interactionState == .wordInput {
                    WordInputView { text in
                        handleWordSubmitted(text)
                    }
                    .transition(.opacity)
                    .padding(.bottom, 120)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: overlayState.interactionState == .wordInput)
        }
        .onChange(of: overlayState.interactionState) {
            if overlayState.interactionState != .idle {
                scheduleAutoHide()
            }
        }
    }

    // MARK: - Color Selection

    private func handleColorSelected(_ hex: String) {
        viewModel.handleColor(hex: hex, context: modelContext)

        if let scnView, let screenPoint = overlayState.lastTouchScreenPoint {
            let target = overlayState.lastTouchPosition ?? SCNVector3(0, 4, 0)
            let uiColor = UIColor(hex: hex)
            InteractionHandler.createParticleFlow(
                from: screenPoint,
                color: uiColor,
                in: scnView,
                toward: target
            )
        }

        overlayState.interactionState = .wordInput
        scheduleAutoHide()
    }

    // MARK: - Word Submission

    private func handleWordSubmitted(_ text: String) {
        viewModel.handleWord(text: text, context: modelContext)

        if let scnView, let screenPoint = overlayState.lastTouchScreenPoint {
            let target = overlayState.lastTouchPosition ?? SCNVector3(0, 4, 0)
            InteractionHandler.createWordDissolve(
                text: text,
                from: screenPoint,
                in: scnView,
                toward: target
            )
        }

        autoHideTask?.cancel()
        overlayState.reset()
    }

    // MARK: - Auto-Hide Timer

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            overlayState.reset()
        }
    }
}
