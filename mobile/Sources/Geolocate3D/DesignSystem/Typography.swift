// DesignSystem/Typography.swift
import SwiftUI

enum SpatialFont {
    // Display — SF Pro for clean Apple-native feel
    static let largeTitle  = Font.system(size: 34, weight: .bold, design: .default)
    static let title       = Font.system(size: 28, weight: .semibold, design: .default)
    static let title2      = Font.system(size: 22, weight: .semibold, design: .default)
    static let title3      = Font.system(size: 20, weight: .medium, design: .default)
    static let headline    = Font.system(size: 17, weight: .semibold, design: .default)

    // Body — clear, readable hierarchy
    static let body        = Font.system(size: 17, weight: .regular)
    static let callout     = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let footnote    = Font.system(size: 13, weight: .regular)
    static let caption     = Font.system(size: 12, weight: .medium)

    // Data — monospaced for measurements and confidence values
    static let dataLarge   = Font.system(size: 22, weight: .semibold, design: .monospaced)
    static let dataMedium  = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let dataSmall   = Font.system(size: 11, weight: .medium, design: .monospaced)
}
