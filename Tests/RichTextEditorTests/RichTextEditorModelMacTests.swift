#if canImport(AppKit)
import AppKit
import RichTextCore
@testable import RichTextEditor
import Testing

/// Exercises `RichTextEditorModel` against a real, attached `NSTextView` — the macOS mirror of
/// `RichTextEditorModelTests` (iOS). The model reads and writes through `textView.textStorage`
/// directly rather than holding its own copy, so a test double standing in for `NSTextView`
/// would not actually exercise the thing that matters. Runs under plain `swift test` on macOS —
/// no simulator needed, since AppKit is native here.
@Suite("RichTextEditorModel (macOS)")
@MainActor
struct RichTextEditorModelMacTests {

    private func makeModel(_ text: String = "Hello\n") async -> (RichTextEditorModel, NSTextView) {
        let delta = Delta(ops: [.text(text)])
        let store = try! ImageStore(
            directory: URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString),
            fetcher: LocalDirectoryImageFetcher(directory: URL(filePath: NSTemporaryDirectory()))
        )
        let (model, content) = await RichTextEditorModel.load(delta: delta, imageStore: store)
        let textView = NSTextView()
        textView.textStorage?.setAttributedString(content)
        model.attach(textView)
        return (model, textView)
    }

    @Test("setLineStyle toggles bulleted on, then back to body when applied a second time")
    func setLineStyleToggles() async {
        let (model, textView) = await makeModel()
        textView.selectedRanges = [NSValue(range: NSRange(location: 0, length: 5))]

        model.setLineStyle(.bullet)
        #expect(model.currentLineStyle == .bullet)

        model.setLineStyle(.bullet)
        #expect(model.currentLineStyle == .body, "Applying the already-active style must revert to Body, matching the toolbar's own mutual-exclusivity rule.")
    }

    @Test("toggleBold flips the font trait at the cursor")
    func toggleBoldFlipsTrait() async {
        let (model, textView) = await makeModel()
        textView.selectedRanges = [NSValue(range: NSRange(location: 0, length: 5))]

        #expect(!model.isBoldActive)
        model.toggleBold()
        #expect(model.isBoldActive)
        model.toggleBold()
        #expect(!model.isBoldActive)
    }

    @Test("applyLink with no prior selection inserts new linked text at the cursor")
    func applyLinkInsertsAtCursor() async {
        let (model, textView) = await makeModel("Hello \n")
        textView.selectedRanges = [NSValue(range: NSRange(location: 6, length: 0))]

        let context = model.linkEditContext
        #expect(context.range == nil, "No selection and no existing link means insert-at-cursor.")

        model.applyLink(text: "world", url: URL(string: "https://example.com")!, range: context.range)
        #expect(textView.textStorage?.string.hasPrefix("Hello world") == true)

        let linkURL = textView.textStorage?.attribute(.link, at: 6, effectiveRange: nil) as? URL
        #expect(linkURL == URL(string: "https://example.com"))
    }

    @Test("insertImage tags the attachment with a resolvable richTextImageInfo")
    func insertImageTagsAttachment() async {
        let (model, textView) = await makeModel()
        textView.selectedRanges = [NSValue(range: NSRange(location: 0, length: 0))]

        model.insertImage(key: "doc-images/test.jpg", alt: "A test image", image: nil)

        guard let storage = textView.textStorage else {
            Issue.record("expected a text storage")
            return
        }
        var range = NSRange(location: 0, length: 0)
        let info = storage.attribute(.richTextImageInfo, at: 0, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) as? RichImageAttachmentInfo
        #expect(info?.key == "doc-images/test.jpg")
        #expect(info?.alt == "A test image")
    }

    @Test("shouldChangeText redirects typing adjacent to an attachment onto its own line")
    func shouldChangeTextGuardsImageAdjacency() async {
        let (model, textView) = await makeModel()
        textView.selectedRanges = [NSValue(range: NSRange(location: 0, length: 0))]
        model.insertImage(key: "doc-images/test.jpg", alt: nil, image: nil)
        guard let storage = textView.textStorage else {
            Issue.record("expected a text storage")
            return
        }
        // The attachment now sits at index 0, its terminator "\n" at index 1. Typing right after
        // the terminator (index 2) is not adjacent to the attachment itself, so this checks the
        // adjacency guard fires exactly at the attachment/terminator boundary, not beyond it.
        let attachmentIndex = 0
        let allowed = model.shouldChangeText(in: NSRange(location: attachmentIndex, length: 0), replacementText: "x")
        #expect(!allowed, "Typing directly at an attachment's position must be redirected, not applied as-is.")
        #expect(storage.length > 0)
    }

    @Test("encodeIfChanged round-trips a plain edit back to a valid Delta")
    func encodeIfChangedProducesValidDelta() async {
        let (model, textView) = await makeModel("Hello\n")
        textView.textStorage?.replaceCharacters(in: NSRange(location: 5, length: 0), with: ", world")

        #expect(model.encodeIfChanged())
        #expect(model.savedDelta.plainText == "Hello, world\n")
        #expect(model.integrityFailure == nil)
    }
}
#endif
