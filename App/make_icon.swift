// Icône de Recomps : carré bleu nuit, flèche circulaire « recompiler » en dégradé cyan → bleu autour d'un triangle « jouer ».
// swift App/make_icon.swift <dossier.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    let cyan = CGColor(srgbRed: 0x34 / 255, green: 0xF2 / 255, blue: 0xE8 / 255, alpha: 1)
    let blue = CGColor(srgbRed: 0x37 / 255, green: 0x7B / 255, blue: 0xB6 / 255, alpha: 1)
    let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

    // Fond : carré arrondi (grille macOS : 824/1024), bleu nuit avec une lueur cyan en haut.
    let inset = s * 100 / 1024, r = s * 185 / 1024
    let bg = CGPath(roundedRect: CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), cornerWidth: r, cornerHeight: r, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.45))
    cg.addPath(bg); cg.setFillColor(CGColor(srgbRed: 0x0B / 255, green: 0x12 / 255, blue: 0x20 / 255, alpha: 1)); cg.fillPath()
    cg.restoreGState()
    cg.saveGState(); cg.addPath(bg); cg.clip()
    let glow = CGGradient(colorsSpace: rgb, colors: [CGColor(srgbRed: 0x34 / 255, green: 0xF2 / 255, blue: 0xE8 / 255, alpha: 0.22), CGColor(srgbRed: 0.04, green: 0.07, blue: 0.13, alpha: 0)] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.5, y: s * 0.86), startRadius: 0, endCenter: CGPoint(x: s * 0.5, y: s * 0.86), endRadius: s * 0.62, options: [])
    // Bord fin
    cg.addPath(bg); cg.setStrokeColor(CGColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 0.10)); cg.setLineWidth(s * 0.006); cg.strokePath()
    cg.restoreGState()

    // Flèche circulaire (anneau ouvert + pointe), remplie du dégradé.
    let c = CGPoint(x: s / 2, y: s / 2), R = s * 0.255, w = s * 0.072
    let start = CGFloat.pi * 0.62, end = CGFloat.pi * 0.62 + CGFloat.pi * 1.62
    let ring = CGMutablePath()
    ring.addArc(center: c, radius: R, startAngle: start, endAngle: end, clockwise: false)
    let stroked = ring.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let tip = CGPoint(x: c.x + R * cos(end), y: c.y + R * sin(end))
    let tan = CGPoint(x: -sin(end), y: cos(end)), nrm = CGPoint(x: cos(end), y: sin(end))
    let head = CGMutablePath(), hl = s * 0.105, hw = s * 0.085
    head.move(to: CGPoint(x: tip.x + tan.x * hl, y: tip.y + tan.y * hl))
    head.addLine(to: CGPoint(x: tip.x + nrm.x * hw - tan.x * hl * 0.15, y: tip.y + nrm.y * hw - tan.y * hl * 0.15))
    head.addLine(to: CGPoint(x: tip.x - nrm.x * hw - tan.x * hl * 0.15, y: tip.y - nrm.y * hw - tan.y * hl * 0.15))
    head.closeSubpath()
    let brand = CGGradient(colorsSpace: rgb, colors: [cyan, blue] as CFArray, locations: [0, 1])!
    for p in [stroked, head] as [CGPath] {
        cg.saveGState(); cg.addPath(p); cg.clip()
        cg.drawLinearGradient(brand, start: CGPoint(x: 0, y: s * 0.78), end: CGPoint(x: 0, y: s * 0.22), options: [])
        cg.restoreGState()
    }

    // Triangle « jouer », blanc givre, légèrement décalé à droite pour paraître centré.
    let t = CGMutablePath(), tr = s * 0.105
    t.move(to: CGPoint(x: c.x + tr * 1.05, y: c.y))
    t.addLine(to: CGPoint(x: c.x - tr * 0.62, y: c.y + tr))
    t.addLine(to: CGPoint(x: c.x - tr * 0.62, y: c.y - tr))
    t.closeSubpath()
    let rounded = t.copy(strokingWithWidth: s * 0.03, lineCap: .round, lineJoin: .round, miterLimit: 10)
    cg.setFillColor(CGColor(srgbRed: 0xF4 / 255, green: 0xF8 / 255, blue: 0xFC / 255, alpha: 1))
    cg.addPath(t); cg.fillPath()
    cg.addPath(rounded); cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
