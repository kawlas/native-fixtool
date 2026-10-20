// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.10, green: 0.29, blue: 0.75, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 206, yRadius: 206).fill()
NSColor(calibratedRed: 0.97, green: 0.98, blue: 1, alpha: 1).setStroke()
let arch = NSBezierPath()
arch.lineWidth = 58
arch.lineCapStyle = .round
arch.move(to: NSPoint(x: 254, y: 370))
arch.line(to: NSPoint(x: 254, y: 540))
arch.curve(to: NSPoint(x: 770, y: 540), controlPoint1: NSPoint(x: 254, y: 850), controlPoint2: NSPoint(x: 770, y: 850))
arch.line(to: NSPoint(x: 770, y: 370))
arch.stroke()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 171, y: 238, width: 682, height: 160), xRadius: 48, yRadius: 48).fill()
NSColor(calibratedRed: 0.10, green: 0.29, blue: 0.75, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 717, y: 296, width: 39, height: 39)).fill()
image.unlockFocus()
let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: CommandLine.arguments[1]))
