import SwiftUI

/// A PATH route as the rider knows it, identified from the feed's line color.
struct PathLine: Hashable {
    let name: String
    /// Card fill. Combined overnight service uses the line it's standing in for.
    let color: Color
    /// Second color for combined services, drawn as a stripe on the card.
    let accent: Color?
    let towards: String

    init(feedColors raw: String, headsign: String) {
        let hexes = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        switch hexes.first ?? "" {
        case "D93A30": name = "NWK–WTC"
        case "65C100": name = "HOB–WTC"
        case "FF9900": name = "JSQ–33"
        case "4D92FB": name = hexes.count > 1 ? "JSQ–33 via HOB" : "HOB–33"
        default: name = "PATH"
        }
        // The overnight combined line is the JSQ–33 service rerouted; fill it yellow.
        let (fill, ink) = RGB(hex: hexes.last ?? "65C100").legibleCard()
        color = fill.color
        self.ink = ink.color
        accent = hexes.count > 1 ? RGB(hex: hexes[0]).color : nil
        towards = headsign
            .replacingOccurrences(of: "World Trade Center", with: "World Trade Ctr")
            .replacingOccurrences(of: " via Hoboken", with: "")
    }

    /// Card text: whichever of near-black or white reads better on the fill.
    let ink: Color
}

/// Plain sRGB components, so contrast math doesn't round-trip through UIColor.
struct RGB: Equatable {
    var r, g, b: Double

    static let white = RGB(r: 1, g: 1, b: 1)
    static let nearBlack = RGB(r: 0.07, g: 0.07, b: 0.07)

    init(r: Double, g: Double, b: Double) { (self.r, self.g, self.b) = (r, g, b) }

    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0x65C100
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The line color as a card fill plus its text color, meeting WCAG AA (4.5:1).
    /// Colors that can't reach it with either ink (PATH red sits right at the
    /// crossover) are darkened just enough for white text to pass, the way
    /// transit apps tone down bright route colors behind white labels.
    func legibleCard() -> (fill: RGB, ink: RGB) {
        let best = contrast(with: .white) >= contrast(with: .nearBlack) ? RGB.white : .nearBlack
        if contrast(with: best) >= 4.5 { return (self, best) }
        var fill = self
        while fill.contrast(with: .white) < 4.5 {
            fill = RGB(r: fill.r * 0.97, g: fill.g * 0.97, b: fill.b * 0.97)
        }
        return (fill, .white)
    }
}

enum Theme {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let walk = Color(red: 0.24, green: 0.55, blue: 1.0)
    static let home = Color(red: 0.40, green: 0.76, blue: 0.0)
}

/// Transit's "this time is live" mark: a dot with two broadcast arcs.
struct RealtimeMark: View {
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let origin = CGPoint(x: s * 0.2, y: s * 0.8)
            ctx.fill(Path(ellipseIn: CGRect(x: origin.x - s * 0.1, y: origin.y - s * 0.1, width: s * 0.2, height: s * 0.2)),
                     with: .color(color))
            for (i, r) in [s * 0.42, s * 0.72].enumerated() {
                var arc = Path()
                arc.addArc(center: origin, radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                ctx.stroke(arc, with: .color(color.opacity(i == 0 ? 1 : 0.7)),
                           style: StrokeStyle(lineWidth: s * 0.14, lineCap: .round))
            }
        }
        .accessibilityLabel("Live")
    }
}
