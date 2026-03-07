import simd
import Foundation

extension simd_float4x4 {
    func toData() -> Data {
        var matrix = self
        return withUnsafeBytes(of: &matrix) { Data($0) }
    }

    static func fromData(_ data: Data) -> simd_float4x4? {
        guard data.count == MemoryLayout<simd_float4x4>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: simd_float4x4.self) }
    }
}
