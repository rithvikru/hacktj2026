import SwiftUI

extension Color {

    static let spaceBlack       = Color(red: 0.00, green: 0.00, blue: 0.00)
    static let obsidian         = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let voidGray         = Color(red: 0.08, green: 0.08, blue: 0.12)

    static let spatialCyan      = Color(red: 0.00, green: 0.96, blue: 1.00)
    static let signalMagenta    = Color(red: 1.00, green: 0.00, blue: 0.80)
    static let confirmGreen     = Color(red: 0.22, green: 1.00, blue: 0.08)
    static let warningAmber     = Color(red: 1.00, green: 0.75, blue: 0.00)
    static let inferenceViolet  = Color(red: 0.55, green: 0.20, blue: 1.00)

    static let glassWhite       = Color.white.opacity(0.06)
    static let glassEdge        = Color.white.opacity(0.12)
    static let dimLabel         = Color.white.opacity(0.5)
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
}
