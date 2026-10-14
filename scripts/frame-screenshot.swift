// Prepara capturas para o README: reduz a largura, arredonda os cantos e adiciona margem com sombra suave
// sobre fundo transparente.
// Uso: swift scripts/frame-screenshot.swift entrada.png saida.png <largura> <raio> [sombra: 1|0]
//   largura e raio em pixels da imagem final.
import AppKit

let args = CommandLine.arguments
guard args.count >= 5, let source = NSImage(contentsOfFile: args[1]),
      let width = Double(args[3]), let radius = Double(args[4])
else {
    FileHandle.standardError.write(Data("uso: entrada saida largura raio [sombra]\n".utf8))
    exit(1)
}
let shadow = args.count < 6 || args[5] != "0"

let sourceRep = source.representations.first!
let aspect = Double(sourceRep.pixelsHigh) / Double(sourceRep.pixelsWide)
let content = CGSize(width: width, height: (width * aspect).rounded())
let padding = shadow ? (width * 0.06).rounded() : 0
let canvas = CGSize(width: content.width + padding * 2, height: content.height + padding * 2)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext
context.interpolationQuality = .high

let frame = CGRect(x: padding, y: padding, width: content.width, height: content.height)
let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
if shadow {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -padding * 0.25), blur: padding * 0.7,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()
}
context.addPath(shape)
context.clip()
context.draw(sourceRep.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: frame)
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
