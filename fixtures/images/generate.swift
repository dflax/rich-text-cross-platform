import AppKit
import Foundation

// Deliberately distinguishable at a glance: a side-by-side comparison against Quill, and a
// cross-platform pass, both need to tell one image from another in a screenshot.
let specs: [(key: String, label: String, color: NSColor)] = [
    ("doc-images/8f2a0c11.jpg",     "8f2a0c11\nMap of the side gate", .systemBlue),
    ("doc-images/map.jpg",          "map\nMap of the side gate",      .systemGreen),
    ("doc-images/first.jpg",        "first",                          .systemOrange),
    ("doc-images/second.jpg",       "second",                         .systemPurple),
    ("doc-images/lane-diagram.jpg", "lane-diagram\nPickup lane",      .systemRed),
]

let outDir = URL(filePath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let size = NSSize(width: 1200, height: 800)
for spec in specs {
    let image = NSImage(size: size)
    image.lockFocus()
    spec.color.setFill()
    NSRect(origin: .zero, size: size).fill()

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let text = NSAttributedString(string: spec.label, attributes: [
        .font: NSFont.systemFont(ofSize: 72, weight: .semibold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: style,
    ])
    let bounds = text.boundingRect(with: size, options: .usesLineFragmentOrigin)
    text.draw(in: NSRect(x: 0, y: (size.height - bounds.height) / 2,
                         width: size.width, height: bounds.height))
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    else { fatalError("could not encode \(spec.key)") }

    let name = spec.key.replacingOccurrences(of: "/", with: "_")
    try jpeg.write(to: outDir.appending(path: name))
    print("\(spec.key)  \(jpeg.count) bytes")
}
