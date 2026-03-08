import Foundation
import SceneKit
import SwiftData
import UIKit
import simd

enum DemoRoomCatalog {
    static let roomID = UUID(uuidString: "6B3D9D6E-7B8A-4E6A-9C6E-5E2A6D3C1B90")!
    static let roomName = "Demo Tabletop Lab"

    static func isDemoRoom(_ id: UUID) -> Bool {
        id == roomID
    }

    @MainActor
    static func seedIfNeeded(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<RoomRecord>(
            predicate: #Predicate { $0.id == roomID }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = roomName
            existing.reconstructionStatus = .complete
            existing.updatedAt = Date()
            seedObservationsIfNeeded(into: existing, modelContext: modelContext)
            try? modelContext.save()
            return
        }

        let room = RoomRecord(id: roomID, name: roomName)
        room.reconstructionStatus = .complete
        room.updatedAt = Date()

        let persistence = RoomPersistenceService()
        try? persistence.createRoomDirectory(roomID: roomID)
        if let previewImage = makePreviewImage() {
            room.previewImagePath = try? persistence.savePreviewImage(previewImage, roomID: roomID)
        }

        modelContext.insert(room)
        seedObservationsIfNeeded(into: room, modelContext: modelContext)
        try? modelContext.save()
    }

    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode

        root.addChildNode(makeFloorNode())
        root.addChildNode(makeWallNode(size: SCNVector3(3.45, 2.25, 0.08), position: SCNVector3(0, 1.12, -1.62)))
        root.addChildNode(makeWallNode(size: SCNVector3(0.08, 2.25, 3.28), position: SCNVector3(-1.72, 1.12, 0)))
        root.addChildNode(makeWallNode(size: SCNVector3(0.08, 2.25, 3.28), position: SCNVector3(1.72, 1.12, 0)))
        root.addChildNode(makeWallNode(size: SCNVector3(1.1, 2.25, 0.08), position: SCNVector3(1.15, 1.12, 1.32)))

        root.addChildNode(makeDeskNode())
        root.addChildNode(makeSideTableNode())
        root.addChildNode(makeShelfNode())
        root.addChildNode(makeCouchNode())
        root.addChildNode(makeMonitorNode())
        root.addChildNode(makeTvPanelNode())
        root.addChildNode(makeCrateStackNode())

        return scene
    }

    static func semanticScene() -> SemanticSceneResponse {
        SemanticSceneResponse(
            objects: semanticObjects(),
            roomID: roomID.uuidString,
            sceneVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Private

    @MainActor
    private static func seedObservationsIfNeeded(into room: RoomRecord, modelContext: ModelContext) {
        guard room.observations.isEmpty else { return }

        for object in semanticObjects() {
            guard let transform = simd_float4x4.fromArray(object.worldTransform16 ?? []) else { continue }
            let observation = ObjectObservation(
                label: object.label,
                source: .openVocabulary,
                confidence: object.confidence,
                transform: transform
            )
            observation.room = room
            modelContext.insert(observation)
        }
    }

    private static func semanticObjects() -> [SemanticSceneObject] {
        [
            makeObject(
                id: "demo-laptop",
                label: "laptop",
                center: [0.08, 0.81, -0.20],
                base: [0.08, 0.78, -0.20],
                yaw: .pi * -0.08,
                supportObjectID: "main-desk",
                supportLabel: "desk",
                supportHeightY: 0.78,
                confidence: 0.96
            ),
            makeObject(
                id: "demo-water-bottle",
                label: "water bottle",
                center: [0.42, 0.81, -0.04],
                base: [0.42, 0.78, -0.04],
                yaw: .pi * 0.02,
                supportObjectID: "main-desk",
                supportLabel: "desk",
                supportHeightY: 0.78,
                confidence: 0.92
            ),
            makeObject(
                id: "demo-can",
                label: "can",
                center: [0.55, 0.81, -0.24],
                base: [0.55, 0.78, -0.24],
                yaw: .pi * 0.06,
                supportObjectID: "main-desk",
                supportLabel: "desk",
                supportHeightY: 0.78,
                confidence: 0.89
            ),
            makeObject(
                id: "demo-notebook",
                label: "notebook",
                center: [-0.24, 0.81, -0.08],
                base: [-0.24, 0.78, -0.08],
                yaw: .pi * -0.12,
                supportObjectID: "main-desk",
                supportLabel: "desk",
                supportHeightY: 0.78,
                confidence: 0.87
            ),
            makeObject(
                id: "demo-clipboard",
                label: "clipboard",
                center: [-0.46, 0.81, -0.24],
                base: [-0.46, 0.78, -0.24],
                yaw: .pi * 0.14,
                supportObjectID: "main-desk",
                supportLabel: "desk",
                supportHeightY: 0.78,
                confidence: 0.84
            ),
            makeObject(
                id: "demo-phone",
                label: "phone",
                center: [0.18, 0.81, 0.18],
                base: [0.18, 0.78, 0.18],
                yaw: .pi * -0.18,
                supportObjectID: "main-desk",
                supportLabel: "desk",
                supportHeightY: 0.78,
                confidence: 0.93
            ),
            makeObject(
                id: "demo-charger",
                label: "charger",
                center: [0.33, 0.81, 0.19],
                base: [0.33, 0.78, 0.19],
                yaw: .pi * 0.21,
                supportObjectID: "main-desk",
                supportLabel: "desk",
                supportHeightY: 0.78,
                confidence: 0.82
            ),
            makeObject(
                id: "demo-airpods",
                label: "airpods case",
                center: [-0.05, 0.81, 0.23],
                base: [-0.05, 0.78, 0.23],
                yaw: .pi * 0.07,
                supportObjectID: "main-desk",
                supportLabel: "desk",
                supportHeightY: 0.78,
                confidence: 0.88
            ),
            makeObject(
                id: "demo-tissue-box",
                label: "tissue box",
                center: [-0.93, 0.69, 0.55],
                base: [-0.93, 0.66, 0.55],
                yaw: 0,
                supportObjectID: "side-table",
                supportLabel: "table",
                supportHeightY: 0.66,
                confidence: 0.8
            ),
            makeObject(
                id: "demo-backpack",
                label: "backpack",
                center: [-1.10, 0.69, 0.42],
                base: [-1.10, 0.66, 0.42],
                yaw: .pi * -0.1,
                supportObjectID: "side-table",
                supportLabel: "table",
                supportHeightY: 0.66,
                confidence: 0.86
            ),
        ]
    }

    private static func makeObject(
        id: String,
        label: String,
        center: [Float],
        base: [Float],
        yaw: Float,
        supportObjectID: String,
        supportLabel: String,
        supportHeightY: Float,
        confidence: Double
    ) -> SemanticSceneObject {
        SemanticSceneObject(
            id: id,
            label: label,
            confidence: confidence,
            worldTransform16: makeWorldTransform(centerX: center[0], centerY: center[1], centerZ: center[2], yaw: yaw),
            centerXYZ: center,
            extentXYZ: [0.14, 0.06, 0.14],
            baseAnchorXYZ: base,
            supportAnchorXYZ: [base[0], supportHeightY, base[2]],
            supportNormalXYZ: [0, 1, 0],
            principalAxisXYZ: [cos(yaw), 0, sin(yaw)],
            yawRadians: yaw,
            footprintXYZ: [
                [base[0] - 0.07, supportHeightY, base[2] - 0.07],
                [base[0] + 0.07, supportHeightY, base[2] - 0.07],
                [base[0] + 0.07, supportHeightY, base[2] + 0.07],
                [base[0] - 0.07, supportHeightY, base[2] + 0.07],
            ],
            meshKind: "demo_marker",
            meshAssetURL: nil,
            pointCount: 64,
            supportingViewCount: 6,
            maskSupportedViewCount: 6,
            bboxFallbackViewCount: 0,
            supportRelation: SupportRelationDTO(
                type: "supported_by",
                supportObjectID: supportObjectID,
                supportLabel: supportLabel,
                supportHeightY: supportHeightY,
                parentID: nil,
                parentLabel: supportLabel,
                relationType: "supported_by"
            )
        )
    }

    private static func makeWorldTransform(centerX: Float, centerY: Float, centerZ: Float, yaw: Float) -> [Float] {
        let cosYaw = cos(yaw)
        let sinYaw = sin(yaw)
        return [
            cosYaw, 0, -sinYaw, 0,
            0, 1, 0, 0,
            sinYaw, 0, cosYaw, 0,
            centerX, centerY, centerZ, 1
        ]
    }

    private static func makePreviewImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 960, height: 640))
        return renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: 960, height: 640))

            cg.setFillColor(UIColor(red: 0.18, green: 0.20, blue: 0.24, alpha: 1).cgColor)
            cg.fill(CGRect(x: 90, y: 430, width: 780, height: 110))

            cg.setStrokeColor(UIColor(white: 1, alpha: 0.18).cgColor)
            cg.setLineWidth(8)
            cg.stroke(CGRect(x: 110, y: 140, width: 740, height: 320))

            cg.setFillColor(UIColor(red: 0.35, green: 0.38, blue: 0.42, alpha: 1).cgColor)
            cg.fill(CGRect(x: 310, y: 250, width: 340, height: 120))
            cg.fill(CGRect(x: 130, y: 285, width: 120, height: 84))

            let accent = UIColor(red: 0.25, green: 0.78, blue: 0.85, alpha: 1).cgColor
            cg.setFillColor(accent)
            let objectRects = [
                CGRect(x: 370, y: 286, width: 58, height: 32),
                CGRect(x: 454, y: 276, width: 24, height: 50),
                CGRect(x: 505, y: 289, width: 24, height: 34),
                CGRect(x: 560, y: 300, width: 42, height: 22),
                CGRect(x: 158, y: 308, width: 38, height: 30),
            ]
            objectRects.forEach { cg.fill($0) }
        }
    }

    private static func makeFloorNode() -> SCNNode {
        let floor = SCNBox(width: 3.55, height: 0.06, length: 3.35, chamferRadius: 0.02)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.16, green: 0.18, blue: 0.21, alpha: 1)
        floor.materials = [material]
        let node = SCNNode(geometry: floor)
        node.position = SCNVector3(0, -0.03, 0)
        return node
    }

    private static func makeWallNode(size: SCNVector3, position: SCNVector3) -> SCNNode {
        let wall = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0.01)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.62, green: 0.64, blue: 0.68, alpha: 1)
        wall.materials = [material]
        let node = SCNNode(geometry: wall)
        node.position = position
        return node
    }

    private static func makeDeskNode() -> SCNNode {
        let group = SCNNode()
        let top = makeBoxNode(size: SCNVector3(1.55, 0.06, 0.88), position: SCNVector3(0.15, 0.75, -0.05), color: UIColor(red: 0.56, green: 0.49, blue: 0.42, alpha: 1))
        group.addChildNode(top)
        for offset in [(-0.55, -0.32), (0.55, -0.32), (-0.55, 0.32), (0.55, 0.32)] {
            group.addChildNode(
                makeBoxNode(
                    size: SCNVector3(0.07, 0.72, 0.07),
                    position: SCNVector3(Float(offset.0) + 0.15, 0.36, Float(offset.1) - 0.05),
                    color: UIColor(red: 0.38, green: 0.34, blue: 0.31, alpha: 1)
                )
            )
        }
        return group
    }

    private static func makeSideTableNode() -> SCNNode {
        let group = SCNNode()
        let top = makeBoxNode(size: SCNVector3(0.72, 0.06, 0.52), position: SCNVector3(-0.98, 0.63, 0.48), color: UIColor(red: 0.48, green: 0.45, blue: 0.40, alpha: 1))
        group.addChildNode(top)
        for offset in [(-0.24, -0.15), (0.24, -0.15), (-0.24, 0.15), (0.24, 0.15)] {
            group.addChildNode(
                makeBoxNode(
                    size: SCNVector3(0.05, 0.58, 0.05),
                    position: SCNVector3(Float(offset.0) - 0.98, 0.29, Float(offset.1) + 0.48),
                    color: UIColor(red: 0.32, green: 0.30, blue: 0.28, alpha: 1)
                )
            )
        }
        return group
    }

    private static func makeShelfNode() -> SCNNode {
        let group = SCNNode()
        group.addChildNode(makeBoxNode(size: SCNVector3(0.72, 1.65, 0.28), position: SCNVector3(1.18, 0.82, 0.42), color: UIColor(red: 0.42, green: 0.39, blue: 0.35, alpha: 1)))
        for y in stride(from: Float(0.25), through: 1.35, by: 0.37) {
            group.addChildNode(makeBoxNode(size: SCNVector3(0.78, 0.03, 0.32), position: SCNVector3(1.18, y, 0.42), color: UIColor(red: 0.55, green: 0.50, blue: 0.44, alpha: 1)))
        }
        return group
    }

    private static func makeCouchNode() -> SCNNode {
        let group = SCNNode()
        group.addChildNode(makeBoxNode(size: SCNVector3(0.95, 0.32, 0.62), position: SCNVector3(-1.03, 0.18, -0.95), color: UIColor(red: 0.30, green: 0.34, blue: 0.39, alpha: 1)))
        group.addChildNode(makeBoxNode(size: SCNVector3(0.95, 0.42, 0.12), position: SCNVector3(-1.03, 0.55, -1.20), color: UIColor(red: 0.34, green: 0.38, blue: 0.42, alpha: 1)))
        group.addChildNode(makeBoxNode(size: SCNVector3(0.12, 0.42, 0.62), position: SCNVector3(-1.47, 0.40, -0.95), color: UIColor(red: 0.34, green: 0.38, blue: 0.42, alpha: 1)))
        return group
    }

    private static func makeMonitorNode() -> SCNNode {
        let group = SCNNode()
        group.addChildNode(makeBoxNode(size: SCNVector3(0.46, 0.28, 0.03), position: SCNVector3(0.16, 1.00, -0.43), color: UIColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1)))
        group.addChildNode(makeBoxNode(size: SCNVector3(0.06, 0.18, 0.05), position: SCNVector3(0.16, 0.82, -0.43), color: UIColor(red: 0.18, green: 0.20, blue: 0.24, alpha: 1)))
        return group
    }

    private static func makeTvPanelNode() -> SCNNode {
        makeBoxNode(size: SCNVector3(0.88, 0.46, 0.04), position: SCNVector3(1.15, 1.20, 1.23), color: UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1))
    }

    private static func makeCrateStackNode() -> SCNNode {
        let group = SCNNode()
        group.addChildNode(makeBoxNode(size: SCNVector3(0.28, 0.28, 0.28), position: SCNVector3(1.02, 0.14, -0.72), color: UIColor(red: 0.52, green: 0.42, blue: 0.30, alpha: 1)))
        group.addChildNode(makeBoxNode(size: SCNVector3(0.22, 0.22, 0.22), position: SCNVector3(1.24, 0.11, -0.68), color: UIColor(red: 0.61, green: 0.49, blue: 0.34, alpha: 1)))
        return group
    }

    private static func makeBoxNode(size: SCNVector3, position: SCNVector3, color: UIColor) -> SCNNode {
        let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0.02)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .physicallyBased
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.position = position
        return node
    }
}
