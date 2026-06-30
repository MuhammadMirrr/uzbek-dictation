// DMG fon rasmini chizadi (oddiy, chiroyli): gradient + nom + "Applications'ga torting" o'qi.
// Ishlatish:  swift scripts/make_dmg_bg.swift assets/dmg-bg.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-bg.png"
let W = 600, H = 400
let scale = 2                                  // retina @2x
let pxW = W * scale, pxH = H * scale

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let r = NSRect(x: 0, y: 0, width: W, height: H)

// Fon — yumshoq gradient (to'q ko'kdan binafshaga)
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.22, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.14, blue: 0.30, alpha: 1),
])!
grad.draw(in: r, angle: -60)

// Sarlavha
let title = "RubaiSTT Diktovka"
let tStyle = NSMutableParagraphStyle(); tStyle.alignment = .center
title.draw(in: NSRect(x: 0, y: H - 70, width: W, height: 36), withAttributes: [
    .font: NSFont.systemFont(ofSize: 26, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: tStyle,
])

let sub = "O'rnatish uchun ilovani Applications papkasiga torting"
sub.draw(in: NSRect(x: 0, y: H - 98, width: W, height: 20), withAttributes: [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(white: 1, alpha: 0.7),
    .paragraphStyle: tStyle,
])

// O'q (ilova → Applications), ikonalar markazi y≈170 (pastdan)
let arrow = NSBezierPath()
let ay: CGFloat = 200
arrow.move(to: NSPoint(x: 250, y: ay))
arrow.line(to: NSPoint(x: 350, y: ay))
NSColor(white: 1, alpha: 0.55).setStroke()
arrow.lineWidth = 4
arrow.stroke()
// o'q uchi
let head = NSBezierPath()
head.move(to: NSPoint(x: 350, y: ay))
head.line(to: NSPoint(x: 336, y: ay + 9))
head.line(to: NSPoint(x: 336, y: ay - 9))
head.close()
NSColor(white: 1, alpha: 0.55).setFill()
head.fill()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try data.write(to: URL(fileURLWithPath: out)); print("yozildi: \(out)") }
catch { FileHandle.standardError.write("xato: \(error)\n".data(using: .utf8)!); exit(1) }
