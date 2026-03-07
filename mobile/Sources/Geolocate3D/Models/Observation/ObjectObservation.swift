import SwiftData
import Foundation
import simd

@Model
final class ObjectObservation {
    @Attribute(.unique) var id: UUID
    var label: String
    var sourceRaw: String
    var confidence: Double
    var transformData: Data
    var observedAt: Date
    var boundingBoxX: Float?
    var boundingBoxY: Float?
    var boundingBoxW: Float?
    var boundingBoxH: Float?
    var maskPath: String?
    var snapshotPath: String?
    var visibilityStateRaw: String

    var room: RoomRecord?
    var prototype: ObjectPrototype?

    @Transient var worldTransform: simd_float4x4 {
        simd_float4x4.fromData(transformData) ?? matrix_identity_float4x4
    }

    @Transient var source: ObservationSource {
        ObservationSource(rawValue: sourceRaw) ?? .closedSet
    }

    @Transient var confidenceClass: DetectionConfidenceClass {
        switch (source, confidence) {
        case (.signal, _): return .signalEstimated
        case (_, 0.8...): return .confirmedHigh
        case (_, 0.5..<0.8): return .confirmedMedium
        default: return .lastSeen
        }
    }

    @Transient var visibilityState: VisibilityState {
        VisibilityState(rawValue: visibilityStateRaw) ?? .unknown
    }

    init(label: String, source: ObservationSource, confidence: Double,
         transform: simd_float4x4) {
        self.id = UUID()
        self.label = label
        self.sourceRaw = source.rawValue
        self.confidence = confidence
        self.transformData = transform.toData()
        self.observedAt = Date()
        self.visibilityStateRaw = VisibilityState.visible.rawValue
    }
}
