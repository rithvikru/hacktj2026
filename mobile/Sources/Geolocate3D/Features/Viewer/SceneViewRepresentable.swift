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
    /// Binding updated each frame with projected 2D positions for SwiftUI annotation overlay.
    @Binding var projectedPositions: [UUID: CGPoint]

    private static let scaffoldGroupName = "scaffoldContent"
    private static let observationGroupName = "observationPins"
    private static let heatmapGroupName = "heatmapNodes"
    private static let denseGroupName = "densePoints"
    private static let maxDensePointCount = 1_200

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X

        let scene = loadBaseScene()
        scnView.scene = scene
        rebuildDynamicContent(in: scene.rootNode)
        updateVisibility(in: scene.rootNode)

        context.coordinator.scnView = scnView
        context.coordinator.observations = observations
        context.coordinator.projectedPositions = $projectedPositions
        context.coordinator.showObjects = showObjects
        startProjectionTimer(context: context)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let rootNode = scnView.scene?.rootNode else { return }
        rebuildDynamicContent(in: rootNode)
        updateVisibility(in: rootNode)
        context.coordinator.observations = observations
        context.coordinator.showObjects = showObjects
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

        addObservationPins(to: rootNode)
        addHeatmapNodes(to: rootNode)
        addDenseNodes(to: rootNode)
    }

    private func updateVisibility(in rootNode: SCNNode) {
        rootNode.childNode(withName: Self.scaffoldGroupName, recursively: false)?.isHidden = !showScaffold
        rootNode.childNode(withName: Self.observationGroupName, recursively: false)?.isHidden = !showObjects
        rootNode.childNode(withName: Self.heatmapGroupName, recursively: false)?.isHidden = !showHeatmap
        rootNode.childNode(withName: Self.denseGroupName, recursively: false)?.isHidden = !showDense
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
        guard let samples = try? loadDenseSamples(from: denseAssetURL), !samples.isEmpty else { return }

        let stride = max(1, samples.count / Self.maxDensePointCount)
        for sample in samples.enumerated().compactMap({ index, sample in
            index.isMultiple(of: stride) ? sample : nil
        }) {
            let sphere = SCNSphere(radius: 0.008)
            let material = SCNMaterial()
            material.diffuse.contents = sample.color
            material.lightingModel = .constant
            sphere.firstMaterial = material

            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(sample.position.x, sample.position.y, sample.position.z)
            group.addChildNode(node)
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

        @objc func updateProjections() {
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
