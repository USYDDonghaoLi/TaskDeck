import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: make_icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

let outerRect = NSRect(x: 32, y: 32, width: 960, height: 960)
let outer = NSBezierPath(roundedRect: outerRect, xRadius: 220, yRadius: 220)
NSGradient(colors: [
    NSColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1),
    NSColor(red: 0.02, green: 0.09, blue: 0.12, alpha: 1)
])!.draw(in: outer, angle: -45)

NSGraphicsContext.current?.saveGraphicsState()
outer.addClip()
NSColor(red: 0.0, green: 0.94, blue: 0.82, alpha: 0.09).setStroke()
for position in stride(from: 72, through: 952, by: 64) {
    let vertical = NSBezierPath()
    vertical.move(to: NSPoint(x: position, y: 32))
    vertical.line(to: NSPoint(x: position, y: 992))
    vertical.lineWidth = 2
    vertical.stroke()

    let horizontal = NSBezierPath()
    horizontal.move(to: NSPoint(x: 32, y: position))
    horizontal.line(to: NSPoint(x: 992, y: position))
    horizontal.lineWidth = 2
    horizontal.stroke()
}
NSGraphicsContext.current?.restoreGraphicsState()

NSColor(red: 0.0, green: 0.94, blue: 0.82, alpha: 1).setStroke()
let terminal = NSBezierPath(roundedRect: NSRect(x: 230, y: 245, width: 564, height: 534), xRadius: 82, yRadius: 82)
terminal.lineWidth = 34
terminal.stroke()

let prompt = NSBezierPath()
prompt.move(to: NSPoint(x: 354, y: 590))
prompt.line(to: NSPoint(x: 454, y: 512))
prompt.line(to: NSPoint(x: 354, y: 434))
prompt.lineWidth = 42
prompt.lineCapStyle = .round
prompt.lineJoinStyle = .round
prompt.stroke()

NSColor(red: 0.68, green: 1.0, blue: 0.28, alpha: 1).setStroke()
let cursor = NSBezierPath()
cursor.move(to: NSPoint(x: 505, y: 424))
cursor.line(to: NSPoint(x: 660, y: 424))
cursor.lineWidth = 42
cursor.lineCapStyle = .round
cursor.stroke()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Could not render icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
