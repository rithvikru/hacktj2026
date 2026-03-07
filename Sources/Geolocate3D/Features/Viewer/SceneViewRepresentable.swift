import SwiftUI
import SceneKit
import simd

struct SceneViewRepresentable: UIViewRepresentable {
    let roomID: UUID
    let observations: [ObjectObservation]
    let showScaffold: Bool
    let showObjects: Bool
    let showHeatmap: Bool
    let showDense: Bool

    @Binding var projectedPositions: [UUID: CGPoint]

    private static let observationGroupName = "observationPins"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

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
            addObservationPins(to: scene.rootNode)
        } else {
            scnView.scene = SCNScene()
        }

        context.coordinator.scnView = scnView
        startProjectionTimer(context: context)

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        guard let rootNode = scnView.scene?.rootNode else { return }

        let pinGroup = rootNode.childNode(withName: Self.observationGroupName, recursively: false)
        pinGroup?.isHidden = !showObjects
    }

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
            node.position = SCNVector3(transform.columns.3.x,
                                       transform.columns.3.y,
                                       transform.columns.3.z)
            group.addChildNode(node)
        }

        rootNode.addChildNode(group)
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

    private func startProjectionTimer(context: Context) {
        let coordinator = context.coordinator
        let displayLink = CADisplayLink(target: coordinator,
                                        selector: #selector(Coordinator.updateProjections))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        coordinator.displayLink = displayLink
        coordinator.observations = observations
        coordinator.projectedPositions = $projectedPositions
        coordinator.showObjects = showObjects
        displayLink.add(to: .main, forMode: .common)
    }

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
            else { return }

            var positions: [UUID: CGPoint] = [:]
            for obs in observations {
                guard let node = pinGroup.childNode(withName: obs.id.uuidString,
                                                     recursively: false) else { continue }
                let projected = scnView.projectPoint(node.worldPosition)

                if projected.z > 0 && projected.z < 1 {
                    positions[obs.id] = CGPoint(x: CGFloat(projected.x),
                                                y: CGFloat(projected.y))
                }
            }
            projectedPositions?.wrappedValue = positions
        }

        deinit {
            displayLink?.invalidate()
        }
    }
}
