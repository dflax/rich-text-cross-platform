import RichTextCore
@testable import RichTextEditor
import Testing
import UIKit

/// Exercises `RichTextEditorModel` against a real, attached `UITextView` — the model reads and
/// writes through `textView.textStorage` directly rather than holding its own copy (see the
/// model's own doc comment), so a test double standing in for `UITextView` would not actually
/// exercise the thing that matters. Running on iOS Simulator, not plain `swift test`, is what
/// makes a real `UITextView` available at all — see README.md's Building & Testing section.
@Suite("RichTextEditorModel")
@MainActor
struct RichTextEditorModelTests {

    private func makeModel(_ text: String = "Hello\n") async -> (RichTextEditorModel, UITextView) {
        let delta = Delta(ops: [.text(text)])
        let store = try! ImageStore(
            directory: URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString),
            fetcher: LocalDirectoryImageFetcher(directory: URL(filePath: NSTemporaryDirectory()))
        )
        let (model, content) = await RichTextEditorModel.load(delta: delta, imageStore: store)
        let textView = UITextView()
        textView.attributedText = content
        model.attach(textView)
        return (model, textView)
    }

    @Test("setLineStyle toggles bulleted on, then back to body when applied a second time")
    func setLineStyleToggles() async {
        let (model, textView) = await makeModel()
        textView.selectedRange = NSRange(location: 0, length: 5)

        model.setLineStyle(.bullet)
        #expect(model.currentLineStyle == .bullet)

        model.setLineStyle(.bullet)
        #expect(model.currentLineStyle == .body, "Applying the already-active style must revert to Body, matching the toolbar's own mutual-exclusivity rule.")
    }

    @Test("toggleBold flips the font trait at the cursor")
    func toggleBoldFlipsTrait() async {
        let (model, textView) = await makeModel()
        textView.selectedRange = NSRange(location: 0, length: 5)

        #expect(!model.isBoldActive)
        model.toggleBold()
        #expect(model.isBoldActive)
        model.toggleBold()
        #expect(!model.isBoldActive)
    }

    @Test("applyLink with no prior selection inserts new linked text at the cursor")
    func applyLinkInsertsAtCursor() async {
        let (model, textView) = await makeModel("Hello \n")
        textView.selectedRange = NSRange(location: 6, length: 0)

        let context = model.linkEditContext
        #expect(context.range == nil, "No selection and no existing link means insert-at-cursor.")

        model.applyLink(text: "world", url: URL(string: "https://example.com")!, range: context.range)
        #expect(textView.textStorage.string.hasPrefix("Hello world"))

        let linkURL = textView.textStorage.attribute(.link, at: 6, effectiveRange: nil) as? URL
        #expect(linkURL == URL(string: "https://example.com"))
    }

    @Test("insertImage tags the attachment with a resolvable richTextImageInfo")
    func insertImageTagsAttachment() async {
        let (model, textView) = await makeModel()
        textView.selectedRange = NSRange(location: 0, length: 0)

        model.insertImage(key: "doc-images/test.jpg", alt: "A test image", image: nil)

        var range = NSRange(location: 0, length: 0)
        let info = textView.textStorage.attribute(.richTextImageInfo, at: 0, longestEffectiveRange: &range, in: NSRange(location: 0, length: textView.textStorage.length)) as? RichImageAttachmentInfo
        #expect(info?.key == "doc-images/test.jpg")
        #expect(info?.alt == "A test image")
    }
}
