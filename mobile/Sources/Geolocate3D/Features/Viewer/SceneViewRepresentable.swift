import SwiftUI
import SceneKit
import simd
import Foundation
import UIKit

struct SceneViewRepresentable: UIViewRepresentable {
    let roomID: UUID
    let observations: [ObjectObservation]
    let hypotheses: [ObjectHypothesis]
    let showScaffold: Bool
    let showObjects: Bool
    let showHeatmap: Bool
    let showDense: Bool
    let denseAssetURL: URL?
    let semanticObjects: [SemanticSceneObject]
    let semanticMeshLocalURLs: [String: URL]
    let selectedSemanticObjectID: String?
    let showSemanticObjects: Bool
    let viewerMode: ViewerMode
    let onSemanticObjectTapped: ((String) -> Void)?
    /// Binding updated each frame with projected 2D positions for SwiftUI annotation overlay.
    @Binding var projectedPositions: [UUID: CGPoint]

    private static let scaffoldGroupName = "scaffoldContent"
    private static let observationGroupName = "observationPins"
    private static let heatmapGroupName = "heatmapNodes"
    private static let denseGroupName = "densePoints"
    private static let semanticGroupName = "semanticObjectGroup"
    private static let maxDensePointCount = 8_000
    private static let maxRenderableSemanticObjects = 10
    private static let semanticMarkerExtent = SIMD3<Float>(repeating: 0.14)
    private static let semanticMarkerHeight: Float = 0.06

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = UIColor(Color.spaceBlack)
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        let scene = loadBaseScene()
        scnView.scene = scene
        rebuildDynamicContent(in: scene.rootNode)
        context.coordinator.cacheSnapshot(
            observations: observations,
            hypotheses: hypotheses,
            showDense: showDense,
            denseAssetURL: denseAssetURL,
            semanticObjects: semanticObjects,
            selectedSemanticObjectID: selectedSemanticObjectID,
            showSemanticObjects: showSemanticObjects,
            viewerMode: viewerMode
        )
        updateVisibility(in: scene.rootNode)

        context.coordinator.scnView = scnView
        context.coordinator.observations = observations
        context.coordinator.projectedPositions = $projectedPositions
        context.coordinator.showObjects = showObjects
        context.coordinator.onSemanticObjectTapped = onSemanticObjectTapped
        startProjectionTimer(context: context)

        // Add tap gesture for semantic object selection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let rootNode = scnView.scene?.rootNode else { return }
        if context.coordinator.needsRebuild(
            observations: observations,
            hypotheses: hypotheses,
            showDense: showDense,
            denseAssetURL: denseAssetURL,
            semanticObjects: semanticObjects,
            selectedSemanticObjectID: selectedSemanticObjectID,
            showSemanticObjects: showSemanticObjects,
            viewerMode: viewerMode
        ) {
            rebuildDynamicContent(in: rootNode)
            context.coordinator.cacheSnapshot(
                observations: observations,
                hypotheses: hypotheses,
                showDense: showDense,
                denseAssetURL: denseAssetURL,
                semanticObjects: semanticObjects,
                selectedSemanticObjectID: selectedSemanticObjectID,
                showSemanticObjects: showSemanticObjects,
                viewerMode: viewerMode
            )
        }
        updateVisibility(in: rootNode)
        context.coordinator.observations = observations
        context.coordinator.showObjects = showObjects
        context.coordinator.onSemanticObjectTapped = onSemanticObjectTapped
    }

    private func loadBaseScene() -> SCNScene {
        let persistence = RoomPersistenceService()
        let url = persistence.usdzURL(for: roomID)

        let scene = (try? SCNScene(url: url, options: [.checkConsistency: true])) ?? SCNScene()
        let scaffoldGroup = SCNNode()
        scaffoldGroup.name = Self.scaffoldGroupName

        while let child = scene.rootNode.childNodes.first {
            child.removeFromParentNode()
            scaffoldGroup.addChildNode(child)
        }
        scene.rootNode.addChildNode(scaffoldGroup)
        return scene
    }

    private func rebuildDynamicContent(in rootNode: SCNNode) {
        rootNode.childNode(withName: Self.observationGroupName, recursively: false)?.removeFromParentNode()
        rootNode.childNode(withName: Self.heatmapGroupName, recursively: false)?.removeFromParentNode()
        rootNode.childNode(withName: Self.denseGroupName, recursively: false)?.removeFromParentNode()
        rootNode.childNode(withName: Self.semanticGroupName, recursively: false)?.removeFromParentNode()

        addObservationPins(to: rootNode)
        addHeatmapNodes(to: rootNode)
        addDenseNodes(to: rootNode)
        addSemanticObjectNodes(to: rootNode)

        // When semantic objects are loaded, reduce scaffold to ghost shell
        if !semanticObjects.isEmpty && showSemanticObjects {
            applyGhostShellToScaffold(in: rootNode)
        } else {
            restoreScaffoldMaterials(in: rootNode)
        }
    }

    private func updateVisibility(in rootNode: SCNNode) {
        rootNode.childNode(withName: Self.scaffoldGroupName, recursively: false)?.isHidden = !showScaffold
        rootNode.childNode(withName: Self.observationGroupName, recursively: false)?.isHidden = !showObjects
        rootNode.childNode(withName: Self.heatmapGroupName, recursively: false)?.isHidden = !showHeatmap
        rootNode.childNode(withName: Self.denseGroupName, recursively: false)?.isHidden = !showDense
        rootNode.childNode(withName: Self.semanticGroupName, recursively: false)?.isHidden = !showSemanticObjects
    }

    // MARK: - Ghost Shell for Scaffold

    private func applyGhostShellToScaffold(in rootNode: SCNNode) {
        guard let scaffoldGroup = rootNode.childNode(withName: Self.scaffoldGroupName, recursively: false) else { return }
        applyGhostMaterialRecursively(to: scaffoldGroup)
    }

    private func applyGhostMaterialRecursively(to node: SCNNode) {
        if let geometry = node.geometry {
            let ghostMaterial = SCNMaterial()
            ghostMaterial.diffuse.contents = UIColor(white: 0.82, alpha: 0.46)
            ghostMaterial.emission.contents = UIColor(white: 0.58, alpha: 0.18)
            ghostMaterial.lightingModel = .lambert
            ghostMaterial.isDoubleSided = true
            ghostMaterial.transparency = 0.46
            ghostMaterial.writesToDepthBuffer = true
            ghostMaterial.readsFromDepthBuffer = true
            geometry.materials = [ghostMaterial]
        }
        for child in node.childNodes {
            applyGhostMaterialRecursively(to: child)
        }
    }

    private func restoreScaffoldMaterials(in rootNode: SCNNode) {
        // No-op: scaffold loaded from USDZ retains its original materials
        // when no semantic objects are present.
    }

    // MARK: - Semantic Object Nodes

    private func addSemanticObjectNodes(to rootNode: SCNNode) {
        let group = SCNNode()
        group.name = Self.semanticGroupName

        for obj in cappedRenderableSemanticObjects() {
            let objectNode = makeSemanticBoundingNode(for: obj, in: rootNode)

            // Selection highlight
            if obj.id == selectedSemanticObjectID {
                applySelectionHighlight(to: objectNode)
            }

            group.addChildNode(objectNode)
        }

        rootNode.addChildNode(group)
    }

    private func cappedRenderableSemanticObjects() -> [SemanticSceneObject] {
        let filtered = semanticObjects.filter { obj in
            guard isRenderableSemanticObject(obj) else { return false }
            return obj.confidence >= 0.22 || obj.id == selectedSemanticObjectID
        }
        let sorted = filtered.sorted(by: { lhs, rhs in
            if lhs.id == selectedSemanticObjectID { return true }
            if rhs.id == selectedSemanticObjectID { return false }
            if lhs.confidence == rhs.confidence {
                return lhs.id < rhs.id
            }
            return lhs.confidence > rhs.confidence
        })
        guard sorted.count > Self.maxRenderableSemanticObjects else {
            return sorted
        }
        if let selectedID = selectedSemanticObjectID,
           let selected = sorted.first(where: { $0.id == selectedID })
        {
            let others = sorted.filter { $0.id != selectedID }
            return [selected] + Array(others.prefix(max(0, Self.maxRenderableSemanticObjects - 1)))
        }
        return Array(sorted.prefix(Self.maxRenderableSemanticObjects))
    }

    private func makeSemanticBoundingNode(for obj: SemanticSceneObject, in rootNode: SCNNode) -> SCNNode {
        let extent = semanticDisplayExtent(for: obj)
        let box = SCNBox(
            width: CGFloat(extent.x),
            height: CGFloat(extent.y),
            length: CGFloat(extent.z),
            chamferRadius: CGFloat(min(extent.x, extent.z) * 0.06)
        )
        let fillMaterial = categoryTintedMaterial(for: obj)
        fillMaterial.transparency = 0.72
        box.materials = [fillMaterial]

        let node = SCNNode()
        node.name = "semantic_\(obj.id)"
        node.geometry = box

        let outline = SCNBox(
            width: CGFloat(extent.x * 1.015),
            height: CGFloat(extent.y * 1.015),
            length: CGFloat(extent.z * 1.015),
            chamferRadius: CGFloat(min(extent.x, extent.z) * 0.06)
        )
        let outlineMaterial = SCNMaterial()
        outlineMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.9)
        outlineMaterial.emission.contents = UIColor.white.withAlphaComponent(0.5)
        outlineMaterial.fillMode = .lines
        outlineMaterial.isDoubleSided = true
        outline.firstMaterial = outlineMaterial
        let outlineNode = SCNNode(geometry: outline)
        node.addChildNode(outlineNode)

        applySemanticPlacement(to: node, obj: obj, extent: extent, in: rootNode)
        if let labelNode = makeSemanticLabelNode(for: obj, extent: extent) {
            node.addChildNode(labelNode)
        }
        return node
    }

    private func semanticDisplayExtent(for obj: SemanticSceneObject) -> SIMD3<Float> {
        SIMD3<Float>(
            Self.semanticMarkerExtent.x,
            Self.semanticMarkerHeight,
            Self.semanticMarkerExtent.z
        )
    }

    private func applySemanticPlacement(
        to node: SCNNode,
        obj: SemanticSceneObject,
        extent: SIMD3<Float>,
        in rootNode: SCNNode
    ) {
        let center = obj.centerXYZ ?? obj.baseAnchorXYZ ?? obj.supportAnchorXYZ ?? [0, 0, 0]
        let x = center.count > 0 ? center[0] : 0
        let z = center.count > 2 ? center[2] : 0

        let backendBaseY: Float
        if let baseAnchor = obj.baseAnchorXYZ, baseAnchor.count > 1 {
            backendBaseY = baseAnchor[1]
        } else if let supportAnchor = obj.supportAnchorXYZ, supportAnchor.count > 1 {
            backendBaseY = supportAnchor[1]
        } else {
            let cy = center.count > 1 ? center[1] : 0
            backendBaseY = cy - (extent.y * 0.5)
        }

        let snappedBaseY = snappedSemanticBaseY(
            near: SIMD2<Float>(x, z),
            preferredY: backendBaseY,
            in: rootNode
        ) ?? backendBaseY

        node.position = SCNVector3(x, snappedBaseY + (extent.y * 0.5), z)

        if let yaw = obj.yawRadians {
            node.eulerAngles = SCNVector3(0, yaw, 0)
        } else if let transform16 = obj.worldTransform16, let matrix = simd_float4x4.fromArray(transform16) {
            let yaw = atan2f(matrix.columns.0.z, matrix.columns.0.x)
            node.eulerAngles = SCNVector3(0, yaw, 0)
        }
    }

    private func snappedSemanticBaseY(
        near positionXZ: SIMD2<Float>,
        preferredY: Float,
        in rootNode: SCNNode
    ) -> Float? {
        guard let scaffoldGroup = rootNode.childNode(withName: Self.scaffoldGroupName, recursively: false) else {
            return nil
        }

        let supportNodes = scaffoldSupportCandidates(in: scaffoldGroup)
        guard !supportNodes.isEmpty else { return nil }

        var bestContainingTop: Float?
        var nearestTop: Float?
        var nearestDistance = Float.greatestFiniteMagnitude

        for candidate in supportNodes {
            let min = candidate.min
            let max = candidate.max
            let topY = max.y

            // Ignore ceilings / very high geometry relative to the semantic estimate.
            if topY > preferredY + 0.75 {
                continue
            }

            let contains =
                positionXZ.x >= min.x - 0.03 &&
                positionXZ.x <= max.x + 0.03 &&
                positionXZ.y >= min.z - 0.03 &&
                positionXZ.y <= max.z + 0.03

            if contains {
                if let current = bestContainingTop {
                    if topY > current {
                        bestContainingTop = topY
                    }
                } else {
                    bestContainingTop = topY
                }
                continue
            }

            let dx: Float
            if positionXZ.x < min.x {
                dx = min.x - positionXZ.x
            } else if positionXZ.x > max.x {
                dx = positionXZ.x - max.x
            } else {
                dx = 0
            }

            let dz: Float
            if positionXZ.y < min.z {
                dz = min.z - positionXZ.y
            } else if positionXZ.y > max.z {
                dz = positionXZ.y - max.z
            } else {
                dz = 0
            }

            let distance = hypotf(dx, dz)
            if distance < nearestDistance && distance < 0.28 {
                nearestDistance = distance
                nearestTop = topY
            }
        }

        return bestContainingTop ?? nearestTop
    }

    private func scaffoldSupportCandidates(in rootNode: SCNNode) -> [(min: SIMD3<Float>, max: SIMD3<Float>)] {
        var candidates: [(min: SIMD3<Float>, max: SIMD3<Float>)] = []

        func visit(_ node: SCNNode) {
            if node.geometry != nil, let bounds = worldBounds(for: node) {
                let size = bounds.max - bounds.min
                // Prefer horizontal support-like surfaces, not tall walls.
                if size.y < 1.35 && size.x > 0.12 && size.z > 0.12 {
                    candidates.append(bounds)
                }
            }
            for child in node.childNodes {
                visit(child)
            }
        }

        visit(rootNode)
        return candidates
    }

    private func worldBounds(for node: SCNNode) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        let (minBox, maxBox) = node.boundingBox
        let localCorners = [
            SCNVector3(minBox.x, minBox.y, minBox.z),
            SCNVector3(minBox.x, minBox.y, maxBox.z),
            SCNVector3(minBox.x, maxBox.y, minBox.z),
            SCNVector3(minBox.x, maxBox.y, maxBox.z),
            SCNVector3(maxBox.x, minBox.y, minBox.z),
            SCNVector3(maxBox.x, minBox.y, maxBox.z),
            SCNVector3(maxBox.x, maxBox.y, minBox.z),
            SCNVector3(maxBox.x, maxBox.y, maxBox.z),
        ]

        var minWorld = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxWorld = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for corner in localCorners {
            let world = node.convertPosition(corner, to: nil)
            let point = SIMD3<Float>(world.x, world.y, world.z)
            minWorld = simd_min(minWorld, point)
            maxWorld = simd_max(maxWorld, point)
        }

        guard minWorld.x.isFinite, minWorld.y.isFinite, minWorld.z.isFinite,
              maxWorld.x.isFinite, maxWorld.y.isFinite, maxWorld.z.isFinite else {
            return nil
        }

        return (minWorld, maxWorld)
    }

    private func makeSemanticLabelNode(for obj: SemanticSceneObject, extent: SIMD3<Float>) -> SCNNode? {
        let text = SCNText(string: obj.label.capitalized, extrusionDepth: 0.2)
        text.font = UIFont.systemFont(ofSize: 8, weight: .semibold)
        text.flatness = 0.2
        text.alignmentMode = CATextLayerAlignmentMode.center.rawValue

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.emission.contents = UIColor.white.withAlphaComponent(0.85)
        material.lightingModel = .constant
        material.isDoubleSided = true
        text.materials = [material]

        let labelNode = SCNNode(geometry: text)
        let (minVec, maxVec) = labelNode.boundingBox
        let width = maxVec.x - minVec.x
        let height = maxVec.y - minVec.y
        let targetWidth: Float = 0.18
        let scale = width > 0 ? targetWidth / width : 0.01
        labelNode.scale = SCNVector3(scale, scale, scale)
        labelNode.position = SCNVector3(
            0,
            extent.y * 0.75 + (height * scale * 0.5) + 0.04,
            0
        )
        labelNode.constraints = [SCNBillboardConstraint()]
        labelNode.renderingOrder = 10
        return labelNode
    }

    private func isRenderableSemanticObject(_ obj: SemanticSceneObject) -> Bool {
        let label = obj.label.lowercased()
        let smallObjectLabels = [
            "laptop",
            "keyboard",
            "mouse",
            "phone",
            "airpods case",
            "wallet",
            "keys",
            "glasses",
            "charger",
            "tv remote",
            "backpack",
            "book",
            "notebook",
            "bottle",
            "can",
            "mug",
            "bowl",
            "plate",
        ]
        guard smallObjectLabels.contains(label) else { return false }
        let supportType = obj.supportRelation?.type?.lowercased()
        let supportLabel = obj.supportRelation?.supportLabel?.lowercased()
        return supportType == "supported_by" && supportLabel != "floor"
    }

    private func categoryTintedMaterial(for obj: SemanticSceneObject) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.isDoubleSided = true
        material.metalness.contents = 0.1
        material.roughness.contents = 0.7

        let label = obj.label.lowercased()
        let color: UIColor
        switch label {
        case let l where l.contains("chair") || l.contains("sofa") || l.contains("couch") || l.contains("seat"):
            color = UIColor(red: 0.35, green: 0.55, blue: 0.75, alpha: 0.65)
        case let l where l.contains("table") || l.contains("desk") || l.contains("counter"):
            color = UIColor(red: 0.55, green: 0.45, blue: 0.35, alpha: 0.65)
        case let l where l.contains("bed") || l.contains("pillow") || l.contains("mattress"):
            color = UIColor(red: 0.55, green: 0.40, blue: 0.60, alpha: 0.65)
        case let l where l.contains("door") || l.contains("window"):
            color = UIColor(red: 0.45, green: 0.65, blue: 0.55, alpha: 0.55)
        case let l where l.contains("light") || l.contains("lamp"):
            color = UIColor(red: 0.85, green: 0.75, blue: 0.45, alpha: 0.65)
        case let l where l.contains("screen") || l.contains("monitor") || l.contains("tv"):
            color = UIColor(red: 0.30, green: 0.50, blue: 0.70, alpha: 0.65)
        case let l where l.contains("plant") || l.contains("flower"):
            color = UIColor(red: 0.35, green: 0.65, blue: 0.40, alpha: 0.65)
        case let l where l.contains("book") || l.contains("shelf"):
            color = UIColor(red: 0.60, green: 0.45, blue: 0.35, alpha: 0.65)
        default:
            color = UIColor(red: 0.50, green: 0.55, blue: 0.60, alpha: 0.55)
        }

        material.diffuse.contents = color
        return material
    }

    private func applyMaterialRecursively(_ material: SCNMaterial, to node: SCNNode) {
        if node.geometry != nil {
            node.geometry?.materials = [material]
        }
        for child in node.childNodes {
            applyMaterialRecursively(material, to: child)
        }
    }

    private func applySelectionHighlight(to node: SCNNode) {
        // Bright cyan edge glow via emission
        applyHighlightRecursively(to: node)
    }

    private func applyHighlightRecursively(to node: SCNNode) {
        if let geometry = node.geometry {
            for material in geometry.materials {
                material.emission.contents = UIColor(Color.spatialCyan)
                material.emission.intensity = 0.6
                material.transparency = min(material.transparency + 0.2, 1.0)
            }
        }
        for child in node.childNodes {
            applyHighlightRecursively(to: child)
        }
    }

    // MARK: - Observation Pins

    private func addObservationPins(to rootNode: SCNNode) {
        let group = SCNNode()
        group.name = Self.observationGroupName

        for obs in observations {
            let sphere = SCNSphere(radius: 0.02)
            sphere.firstMaterial?.diffuse.contents = pinColor(for: obs)
            sphere.firstMaterial?.lightingModel = .constant

            let node = SCNNode(geometry: sphere)
            node.name = obs.id.uuidString
            let transform = obs.worldTransform
            node.position = SCNVector3(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )
            group.addChildNode(node)
        }

        rootNode.addChildNode(group)
    }

    private func addHeatmapNodes(to rootNode: SCNNode) {
        let group = SCNNode()
        group.name = Self.heatmapGroupName

        for hypothesis in hypotheses {
            guard let transformData = hypothesis.transformData,
                  let transform = simd_float4x4.fromData(transformData) else { continue }

            let sphere = SCNSphere(radius: hypothesis.id == hypotheses.first?.id ? 0.12 : 0.09)
            let material = SCNMaterial()
            material.diffuse.contents = heatmapColor(for: hypothesis)
            material.transparency = 0.35
            material.lightingModel = .constant
            material.isDoubleSided = true
            sphere.firstMaterial = material

            let node = SCNNode(geometry: sphere)
            node.name = hypothesis.id.uuidString
            node.position = SCNVector3(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )
            group.addChildNode(node)
        }

        rootNode.addChildNode(group)
    }

    private func addDenseNodes(to rootNode: SCNNode) {
        let group = SCNNode()
        group.name = Self.denseGroupName
        defer { rootNode.addChildNode(group) }

        guard showDense, let denseAssetURL else { return }
        if let meshNode = loadDenseMeshNode(from: denseAssetURL) {
            meshNode.name = "densePreviewMesh"
            group.addChildNode(meshNode)
            return
        }
        guard let samples = try? loadDenseSamples(from: denseAssetURL), !samples.isEmpty else { return }

        let stride = max(1, Int(ceil(Double(samples.count) / Double(Self.maxDensePointCount))))
        let sampledPoints = samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: stride) ? sample : nil
        }

        guard let geometry = makeDensePointGeometry(from: sampledPoints) else { return }
        let node = SCNNode(geometry: geometry)
        node.name = "densePointCloud"
        group.addChildNode(node)
    }

    private func makeDensePointGeometry(from samples: [DensePointSample]) -> SCNGeometry? {
        guard !samples.isEmpty else { return nil }

        var vertexComponents: [Float] = []
        vertexComponents.reserveCapacity(samples.count * 3)
        var colorComponents: [UInt8] = []
        colorComponents.reserveCapacity(samples.count * 4)
        var indices: [UInt32] = []
        indices.reserveCapacity(samples.count)

        for (index, sample) in samples.enumerated() {
            vertexComponents.append(sample.position.x)
            vertexComponents.append(sample.position.y)
            vertexComponents.append(sample.position.z)

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 1
            sample.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            colorComponents.append(UInt8(max(0, min(255, Int(red * 255)))))
            colorComponents.append(UInt8(max(0, min(255, Int(green * 255)))))
            colorComponents.append(UInt8(max(0, min(255, Int(blue * 255)))))
            colorComponents.append(UInt8(max(0, min(255, Int(alpha * 255)))))
            indices.append(UInt32(index))
        }

        let vertexData = vertexComponents.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorData = colorComponents.withUnsafeBufferPointer { Data(buffer: $0) }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }

        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: samples.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: samples.count,
            usesFloatComponents: false,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<UInt8>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<UInt8>.size * 4
        )

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: samples.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = 6
        element.minimumPointScreenSpaceRadius = 3
        element.maximumPointScreenSpaceRadius = 10

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = true
        geometry.materials = [material]
        return geometry
    }

    private func loadDenseMeshNode(from url: URL) -> SCNNode? {
        let supportedMeshExtensions = Set(["obj", "usdz", "dae", "scn", "scnz"])
        guard supportedMeshExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        guard let scene = try? SCNScene(url: url, options: [.checkConsistency: false]) else { return nil }

        let container = SCNNode()
        for child in scene.rootNode.childNodes {
            let clone = child.clone()
            applyDensePreviewMaterialIfNeeded(to: clone)
            container.addChildNode(clone)
        }
        return container
    }

    private func applyDensePreviewMaterialIfNeeded(to node: SCNNode) {
        if let geometry = node.geometry, geometry.materials.isEmpty {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0.82, alpha: 1.0)
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.9
            material.metalness.contents = 0.0
            geometry.materials = [material]
        }
        for child in node.childNodes {
            applyDensePreviewMaterialIfNeeded(to: child)
        }
    }

    private func loadDenseSamples(from url: URL) throws -> [DensePointSample] {
        switch url.pathExtension.lowercased() {
        case "ply":
            return try loadPLYSamples(from: url)
        case "splat":
            return try loadSplatSamples(from: url)
        default:
            return []
        }
    }

    private func loadSplatSamples(from url: URL) throws -> [DensePointSample] {
        let data = try Data(contentsOf: url)
        let recordSize = 32
        guard data.count >= recordSize else { return [] }

        var samples: [DensePointSample] = []
        var offset = 0
        while offset + recordSize <= data.count {
            guard
                let x = readFloat32(from: data, offset: &offset),
                let y = readFloat32(from: data, offset: &offset),
                let z = readFloat32(from: data, offset: &offset)
            else {
                break
            }
            offset += 12 // skip scale
            guard
                let red = readUInt8(from: data, offset: &offset),
                let green = readUInt8(from: data, offset: &offset),
                let blue = readUInt8(from: data, offset: &offset),
                let _ = readUInt8(from: data, offset: &offset)
            else {
                break
            }
            offset += 4 // skip quaternion bytes

            samples.append(
                DensePointSample(
                    position: SIMD3(x, y, z),
                    color: UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
                )
            )
        }
        return samples
    }

    private func loadPLYSamples(from url: URL) throws -> [DensePointSample] {
        let data = try Data(contentsOf: url)
        guard
            let headerRange = data.range(of: Data("end_header\n".utf8)) ??
                data.range(of: Data("end_header\r\n".utf8))
        else {
            return []
        }

        let headerData = data[..<headerRange.upperBound]
        let headerString = String(decoding: headerData, as: UTF8.self)
        let header = parsePLYHeader(headerString)
        switch header.format {
        case .ascii:
            return parseASCIIPLYBody(
                Data(data[headerRange.upperBound...]),
                vertexCount: header.vertexCount,
                properties: header.properties
            )
        case .binaryLittleEndian:
            return parseBinaryPLYSamples(
                Data(data[headerRange.upperBound...]),
                vertexCount: header.vertexCount,
                properties: header.properties
            )
        }
    }

    private func parsePLYHeader(_ headerString: String) -> PLYHeader {
        var format = PLYFormat.ascii
        var vertexCount = 0
        var properties: [PLYProperty] = []
        var readingVertexProperties = false

        for line in headerString.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ")
            guard let first = parts.first else { continue }

            if first == "format", parts.count >= 2 {
                format = parts[1] == "binary_little_endian" ? .binaryLittleEndian : .ascii
                continue
            }

            if first == "element" {
                readingVertexProperties = parts.count >= 3 && parts[1] == "vertex"
                if readingVertexProperties {
                    vertexCount = Int(parts[2]) ?? 0
                }
                continue
            }

            if readingVertexProperties, first == "property", parts.count >= 3 {
                properties.append(PLYProperty(type: String(parts[1]), name: String(parts[2])))
            }
        }

        return PLYHeader(format: format, vertexCount: vertexCount, properties: properties)
    }

    private func parseASCIIPLYBody(
        _ bodyData: Data,
        vertexCount: Int,
        properties: [PLYProperty]
    ) -> [DensePointSample] {
        let lines = String(decoding: bodyData, as: UTF8.self).split(whereSeparator: \.isNewline)
        return lines.prefix(vertexCount).compactMap { line in
            let values = line.split(separator: " ")
            guard values.count >= properties.count else { return nil }

            var x: Float = 0
            var y: Float = 0
            var z: Float = 0
            var red: CGFloat = 0.75
            var green: CGFloat = 0.75
            var blue: CGFloat = 0.75

            for (index, property) in properties.enumerated() {
                let rawValue = String(values[index])
                switch property.name {
                case "x":
                    x = Float(rawValue) ?? 0
                case "y":
                    y = Float(rawValue) ?? 0
                case "z":
                    z = Float(rawValue) ?? 0
                case "red":
                    red = normalizedColorComponent(rawValue, type: property.type)
                case "green":
                    green = normalizedColorComponent(rawValue, type: property.type)
                case "blue":
                    blue = normalizedColorComponent(rawValue, type: property.type)
                default:
                    continue
                }
            }

            return DensePointSample(
                position: SIMD3(x, y, z),
                color: UIColor(red: red, green: green, blue: blue, alpha: 1)
            )
        }
    }

    private func parseBinaryPLYSamples(
        _ bodyData: Data,
        vertexCount: Int,
        properties: [PLYProperty]
    ) -> [DensePointSample] {
        var offset = 0
        var samples: [DensePointSample] = []

        for _ in 0..<vertexCount {
            var x: Float = 0
            var y: Float = 0
            var z: Float = 0
            var red: CGFloat = 0.75
            var green: CGFloat = 0.75
            var blue: CGFloat = 0.75

            for property in properties {
                guard let scalar = readScalar(type: property.type, from: bodyData, offset: &offset) else {
                    return samples
                }

                switch property.name {
                case "x":
                    x = Float(scalar)
                case "y":
                    y = Float(scalar)
                case "z":
                    z = Float(scalar)
                case "red":
                    red = normalizedColorComponent(scalar, type: property.type)
                case "green":
                    green = normalizedColorComponent(scalar, type: property.type)
                case "blue":
                    blue = normalizedColorComponent(scalar, type: property.type)
                default:
                    continue
                }
            }

            samples.append(
                DensePointSample(
                    position: SIMD3(x, y, z),
                    color: UIColor(red: red, green: green, blue: blue, alpha: 1)
                )
            )
        }

        return samples
    }

    private func normalizedColorComponent(_ value: String, type: String) -> CGFloat {
        normalizedColorComponent(Double(value) ?? 0, type: type)
    }

    private func normalizedColorComponent(_ value: Double, type: String) -> CGFloat {
        let normalizedType = type.lowercased()
        if normalizedType.contains("uchar") || normalizedType.contains("uint8") {
            return CGFloat(max(0, min(value / 255.0, 1.0)))
        }
        return CGFloat(max(0, min(value, 1.0)))
    }

    private func readScalar(type: String, from data: Data, offset: inout Int) -> Double? {
        switch type.lowercased() {
        case "char", "int8":
            guard let value = readUInt8(from: data, offset: &offset) else { return nil }
            return Double(Int8(bitPattern: value))
        case "uchar", "uint8":
            guard let value = readUInt8(from: data, offset: &offset) else { return nil }
            return Double(value)
        case "short", "int16":
            guard let value = readUInt16(from: data, offset: &offset) else { return nil }
            return Double(Int16(bitPattern: value))
        case "ushort", "uint16":
            guard let value = readUInt16(from: data, offset: &offset) else { return nil }
            return Double(value)
        case "int", "int32":
            guard let value = readUInt32(from: data, offset: &offset) else { return nil }
            return Double(Int32(bitPattern: value))
        case "uint", "uint32":
            guard let value = readUInt32(from: data, offset: &offset) else { return nil }
            return Double(value)
        case "double", "float64":
            guard let value = readUInt64(from: data, offset: &offset) else { return nil }
            return Double(bitPattern: value)
        case "float", "float32":
            fallthrough
        default:
            guard let value = readFloat32(from: data, offset: &offset) else { return nil }
            return Double(value)
        }
    }

    private func readUInt8(from data: Data, offset: inout Int) -> UInt8? {
        guard offset < data.count else { return nil }
        let value = data[offset]
        offset += 1
        return value
    }

    private func readUInt16(from data: Data, offset: inout Int) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        offset += 2
        return b0 | b1
    }

    private func readUInt32(from data: Data, offset: inout Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let value =
            UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
        offset += 4
        return value
    }

    private func readUInt64(from data: Data, offset: inout Int) -> UInt64? {
        guard offset + 8 <= data.count else { return nil }
        let value =
            UInt64(data[offset]) |
            (UInt64(data[offset + 1]) << 8) |
            (UInt64(data[offset + 2]) << 16) |
            (UInt64(data[offset + 3]) << 24) |
            (UInt64(data[offset + 4]) << 32) |
            (UInt64(data[offset + 5]) << 40) |
            (UInt64(data[offset + 6]) << 48) |
            (UInt64(data[offset + 7]) << 56)
        offset += 8
        return value
    }

    private func readFloat32(from data: Data, offset: inout Int) -> Float? {
        guard let bits = readUInt32(from: data, offset: &offset) else { return nil }
        return Float(bitPattern: bits)
    }

    private func pinColor(for obs: ObjectObservation) -> UIColor {
        switch obs.confidenceClass {
        case .confirmedHigh:    return UIColor(Color.spatialCyan)
        case .confirmedMedium:  return UIColor(Color.spatialCyan.opacity(0.7))
        case .lastSeen:         return UIColor(Color.warningAmber)
        case .signalEstimated:  return UIColor(Color.signalMagenta)
        case .likelihoodRanked: return UIColor(Color.inferenceViolet)
        case .noResult:         return UIColor(Color.dimLabel)
        }
    }

    private func heatmapColor(for hypothesis: ObjectHypothesis) -> UIColor {
        switch hypothesis.hypothesisType {
        case .cooperative:
            return UIColor(Color.signalMagenta)
        case .tagged:
            return UIColor(Color.spatialCyan)
        case .inferred:
            return UIColor(Color.inferenceViolet)
        }
    }

    // MARK: - Screen Projection

    private func startProjectionTimer(context: Context) {
        let coordinator = context.coordinator
        let displayLink = CADisplayLink(target: coordinator,
                                        selector: #selector(Coordinator.updateProjections))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        coordinator.displayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        weak var scnView: SCNView?
        var displayLink: CADisplayLink?
        var observations: [ObjectObservation] = []
        var projectedPositions: Binding<[UUID: CGPoint]>?
        var showObjects: Bool = true
        var onSemanticObjectTapped: ((String) -> Void)?
        private var observationSignature: String?
        private var hypothesisSignature: String?
        private var denseAssetPath: String?
        private var lastShowDense = false
        private var semanticSignature: String?
        private var lastSelectedSemanticID: String?
        private var lastShowSemantic = false
        private var lastViewerMode: ViewerMode = .semantic

        func needsRebuild(
            observations: [ObjectObservation],
            hypotheses: [ObjectHypothesis],
            showDense: Bool,
            denseAssetURL: URL?,
            semanticObjects: [SemanticSceneObject],
            selectedSemanticObjectID: String?,
            showSemanticObjects: Bool,
            viewerMode: ViewerMode
        ) -> Bool {
            let nextObservationSignature = Self.signature(for: observations)
            let nextHypothesisSignature = Self.signature(for: hypotheses)
            let nextDenseAssetPath = denseAssetURL?.path
            let nextSemanticSignature = Self.semanticSignature(for: semanticObjects)

            return nextObservationSignature != observationSignature ||
                nextHypothesisSignature != hypothesisSignature ||
                nextDenseAssetPath != denseAssetPath ||
                showDense != lastShowDense ||
                nextSemanticSignature != semanticSignature ||
                selectedSemanticObjectID != lastSelectedSemanticID ||
                showSemanticObjects != lastShowSemantic ||
                viewerMode != lastViewerMode
        }

        func cacheSnapshot(
            observations: [ObjectObservation],
            hypotheses: [ObjectHypothesis],
            showDense: Bool,
            denseAssetURL: URL?,
            semanticObjects: [SemanticSceneObject],
            selectedSemanticObjectID: String?,
            showSemanticObjects: Bool,
            viewerMode: ViewerMode
        ) {
            observationSignature = Self.signature(for: observations)
            hypothesisSignature = Self.signature(for: hypotheses)
            denseAssetPath = denseAssetURL?.path
            lastShowDense = showDense
            semanticSignature = Self.semanticSignature(for: semanticObjects)
            lastSelectedSemanticID = selectedSemanticObjectID
            lastShowSemantic = showSemanticObjects
            lastViewerMode = viewerMode
        }

        @MainActor @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let scnView else { return }
            let location = gestureRecognizer.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue
            ])

            for hit in hitResults {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("semantic_") {
                        let objectID = String(name.dropFirst("semantic_".count))
                        onSemanticObjectTapped?(objectID)
                        return
                    }
                    node = current.parent
                }
            }
            // Tapped empty space — deselect
            onSemanticObjectTapped?("")
        }

        @MainActor @objc func updateProjections() {
            guard showObjects,
                  let scnView,
                  let rootNode = scnView.scene?.rootNode,
                  let pinGroup = rootNode.childNode(withName: SceneViewRepresentable.observationGroupName,
                                                    recursively: false)
            else {
                projectedPositions?.wrappedValue = [:]
                return
            }

            var positions: [UUID: CGPoint] = [:]
            for obs in observations {
                guard let node = pinGroup.childNode(withName: obs.id.uuidString, recursively: false) else { continue }
                let projected = scnView.projectPoint(node.worldPosition)
                if projected.z > 0 && projected.z < 1 {
                    positions[obs.id] = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                }
            }
            projectedPositions?.wrappedValue = positions
        }

        deinit {
            displayLink?.invalidate()
        }

        private static func signature(for observations: [ObjectObservation]) -> String {
            observations.map { observation in
                let position = observation.worldTransform.columns.3
                return "\(observation.id.uuidString):\(position.x):\(position.y):\(position.z)"
            }
            .joined(separator: "|")
        }

        private static func signature(for hypotheses: [ObjectHypothesis]) -> String {
            hypotheses.map { hypothesis in
                let transformSignature = hypothesis.transformData?.base64EncodedString() ?? "nil"
                return "\(hypothesis.id.uuidString):\(hypothesis.rank):\(hypothesis.confidence):\(transformSignature)"
            }
            .joined(separator: "|")
        }

        private static func semanticSignature(for objects: [SemanticSceneObject]) -> String {
            objects.map { obj in
                "\(obj.id):\(obj.label):\(obj.confidence)"
            }
            .joined(separator: "|")
        }
    }
}

private struct DensePointSample {
    let position: SIMD3<Float>
    let color: UIColor
}

private struct PLYProperty {
    let type: String
    let name: String
}

private struct PLYHeader {
    let format: PLYFormat
    let vertexCount: Int
    let properties: [PLYProperty]
}

private enum PLYFormat {
    case ascii
    case binaryLittleEndian
}
