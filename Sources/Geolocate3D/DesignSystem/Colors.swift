// DesignSystem/Colors.swift
import SwiftUI

extension Color {
    // Backgrounds — true black for OLED + depth layers
    static let spaceBlack       = Color(red: 0.00, green: 0.00, blue: 0.00) // #000000
    static let obsidian         = Color(red: 0.04, green: 0.04, blue: 0.06) // #0A0A0F
    static let voidGray         = Color(red: 0.08, green: 0.08, blue: 0.12) // #14141F

    // Spatial Accents — luminous, high-contrast on black
    static let spatialCyan      = Color(red: 0.00, green: 0.96, blue: 1.00) // #00F5FF
    static let signalMagenta    = Color(red: 1.00, green: 0.00, blue: 0.80) // #FF00CC
    static let confirmGreen     = Color(red: 0.22, green: 1.00, blue: 0.08) // #39FF14
    static let warningAmber     = Color(red: 1.00, green: 0.75, blue: 0.00) // #FFBF00
    static let inferenceViolet  = Color(red: 0.55, green: 0.20, blue: 1.00) // #8C33FF

    // Surface materials — translucent layers
    static let glassWhite       = Color.white.opacity(0.06)
    static let glassEdge        = Color.white.opacity(0.12)
    static let dimLabel         = Color.white.opacity(0.5)
}
