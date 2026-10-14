import SwiftUI

/// Desenho do aparelho e do fluxo de ar, conforme o estado real.
/// A animação só roda com o painel visível, o ar ligado e sem "Reduzir movimento".
struct AirflowView: View {
    let isOn: Bool
    let mode: String?
    let fan: String?
    let oscillation: String?
    let windFree: Bool
    let animate: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let running = animate && isOn && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
            Canvas { graphics, size in
                draw(in: &graphics, size: size, time: running ? context.date.timeIntervalSinceReferenceDate : 0)
            }
        }
    }

    private var speed: Double {
        switch fan {
        case "low", "quiet": 0.55
        case "medium": 0.85
        case "high": 1.2
        case "turbo": 1.6
        default: 0.9
        }
    }

    private func draw(in graphics: inout GraphicsContext, size: CGSize, time: Double) {
        let dark = colorScheme == .dark
        let unitWidth = min(size.width * 0.66, 220)
        let unit = CGRect(x: (size.width - unitWidth) / 2, y: 4, width: unitWidth, height: 32)
        let color = Labels.modeColor(mode)

        // Fluxo de ar
        if isOn {
            let top = unit.maxY + 1
            let height = size.height - top
            if windFree {
                drawMicroFlow(in: &graphics, unit: unit, top: top, height: height, time: time, color: color)
            } else {
                drawStrands(in: &graphics, unit: unit, top: top, height: height, time: time, color: color)
            }
        }

        // Corpo do aparelho
        var body = graphics
        body.opacity = isOn ? 1 : 0.6
        let shape = Path(roundedRect: unit, cornerRadius: 9)
        body.addFilter(.shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: 4, y: 2))
        body.fill(shape, with: .linearGradient(
            Gradient(colors: dark ? [Color(white: 0.92), Color(white: 0.78)] : [Color.white, Color(white: 0.9)]),
            startPoint: CGPoint(x: unit.midX, y: unit.minY), endPoint: CGPoint(x: unit.midX, y: unit.maxY)
        ))
        graphics.opacity = isOn ? 1 : 0.6
        graphics.stroke(shape, with: .color(.black.opacity(0.08)), lineWidth: 0.5)

        // Saída de ar: aberta normalmente, fechada no WindFree (com microfuros).
        let slot = CGRect(x: unit.minX + 14, y: unit.maxY - 9, width: unit.width - 28, height: 4)
        if windFree, isOn {
            graphics.fill(Path(roundedRect: slot, cornerRadius: 2), with: .color(Color(white: 0.82)))
            var x = unit.minX + 18
            while x < unit.maxX - 18 {
                for row in 0..<3 {
                    let dot = CGRect(x: x, y: unit.minY + 8 + CGFloat(row) * 4, width: 1.2, height: 1.2)
                    graphics.fill(Path(ellipseIn: dot), with: .color(.black.opacity(0.18)))
                }
                x += 4
            }
        } else {
            graphics.fill(Path(roundedRect: slot, cornerRadius: 2),
                          with: .color(Color(white: isOn ? 0.25 : 0.55)))
        }
        // Indicador do modo
        let led = CGRect(x: unit.maxX - 16, y: unit.minY + 7, width: 5, height: 5)
        graphics.fill(Path(ellipseIn: led), with: .color(isOn ? color : Color(white: 0.7)))
        graphics.opacity = 1
    }

    private func drawStrands(in graphics: inout GraphicsContext, unit: CGRect, top: CGFloat, height: CGFloat,
                             time: Double, color: Color)
    {
        let strands = 9
        let swingVertical = oscillation == "vertical" || oscillation == "all"
        let swingHorizontal = oscillation == "horizontal" || oscillation == "all"
        let spread = swingVertical ? 0.35 + 0.25 * sin(time * 0.9) : 0.35
        let sway = swingHorizontal ? CGFloat(sin(time * 0.7)) * 22 : 0
        let usable = unit.width - 40
        for index in 0..<strands {
            let fraction = Double(index) / Double(strands - 1)
            let startX = unit.minX + 20 + usable * fraction
            var path = Path()
            path.move(to: CGPoint(x: startX, y: top))
            var y: CGFloat = 0
            while y <= height {
                let progress = y / height
                let fan = (startX - unit.midX) * CGFloat(spread) * progress
                let wave = CGFloat(sin(Double(y) * 0.09 - time * speed * 3 + Double(index) * 1.7)) * 2.5 * progress
                path.addLine(to: CGPoint(x: startX + fan + wave + sway * progress, y: top + y))
                y += 3
            }
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                startPoint: CGPoint(x: startX, y: top), endPoint: CGPoint(x: startX, y: top + height)
            )
            let phase = CGFloat(time * speed * 38 + Double(index) * 7)
            graphics.stroke(path, with: shading,
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [7, 9], dashPhase: -phase))
        }
    }

    private func drawMicroFlow(in graphics: inout GraphicsContext, unit: CGRect, top: CGFloat, height: CGFloat,
                               time: Double, color: Color)
    {
        let particles = 42
        for index in 0..<particles {
            let seed = Double(index)
            let x = unit.minX + 16 + (unit.width - 32) * CGFloat(fract(sin(seed * 12.9898) * 43758.5453))
            let offset = fract(seed * 0.618 + time * 0.12 * speed)
            let y = top + CGFloat(offset) * height
            let drift = CGFloat(sin(time * 0.8 + seed)) * 3
            let alpha = 0.5 * (1 - offset)
            let dot = CGRect(x: x + drift, y: y, width: 2, height: 2)
            graphics.fill(Path(ellipseIn: dot), with: .color(color.opacity(alpha)))
        }
    }

    private func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}
