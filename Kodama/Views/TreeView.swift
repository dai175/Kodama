//
//  TreeView.swift
//  Kodama
//
//  Created by Daisuke Ooba on 2026/04/02.
//

import SceneKit
import SwiftData
import SwiftUI

// MARK: - TreeView

struct TreeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = TreeViewModel()
    @State private var bonsaiScene = BonsaiScene()
    @State private var renderer: BonsaiRenderer?
    @State private var isLoading = true
    @State private var scnViewRef: SCNView?
    @State private var overlay = InteractionOverlayState()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            SceneViewRepresentable(
                bonsaiScene: bonsaiScene,
                onSCNViewCreated: { scnView in DispatchQueue.main.async { scnViewRef = scnView } },
                onTreeTapped: { point, scnView in
                    handleTreeTap(at: point, in: scnView)
                }
            )
            .ignoresSafeArea()
            .opacity(isLoading ? 0 : 1)

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                InteractionOverlay(
                    viewModel: viewModel,
                    bonsaiScene: bonsaiScene,
                    scnView: scnViewRef,
                    overlayState: overlay,
                    onSettingsTapped: { showSettings = true }
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView {
                handleTreeReset()
            }
        }
        .onAppear {
            guard isLoading else { return }

            let bonsaiRenderer = BonsaiRenderer(bonsaiScene: bonsaiScene)
            renderer = bonsaiRenderer

            Task {
                viewModel.loadOrCreateTree(context: modelContext)
                bonsaiRenderer.renderTree(from: viewModel.blocks)
                viewModel.evaluateGrowth(context: modelContext, renderer: bonsaiRenderer)
                isLoading = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let bonsaiRenderer = renderer else { return }
            Task {
                viewModel.evaluateGrowth(context: modelContext, renderer: bonsaiRenderer)
            }
        }
    }

    private func handleTreeReset() {
        viewModel.resetTree(context: modelContext)
        if let bonsaiRenderer = renderer {
            bonsaiRenderer.renderTree(from: viewModel.blocks)
            viewModel.evaluateGrowth(context: modelContext, renderer: bonsaiRenderer)
        }
    }

    private func handleTreeTap(at point: CGPoint, in scnView: SCNView) {
        guard let hitPosition = InteractionHandler.handleTouch(
            at: point, in: scnView, scene: bonsaiScene
        ) else { return }

        viewModel.handleTouch(position: hitPosition, context: modelContext)
        overlay.showPalette(touchPosition: hitPosition, screenPoint: point)
    }
}

// MARK: - SceneViewRepresentable

struct SceneViewRepresentable: UIViewRepresentable {
    let bonsaiScene: BonsaiScene
    var onSCNViewCreated: ((SCNView) -> Void)?
    var onTreeTapped: ((CGPoint, SCNView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(bonsaiScene: bonsaiScene, onTreeTapped: onTreeTapped)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = bonsaiScene.scene
        scnView.pointOfView = bonsaiScene.cameraNode
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor.darkForest
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.maximumVerticalAngle = 60
        scnView.defaultCameraController.inertiaEnabled = true

        // Single tap for tree interaction
        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        scnView.addGestureRecognizer(singleTap)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scnView.addGestureRecognizer(doubleTap)

        // Single tap should wait for double-tap to fail
        singleTap.require(toFail: doubleTap)

        let touchRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleInteraction(_:))
        )
        touchRecognizer.maximumNumberOfTouches = 10
        touchRecognizer.delegate = context.coordinator
        scnView.addGestureRecognizer(touchRecognizer)

        let pinchRecognizer = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleInteraction(_:))
        )
        pinchRecognizer.delegate = context.coordinator
        scnView.addGestureRecognizer(pinchRecognizer)

        context.coordinator.scnView = scnView
        onSCNViewCreated?(scnView)

        return scnView
    }

    func updateUIView(_: SCNView, context: Context) {
        context.coordinator.onTreeTapped = onTreeTapped
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let bonsaiScene: BonsaiScene
        var onTreeTapped: ((CGPoint, SCNView) -> Void)?
        weak var scnView: SCNView?

        init(bonsaiScene: BonsaiScene, onTreeTapped: ((CGPoint, SCNView) -> Void)?) {
            self.bonsaiScene = bonsaiScene
            self.onTreeTapped = onTreeTapped
        }

        // MARK: - Gesture Handling

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let scnView else { return }
            let point = gesture.location(in: scnView)
            onTreeTapped?(point, scnView)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let scnView else { return }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5

            scnView.pointOfView = bonsaiScene.cameraNode
            bonsaiScene.cameraNode.position = SCNVector3(0, 5, 12)

            SCNTransaction.commit()

            bonsaiScene.stopAutoRotation()
            bonsaiScene.scheduleAutoRotationResume()
        }

        @objc func handleInteraction(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began:
                bonsaiScene.stopAutoRotation()
            case .ended, .cancelled:
                bonsaiScene.scheduleAutoRotationResume()
            default:
                break
            }
        }

        /// Allow simultaneous recognition so SCNView's built-in gestures still work
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

#Preview {
    TreeView()
        .modelContainer(for: [BonsaiTree.self, VoxelBlock.self, Interaction.self], inMemory: true)
}
