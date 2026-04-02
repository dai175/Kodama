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
    @State private var viewModel = TreeViewModel()
    @State private var bonsaiScene = BonsaiScene()
    @State private var renderer: BonsaiRenderer?
    @State private var hasLoaded = false

    var body: some View {
        SceneViewRepresentable(bonsaiScene: bonsaiScene)
            .ignoresSafeArea()
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true

                let bonsaiRenderer = BonsaiRenderer(bonsaiScene: bonsaiScene)
                renderer = bonsaiRenderer

                viewModel.loadOrCreateTree(context: modelContext)
                bonsaiRenderer.renderTree(from: viewModel.blocks)
                viewModel.evaluateGrowth(context: modelContext, renderer: bonsaiRenderer)
            }
    }
}

// MARK: - SceneViewRepresentable

struct SceneViewRepresentable: UIViewRepresentable {
    let bonsaiScene: BonsaiScene

    func makeCoordinator() -> Coordinator {
        Coordinator(bonsaiScene: bonsaiScene)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = bonsaiScene.scene
        scnView.pointOfView = bonsaiScene.cameraNode
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(red: 10 / 255, green: 26 / 255, blue: 18 / 255, alpha: 1)
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.maximumVerticalAngle = 60
        scnView.defaultCameraController.inertiaEnabled = true

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scnView.addGestureRecognizer(doubleTap)

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

        return scnView
    }

    func updateUIView(_: SCNView, context _: Context) {
        // No dynamic updates needed yet
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let bonsaiScene: BonsaiScene
        weak var scnView: SCNView?

        init(bonsaiScene: BonsaiScene) {
            self.bonsaiScene = bonsaiScene
        }

        // MARK: - Gesture Handling

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
}
