import RichTextCore
import Foundation

/// One in-memory document. A real app would load/save these through whatever backend it uses
/// (see docs/backends/) — this demo only needs enough persistence to make opening several
/// documents in their own floating windows worth demonstrating.
struct Document: Identifiable {
    let id: UUID
    var title: String
    var delta: Delta

    init(id: UUID = UUID(), title: String, delta: Delta) {
        self.id = id
        self.title = title
        self.delta = delta
    }
}

extension Document {
    /// A handful of starting documents so the gallery isn't empty on first launch, and so
    /// opening two or three of them side by side actually demonstrates something.
    static var samples: [Document] {
        [
            Document(
                title: "Meeting notes",
                delta: Delta(ops: [
                    .text("Meeting notes"),
                    .text("\n", ["header": .int(1)]),
                    .text("Discuss the "),
                    .text("spatial", ["italic": .bool(true)]),
                    .text(" layout for the new editor.\n"),
                    .text("Follow up with design"),
                    .text("\n", ["list": .string("bullet")]),
                    .text("Ship the ornament toolbar"),
                    .text("\n", ["list": .string("bullet")]),
                ])
            ),
            Document(
                title: "Recipe: cold brew",
                delta: Delta(ops: [
                    .text("Cold brew"),
                    .text("\n", ["header": .int(1)]),
                    .text("Coarse grind, "),
                    .text("1:8", ["bold": .bool(true)]),
                    .text(" ratio, steep 18 hours.\n"),
                ])
            ),
            Document(
                title: "Untitled",
                delta: Delta(ops: [.text("\n")])
            ),
        ]
    }
}
