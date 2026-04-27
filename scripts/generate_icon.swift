#!/usr/bin/env swift
import AppKit
import CoreGraphics

let SIZE: CGFloat = 1024

func makeIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: SIZE, height: SIZE))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return img }

    // ── Background gradient (violet → bleu électrique) ──────────────────────
    let colors = [
        CGColor(red: 0.35, green: 0.10, blue: 0.82, alpha: 1),   // violet-700
        CGColor(red: 0.09, green: 0.39, blue: 0.95, alpha: 1)    // blue-600
    ] as CFArray
    let locs: [CGFloat] = [0, 1]
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locs)!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: SIZE),
        end: CGPoint(x: SIZE, y: 0),
        options: []
    )

    // ── Enveloppe (centrée) ──────────────────────────────────────────────────
    let ew: CGFloat = 640, eh: CGFloat = 440
    let ex = (SIZE - ew) / 2, ey = (SIZE - eh) / 2

    // Ombre douce
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))

    // Corps blanc avec légères coins arrondis
    let bodyPath = CGPath(roundedRect: CGRect(x: ex, y: ey, width: ew, height: eh),
                          cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 1.0, alpha: 1))
    ctx.addPath(bodyPath)
    ctx.fillPath()

    // Retirer ombre pour les détails
    ctx.setShadow(offset: .zero, blur: 0, color: CGColor(red: 0,green: 0,blue: 0,alpha: 0))

    // Clip dans le corps de l'enveloppe
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Rabat supérieur (triangle inversé)
    let flapTip = CGPoint(x: SIZE / 2, y: ey + eh * 0.40)
    ctx.setFillColor(CGColor(red: 0.90, green: 0.91, blue: 0.98, alpha: 1))
    ctx.move(to: CGPoint(x: ex, y: ey + eh))
    ctx.addLine(to: CGPoint(x: ex, y: ey + eh))
    ctx.move(to: CGPoint(x: ex, y: ey + eh))   // coin bas-gauche

    // V-flap : lignes diagonales du haut vers le centre
    let flapPath = CGMutablePath()
    flapPath.move(to: CGPoint(x: ex, y: ey + eh))        // bas-gauche
    flapPath.addLine(to: CGPoint(x: ex + ew, y: ey + eh)) // bas-droit
    flapPath.addLine(to: flapTip)                          // pointe du rabat
    flapPath.closeSubpath()
    ctx.addPath(flapPath)
    ctx.fillPath()

    // Lignes de pli (diagonales haut-gauche et haut-droit vers coin bas)
    ctx.setStrokeColor(CGColor(red: 0.75, green: 0.77, blue: 0.92, alpha: 1))
    ctx.setLineWidth(2)

    // Diagonale haut-gauche → coin bas-droit
    ctx.move(to: CGPoint(x: ex, y: ey + eh))
    ctx.addLine(to: CGPoint(x: SIZE / 2, y: ey + eh * 0.58))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: ex + ew, y: ey + eh))
    ctx.addLine(to: CGPoint(x: SIZE / 2, y: ey + eh * 0.58))
    ctx.strokePath()

    ctx.restoreGState()

    // Bordure enveloppe
    ctx.setStrokeColor(CGColor(red: 0.82, green: 0.84, blue: 0.96, alpha: 1))
    ctx.setLineWidth(2.5)
    ctx.addPath(bodyPath)
    ctx.strokePath()

    // ── Sparkles IA (étoiles dorées) ────────────────────────────────────────
    let sparkles: [(CGFloat, CGFloat, CGFloat)] = [
        (ex + ew - 68,  ey + eh + 80, 22),   // grande, coin bas-droit hors enveloppe
        (ex + ew + 28,  ey + eh - 40, 14),   // petite
        (ex + ew - 20,  ey + eh + 40, 10),   // minuscule
    ]

    for (sx, sy, sr) in sparkles {
        drawSparkle(ctx: ctx, cx: sx, cy: sy, r: sr)
    }

    img.unlockFocus()
    return img
}

func drawSparkle(ctx: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat) {
    // Étoile à 4 branches
    ctx.setFillColor(CGColor(red: 0.98, green: 0.84, blue: 0.22, alpha: 1)) // amber
    ctx.setShadow(offset: .zero, blur: r * 0.6,
                  color: CGColor(red: 0.98, green: 0.84, blue: 0.22, alpha: 0.7))

    let path = CGMutablePath()
    let inner = r * 0.3
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4
        let rad = i % 2 == 0 ? r : inner
        let px = cx + rad * cos(angle)
        let py = cy + rad * sin(angle)
        if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
        else { path.addLine(to: CGPoint(x: px, y: py)) }
    }
    path.closeSubpath()
    ctx.addPath(path)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: CGColor(red:0,green:0,blue:0,alpha:0))
}

// ── Export ──────────────────────────────────────────────────────────────────
let icon = makeIcon()
guard let tiff = icon.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Erreur génération PNG")
    exit(1)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/gmac_icon_1024.png"
try! png.write(to: URL(fileURLWithPath: outPath))
print("✓ Icône générée : \(outPath)")
