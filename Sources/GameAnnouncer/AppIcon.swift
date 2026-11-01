import AppKit

/// The app icon, drawn in code so there's one source for both the Dock icon of unbundled
/// builds (`swift run`) and the .icns that scripts/make-app.sh puts in GameAnnouncer.app.
///
/// A football on a gridiron-green squircle, with announcer sound waves coming off it.
/// Geometry follows Apple's macOS icon grid: an 824-point body centered on a 1024 canvas.
enum AppIcon {
    static func image() -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
            draw(in: rect)
            return true
        }
    }

    /// Writes a 1024×1024 PNG, independent of the screen's scale factor.
    static func writePNG(to url: URL) throws {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        rep.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }

    static func draw(in rect: NSRect) {
        let s = rect.width / 1024
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: rect.minX + x * s, y: rect.minY + y * s, width: w * s, height: h * s)
        }

        // Body with a soft drop shadow.
        let body = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
        shadow.shadowBlurRadius = 28 * s
        shadow.set()
        NSColor(srgbRed: 0.10, green: 0.42, blue: 0.21, alpha: 1).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.22, green: 0.66, blue: 0.33, alpha: 1),
            NSColor(srgbRed: 0.07, green: 0.36, blue: 0.17, alpha: 1),
        ])?.draw(in: body, angle: -90)

        // Yard lines with hash marks.
        NSColor.white.withAlphaComponent(0.16).setFill()
        for i in 0..<6 {
            let y = 160 + CGFloat(i) * 140
            NSBezierPath(rect: r(100, y, 824, 10)).fill()
            for x in stride(from: CGFloat(330), through: 690, by: 360) {
                NSBezierPath(rect: r(x, y + 60, 6, 30)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        drawFootball(center: CGPoint(x: rect.minX + 455 * s, y: rect.minY + 455 * s), scale: s)
        drawSoundWaves(center: CGPoint(x: rect.minX + 585 * s, y: rect.minY + 585 * s), scale: s)
    }

    private static func drawFootball(center: CGPoint, scale s: CGFloat) {
        let w: CGFloat = 520 * s, h: CGFloat = 300 * s
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: 35)

        // Pointed-ellipse football outline around the origin.
        let ball = NSBezierPath()
        ball.move(to: CGPoint(x: -w / 2, y: 0))
        // Control points near the middle keep the tips pointed (about 75°), like a real ball.
        ball.curve(to: CGPoint(x: w / 2, y: 0),
                   controlPoint1: CGPoint(x: -w * 0.06, y: h * 0.66), controlPoint2: CGPoint(x: w * 0.06, y: h * 0.66))
        ball.curve(to: CGPoint(x: -w / 2, y: 0),
                   controlPoint1: CGPoint(x: w * 0.06, y: -h * 0.66), controlPoint2: CGPoint(x: -w * 0.06, y: -h * 0.66))
        ball.close()
        ball.transform(using: transform as AffineTransform)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.shadowBlurRadius = 20 * s
        shadow.set()
        NSColor(srgbRed: 0.45, green: 0.22, blue: 0.09, alpha: 1).setFill()
        ball.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        ball.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.68, green: 0.36, blue: 0.16, alpha: 1),
            NSColor(srgbRed: 0.38, green: 0.17, blue: 0.06, alpha: 1),
        ])?.draw(in: ball, angle: -55)

        // White stripes near each tip.
        func local(_ build: (NSBezierPath) -> Void) -> NSBezierPath {
            let p = NSBezierPath()
            build(p)
            p.transform(using: transform as AffineTransform)
            return p
        }
        NSColor.white.setFill()
        for x in [-w * 0.33, w * 0.29] {
            local { $0.appendRect(NSRect(x: x, y: -h, width: 0.04 * w, height: 2 * h)) }.fill()
        }

        // Laces: one long stitch line and four cross stitches.
        NSColor.white.setStroke()
        let laces = local {
            $0.move(to: CGPoint(x: -w * 0.17, y: h * 0.02))
            $0.line(to: CGPoint(x: w * 0.17, y: h * 0.02))
            for i in 0..<5 {
                let x = -w * 0.14 + CGFloat(i) * w * 0.07
                $0.move(to: CGPoint(x: x, y: -h * 0.09))
                $0.line(to: CGPoint(x: x, y: h * 0.13))
            }
        }
        laces.lineWidth = 16 * s
        laces.lineCapStyle = .round
        laces.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Three arcs off the football's upper right: the announcer.
    private static func drawSoundWaves(center: CGPoint, scale s: CGFloat) {
        for (i, radius) in [CGFloat(130), 195, 260].enumerated() {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius * s, startAngle: 5, endAngle: 85)
            arc.lineWidth = 36 * s
            arc.lineCapStyle = .round
            NSColor.white.withAlphaComponent(1 - CGFloat(i) * 0.22).setStroke()
            arc.stroke()
        }
    }
}
