import SwiftUI
import SceneKit

/// Displays the room USDZ with colored heatmap regions for hypothesis locations.
/// Currently loads the base USDZ and highlights hypothesis positions with colored spheres.
/// Future: CustomMaterial with Metal shader for mesh-based coloring.
struct RoomHeatmapView: View {
    let roomID: UUID
    let hypotheses: [ObjectHypothesis]
    let selectedID: UUID?

    var body: some View {
        SceneKitHeatmapRepresentable(
            roomID: roomID,
            hypotheses: hypotheses,
            selectedID: selectedID
        )
    }
}

private struct SceneKitHeatmapRepresentable: UIViewRepresentable {
    let roomID: UUID
    let hypotheses: [ObjectHypothesis]
    let selectedID: UUID?

    private static let heatmapGroupName = "heatmapNodes"

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        let persistence = RoomPersistenceService()
        let url = persistence.usdzURL(for: roomID)
        if let scene = try? SCNScene(url: url, options: [.checkConsistency: true]) {
            scnView.scene = scene
            addHeatmapNodes(to: scene.rootNode)
        } else {
            scnView.scene = SCNScene()
            scnView.scene?.background.contents = UIColor.black
        }

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let rootNode = scnView.scene?.rootNode else { return }

        // Remove old heatmap nodes and rebuild
        rootNode.childNode(withName: Self.heatmapGroupName, recursively: false)?.removeFromParentNode()
        addHeatmapNodes(to: rootNode)
    }

    private func addHeatmapNodes(to rootNode: SCNNode) {
        let group = SCNNode()
        group.name = Self.heatmapGroupName

        for hypothesis in hypotheses {
            guard let transformData = hypothesis.transformData,
                  let transform = simd_float4x4.fromData(transformData) else { continue }

            let isSelected = hypothesis.id == selectedID
            let radius: CGFloat = isSelected ? 0.15 : 0.1

            // Heatmap sphere with transparency
            let sphere = SCNSphere(radius: radius)
            let material = SCNMaterial()
            material.diffuse.contents = heatmapColor(for: hypothesis, isSelected: isSelected)
            material.transparency = isSelected ? 0.5 : 0.3
            material.lightingModel = .constant
            material.isDoubleSided = true
            sphere.firstMaterial = material

            let node = SCNNode(geometry: sphere)
            node.name = hypothesis.id.uuidString
            node.position = SCNVector3(transform.columns.3.x,
                                       transform.columns.3.y,
                                       transform.columns.3.z)
            group.addChildNode(node)
        }

        rootNode.addChildNode(group)
    }

    private func heatmapColor(for hypothesis: ObjectHypothesis, isSelected: Bool) -> UIColor {
        let alpha: CGFloat = isSelected ? 0.8 : 0.5
        switch hypothesis.hypothesisType {
        case .cooperative:
            return UIColor(Color.signalMagenta).withAlphaComponent(alpha)
        case .tagged:
            return UIColor(Color.spatialCyan).withAlphaComponent(alpha)
        case .inferred:
            return UIColor(Color.inferenceViolet).withAlphaComponent(alpha)
        }
    }
}
