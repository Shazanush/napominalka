import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Стиль: минимализм «Ма» + циферблат Рамса + точечные цифры + красное солнце.
enum Theme {
    static let emerald = Color(hex: 0x1B5C45)
    static let ocean = Color(hex: 0x1A4F6C)
    static let emeraldLight = Color(hex: 0x3F9A78)
    static let oceanLight = Color(hex: 0x3A82A8)
    static let ash = Color(hex: 0x8D8E89)
    static let ashLight = Color(hex: 0xC9C9C4)
    static let text = Color(hex: 0xE8E8E3)
    static let line = Color(hex: 0x262626)
    static let field = Color(hex: 0x0E0F0E)
    static let blood = Color(hex: 0xB3141F)

    static func condensed(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.condensed)
    }
}

// MARK: - Точечные цифры (как LED-дисплей)

enum DotFont {
    static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["0", "0", "1", "0", "1", "0", "0"]
    ]
    static func glyph(_ c: Character) -> [String] {
        glyphs[c] ?? ["000", "000", "000", "000", "000", "000", "000"]
    }
}

struct DotMatrixText: View {
    let text: String
    var dot: CGFloat = 5
    var color: Color = Theme.text
    var showOff = true

    private var gap: CGFloat { dot * 0.35 }
    private var step: CGFloat { dot + gap }
    private var glyphs: [[String]] { text.map { DotFont.glyph($0) } }
    private var width: CGFloat {
        let cols = glyphs.reduce(0) { $0 + ($1.first?.count ?? 0) } + max(0, glyphs.count - 1)
        return max(CGFloat(cols) * step - gap, 1)
    }
    private var height: CGFloat { 7 * step - gap }

    var body: some View {
        Canvas { ctx, _ in
            draw(in: &ctx)
        }
        .frame(width: width, height: height)
        .accessibilityLabel(Text(text))
    }

    private func draw(in ctx: inout GraphicsContext) {
        let on = GraphicsContext.Shading.color(color)
        let off = GraphicsContext.Shading.color(color.opacity(0.07))
        let st: CGFloat = step
        var x: CGFloat = 0
        for g in glyphs {
            let cols: Int = g.first?.count ?? 0
            for (r, row) in g.enumerated() {
                for (c, ch) in row.enumerated() {
                    let px: CGFloat = x + CGFloat(c) * st
                    let py: CGFloat = CGFloat(r) * st
                    let rect = CGRect(x: px, y: py, width: dot, height: dot)
                    if ch == "1" {
                        ctx.fill(Path(ellipseIn: rect), with: on)
                    } else if showOff {
                        ctx.fill(Path(ellipseIn: rect), with: off)
                    }
                }
            }
            x += CGFloat(cols + 1) * st
        }
    }
}

// MARK: - Солнце с циферблатом и бегущей секундной стрелкой

struct SunDial: View {
    var size: CGFloat = 250

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, sz in
                SunDial.draw(in: &ctx, size: sz, date: tl.date)
            }
        }
        .frame(width: size, height: size)
    }

    private static func point(_ c: CGPoint, _ angle: CGFloat, _ r: CGFloat) -> CGPoint {
        let x: CGFloat = c.x + CGFloat(cos(Double(angle))) * r
        let y: CGFloat = c.y + CGFloat(sin(Double(angle))) * r
        return CGPoint(x: x, y: y)
    }

    static func draw(in ctx: inout GraphicsContext, size sz: CGSize, date: Date) {
        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
        let R: CGFloat = min(sz.width, sz.height) / 2
        let twoPi: CGFloat = 2 * CGFloat.pi
        let quarter: CGFloat = CGFloat.pi / 2

        let sun: CGFloat = R * 0.66
        let sunRect = CGRect(x: c.x - sun, y: c.y - sun, width: sun * 2, height: sun * 2)
        ctx.fill(Path(ellipseIn: sunRect), with: .color(Theme.blood))

        let minor = Color(hex: 0x444444)
        for i in stride(from: 0, to: 60, by: 5) {
            let a: CGFloat = CGFloat(i) / 60 * twoPi - quarter
            let major: Bool = i % 15 == 0
            let len: CGFloat = major ? R * 0.1 : R * 0.06
            var p = Path()
            p.move(to: point(c, a, R - 2))
            p.addLine(to: point(c, a, R - 2 - len))
            ctx.stroke(p, with: .color(major ? Theme.ash : minor), lineWidth: major ? 2 : 1)
        }

        let secs: Double = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        let a: CGFloat = CGFloat(secs / 60) * twoPi - quarter
        var hand = Path()
        hand.move(to: point(c, a + CGFloat.pi, R * 0.1))
        hand.addLine(to: point(c, a, R * 0.9))
        ctx.stroke(hand, with: .color(Theme.emeraldLight), lineWidth: 2)
        let dot = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
        ctx.fill(Path(ellipseIn: dot), with: .color(Theme.emeraldLight))
    }
}

// MARK: - Катана и капли

/// Белая катана (картинка Katana из ресурсов).
struct KatanaView: View {
    var body: some View {
        Group {
            if let ui = UIImage(named: "Katana") {
                Image(uiImage: ui).resizable().scaledToFit()
            } else {
                Capsule().fill(Theme.text).frame(height: 4)
            }
        }
        .aspectRatio(1395.0 / 174.0, contentMode: .fit)
    }
}

/// Падающие красные капли; точки заданы долями от размера.
struct FallingDrops: View {
    let points: [CGPoint]
    var distance: CGFloat = 40
    @State private var fall = false

    var body: some View {
        GeometryReader { g in
            ForEach(0..<points.count, id: \.self) { i in
                let p: CGPoint = points[i]
                let px: CGFloat = g.size.width * p.x
                let py: CGFloat = g.size.height * p.y + (fall ? distance : 0)
                Ellipse()
                    .fill(Theme.blood)
                    .overlay(Ellipse().stroke(Color.black, lineWidth: 0.6))
                    .frame(width: 6, height: 8)
                    .position(x: px, y: py)
                    .opacity(fall ? 0 : 1)
                    .animation(.easeIn(duration: 1.9).delay(Double(i) * 0.9).repeatForever(autoreverses: false),
                               value: fall)
            }
        }
        .allowsHitTesting(false)
        .onAppear { fall = true }
    }
}
