// DesignSystem/Typography.swift
import SwiftUI

enum SpatialFont {
    // Display — SF Pro Rounded for spatial warmth
    static let largeTitle  = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title       = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let title2      = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let headline    = Font.system(size: 17, weight: .semibold, design: .rounded)

    // Body — SF Pro default for readability
    static let body        = Font.system(size: 17, weight: .regular)
    static let callout     = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let caption     = Font.system(size: 13, weight: .regular)

    // Data — monospaced digits for coordinates, measurements, confidence
    static let dataLarge   = Font.system(size: 20, weight: .medium, design: .monospaced)
    static let dataMedium  = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let dataSmall   = Font.system(size: 12, weight: .medium, design: .monospaced)
}
