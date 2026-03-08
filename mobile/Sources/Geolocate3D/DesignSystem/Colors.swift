// DesignSystem/Colors.swift
import SwiftUI

extension Color {
    // Backgrounds — refined dark grays for depth, not pure black
    static let spaceBlack       = Color(red: 0.06, green: 0.06, blue: 0.07) // #0F0F12
    static let obsidian         = Color(red: 0.09, green: 0.09, blue: 0.11) // #17171C
    static let voidGray         = Color(red: 0.13, green: 0.13, blue: 0.16) // #212128

    // Spatial Accents — sophisticated, muted tones
    static let spatialCyan      = Color(red: 0.30, green: 0.68, blue: 0.82) // #4DAEД1 — muted teal
    static let signalMagenta    = Color(red: 0.82, green: 0.35, blue: 0.55) // #D1598C — soft rose
    static let confirmGreen     = Color(red: 0.35, green: 0.78, blue: 0.55) // #59C78C — sage green
    static let warningAmber     = Color(red: 0.92, green: 0.72, blue: 0.30) // #EBB84D — warm amber
    static let inferenceViolet  = Color(red: 0.55, green: 0.45, blue: 0.85) // #8C73D9 — soft violet

    // Surface materials — subtle translucent layers
    static let glassWhite       = Color.white.opacity(0.05)
    static let glassEdge        = Color.white.opacity(0.08)
    static let dimLabel         = Color.white.opacity(0.45)

    // Elevated surfaces
    static let elevatedSurface  = Color(red: 0.15, green: 0.15, blue: 0.18) // #26262E
    static let cardBackground   = Color(red: 0.11, green: 0.11, blue: 0.14) // #1C1C24
}

extension ShapeStyle where Self == Color {
    static var spatialCyan: Color { .spatialCyan }
    static var signalMagenta: Color { .signalMagenta }
    static var confirmGreen: Color { .confirmGreen }
    static var warningAmber: Color { .warningAmber }
    static var inferenceViolet: Color { .inferenceViolet }
    static var spaceBlack: Color { .spaceBlack }
    static var obsidian: Color { .obsidian }
    static var voidGray: Color { .voidGray }
    static var glassWhite: Color { .glassWhite }
    static var glassEdge: Color { .glassEdge }
    static var dimLabel: Color { .dimLabel }
    static var elevatedSurface: Color { .elevatedSurface }
    static var cardBackground: Color { .cardBackground }
}
