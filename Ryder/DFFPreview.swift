//
//  DFFPreview.swift
//  Ryder
//
//  Created by Alex Marcelle on 07/10/26.
//

import SceneKit
import SwiftUI

struct DFFPreview: NSViewRepresentable {
    let scene: SCNScene

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .windowBackgroundColor
        view.antialiasingMode = .multisampling4X
        view.scene = scene
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.scene = scene
    }
}

enum DFFSceneBuilder {
    static func scene(containing model: SCNNode) -> SCNScene {
        let scene = SCNScene()
        scene.rootNode.addChildNode(model)

        let bounds = model.boundingBox
        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        let width = bounds.max.x - bounds.min.x
        let height = bounds.max.y - bounds.min.y
        let depth = bounds.max.z - bounds.min.z
        let extent = max(width, height, depth, 0.1)

        let camera = SCNCamera()
        camera.zNear = Double(max(extent / 1_000, 0.001))
        camera.zFar = Double(max(extent * 100, 100))

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(
            center.x + extent * 1.5,
            center.y + extent,
            center.z + extent * 1.5
        )
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 1_000

        let keyLightNode = SCNNode()
        keyLightNode.light = keyLight
        keyLightNode.eulerAngles = SCNVector3(-0.8, 0.7, 0)
        scene.rootNode.addChildNode(keyLightNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 400
        ambientLight.color = NSColor(white: 0.7, alpha: 1)

        let ambientLightNode = SCNNode()
        ambientLightNode.light = ambientLight
        scene.rootNode.addChildNode(ambientLightNode)

        return scene
    }
}
