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

    static func fromArray(_ values: [Float]) -> simd_float4x4? {
        guard values.count == 16 else { return nil }
        return simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], values[3]),
            SIMD4(values[4], values[5], values[6], values[7]),
            SIMD4(values[8], values[9], values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        ))
    }
}
