// Gera o ícone do app (arte própria).
// macOS (todos os tamanhos, com margem e sombra):
//   swift scripts/make-icon.swift Apps/macOS/WindFree/Resources/Assets.xcassets/AppIcon.appiconset
// iOS/iPadOS (1024 px quadrado e opaco; o sistema arredonda os cantos):
//   swift scripts/make-icon.swift --ios Apps/iOS/WindFree/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
let iOS = arguments.contains("--ios")
let output = URL(fileURLWithPath: arguments.first { $0 != "--ios" } ?? ".")

func render(size: Int, fullBleed: Bool = false) -> Data {
    let scale = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)

    // Fundo: retângulo arredondado na grade de ícones do macOS (824 pt com margem de 100), ou o quadrado
    // inteiro no iOS (opaco, sem sombra), ampliando a arte para ocupar o espaço.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = fullBleed
        ? CGPath(rect: CGRect(x: 0, y: 0, width: 1024, height: 1024), transform: nil)
        : CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    if fullBleed {
        ctx.translateBy(x: 512, y: 512)
        ctx.scaleBy(x: 1024 / 824, y: 1024 / 824)
        ctx.translateBy(x: -512, y: -512)
    } else {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(shape)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.95, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.55, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Aparelho
    let unit = CGRect(x: 230, y: 560, width: 564, height: 190)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(CGPath(roundedRect: unit, cornerWidth: 48, cornerHeight: 48, transform: nil))
    ctx.setFillColor(NSColor(white: 0.97, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    // Saída de ar
    ctx.addPath(CGPath(roundedRect: CGRect(x: 290, y: 590, width: 444, height: 22), cornerWidth: 11,
                       cornerHeight: 11, transform: nil))
    ctx.setFillColor(NSColor(white: 0.30, alpha: 1).cgColor)
    ctx.fillPath()
    // Microfuros
    ctx.setFillColor(NSColor(white: 0.72, alpha: 1).cgColor)
    var x: CGFloat = 300
    while x < 724 {
        for row in 0..<3 {
            ctx.fillEllipse(in: CGRect(x: x, y: 650 + CGFloat(row) * 22, width: 8, height: 8))
        }
        x += 24
    }

    // Fluxo de ar
    ctx.setLineCap(.round)
    for index in 0..<5 {
        let startX = 330 + CGFloat(index) * 91
        let path = CGMutablePath()
        path.move(to: CGPoint(x: startX, y: 540))
        path.addCurve(to: CGPoint(x: startX + (startX - 512) * 0.35, y: 230),
                      control1: CGPoint(x: startX + 40, y: 440), control2: CGPoint(x: startX - 40, y: 330))
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(calibratedRed: 0.75, green: 0.92, blue: 1, alpha: 0.85 - CGFloat(abs(index - 2)) * 0.12).cgColor)
        ctx.setLineWidth(26)
        ctx.strokePath()
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    guard fullBleed else { return rep.representation(using: .png, properties: [:])! }
    // iOS: sem canal alfa.
    let target = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    target.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, target.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

if iOS {
    try render(size: 1024, fullBleed: true).write(to: output.appendingPathComponent("icon_1024.png"))
    let contents: [String: Any] = [
        "images": [["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon_1024.png"]],
        "info": ["author": "xcode", "version": 1],
    ]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: output.appendingPathComponent("Contents.json"))
    print("Ícone iOS gerado em \(output.path)")
    exit(0)
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Ícones gerados em \(output.path)")
