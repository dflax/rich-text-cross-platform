import PhotosUI
import RichTextCore
import SwiftUI

/// Uploads image bytes somewhere reachable by URL and returns the object key `RichTextCore`
/// should store in the `Delta` — never a URL itself (see `ImageStore`'s own invariant: a key is
/// resolved to a URL at *read* time, so the same document works no matter which bucket, CDN, or
/// base URL a given deployment points at). Implement this against whatever object storage your
/// backend uses — see `docs/backends/` for worked examples against Postgres+S3-compatible
/// storage, Firebase Storage, and others.
public protocol RichTextImageUploading: Sendable {
    /// `imageData` is already downscaled/re-encoded by the editor before this is called — see
    /// `RichTextEditorConfiguration.imageDownscaling`.
    func upload(_ imageData: Data) async throws -> String
}

/// What this editor's default toolbar offers, and how far a host app can reshape it.
public struct RichTextEditorConfiguration: Sendable {
    /// Show the image-insert button and accept pasted/dropped images. When `false`, no
    /// `RichTextImageUploading` call is ever made, and existing image ops still decode/render —
    /// this only affects whether *new* images can be added.
    public var allowsImages: Bool = true
    /// Show the link button and accept a pasted link's `.link` attribute. When `false`, a
    /// pasted link's URL is stripped along with everything else outside the vocabulary.
    public var allowsLinks: Bool = true
    /// Long-edge pixel cap and JPEG quality applied to a picked image before upload — see
    /// `ImageDownscaling`.
    public var imageDownscaling: ImageDownscaling = .default
    /// Supply your own view instead of the default Liquid Glass toolbar — e.g. to match an
    /// existing design system, or to support an OS version below this package's iOS 26 / macOS 26
    /// minimum for the rest of your app while still editing rich text on newer devices. Receives
    /// the same `RichTextEditorModel` the default toolbar drives; see `docs/guides/custom-toolbar.md`.
    public var toolbar: (@MainActor (RichTextEditorModel) -> AnyView)?

    public init(
        allowsImages: Bool = true,
        allowsLinks: Bool = true,
        imageDownscaling: ImageDownscaling = .default,
        toolbar: (@MainActor (RichTextEditorModel) -> AnyView)? = nil
    ) {
        self.allowsImages = allowsImages
        self.allowsLinks = allowsLinks
        self.imageDownscaling = imageDownscaling
        self.toolbar = toolbar
    }

    public static let `default` = RichTextEditorConfiguration()
}

/// A rich-text editor backed by a real `UITextView` (iOS/iPadOS) or `NSTextView` (macOS) — real
/// hanging indent and non-selectable list markers via TextKit 2's `NSTextList`, not literal
/// marker characters in the buffer. This file, `RichTextEditorModel`, and `RichTextTextView` are
/// each declared twice — once per platform, in mutually-exclusive `#if canImport(UIKit)`/
/// `#if canImport(AppKit)` files — sharing the same public type names so this view's own body
/// below needs almost no platform branching itself. See `docs/ARCHITECTURE.md` for why this
/// exists instead of SwiftUI's own `TextEditor`.
///
/// `delta` is the single source of truth both directions: this view decodes it once to seed the
/// live text view, and writes back to it (debounced, and on disappear/backgrounding) as the user
/// edits — never by replacing the whole binding wholesale mid-session, which is exactly the
/// hazard that makes `TextEditor`'s own `AttributedString` binding unsafe to update from outside
/// causes. Pair with `.onChange(of: delta)` if your host needs to react to saves, e.g. to persist
/// to your backend.
@MainActor
public struct RichTextEditor: View {
    @Binding private var delta: Delta
    private let imageStore: ImageStore
    private let imageUploader: (any RichTextImageUploading)?
    private let configuration: RichTextEditorConfiguration
    /// If non-nil, a "Done" button appears in this view's own toolbar and calls this after
    /// saving synchronously. Omit it if your host provides its own dismissal chrome — but then
    /// your host is responsible for giving the debounce (~1s) a chance to fire, or triggering a
    /// save itself, before tearing this view down; see `docs/guides/saving.md`.
    private let onDone: (() -> Void)?

    public init(
        delta: Binding<Delta>,
        imageStore: ImageStore,
        imageUploader: (any RichTextImageUploading)? = nil,
        configuration: RichTextEditorConfiguration = .default,
        onDone: (() -> Void)? = nil
    ) {
        self._delta = delta
        self.imageStore = imageStore
        self.imageUploader = imageUploader
        self.configuration = configuration
        self.onDone = onDone
    }

    @State private var model: RichTextEditorModel?
    @State private var initialContent: NSAttributedString?
    @State private var isFocused = true
    @State private var isPanelOpen = false

    @State private var showingAltPrompt = false
    @State private var altDraft = ""
    @State private var pendingImage: (key: String, image: PlatformImage)?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var isUploading = false

    @State private var showingLinkSheet = false
    @State private var linkTextDraft = ""
    @State private var linkURLDraft = ""
    @State private var linkEditRange: NSRange?
    @State private var linkHasExistingURL = false
    @State private var linkValidationError: String?

    @Environment(\.scenePhase) private var scenePhase

    public var body: some View {
        Group {
            if let model, let initialContent {
                editor(model, initialContent)
            } else {
                ProgressView()
            }
        }
        .task { await load() }
        .toolbar {
            if onDone != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); onDone?() }
                }
            }
        }
        // Backstop for exits that don't go through the Done button above (swipe-back,
        // backgrounding, a host-provided dismissal path) — real bug found the hard way: relying
        // on this ALONE races a `weak var textView` against this view's own teardown, since
        // nothing else keeps the underlying `UITextView` alive. When `onDone` is provided, Done
        // saves synchronously first, while the view is still guaranteed live, closing that race
        // for the common case.
        .onDisappear { save() }
        .onChange(of: scenePhase) { _, _ in save() }
    }

    private func load() async {
        let (created, content) = await RichTextEditorModel.load(delta: delta, imageStore: imageStore)
        model = created
        initialContent = content
    }

    private func save() {
        guard let model else { return }
        model.encodeIfChanged()
        guard model.savedDelta != delta else { return }
        delta = model.savedDelta
    }

    @ViewBuilder
    private func editor(_ model: RichTextEditorModel, _ initialContent: NSAttributedString) -> some View {
        ScrollView {
            RichTextTextView(model: model, initialContent: initialContent, focused: $isFocused)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            toolbar(for: model)
                .padding(.bottom, 4)
        }
        .overlay(alignment: .top) { banners(model) }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePickedPhoto(item, model: model) }
        }
        .alert("Describe this image", isPresented: $showingAltPrompt) {
            TextField("Alt text", text: $altDraft)
            Button("Insert") { insertPendingImage(into: model) }
            Button("Cancel", role: .cancel) { pendingImage = nil }
        } message: {
            Text("Used as the accessibility label wherever this document is read.")
        }
        .sheet(isPresented: $showingLinkSheet) { linkSheet(model) }
    }

    @ViewBuilder
    private func toolbar(for model: RichTextEditorModel) -> some View {
        if let custom = configuration.toolbar {
            custom(model)
        } else {
            RichTextFormatBar(
                model: model,
                isPanelOpen: $isPanelOpen,
                showsLink: configuration.allowsLinks,
                showsPhoto: configuration.allowsImages,
                onLink: { presentLinkSheet(model) },
                onPhoto: { showingPhotoPicker = true }
            )
        }
    }

    // MARK: - Links

    private func presentLinkSheet(_ model: RichTextEditorModel) {
        let context = model.linkEditContext
        linkEditRange = context.range
        linkTextDraft = context.text
        linkURLDraft = context.url?.absoluteString ?? ""
        linkHasExistingURL = context.url != nil
        linkValidationError = nil
        showingLinkSheet = true
    }

    @ViewBuilder
    private func linkSheet(_ model: RichTextEditorModel) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link text", text: $linkTextDraft)
                    TextField("https://example.com", text: $linkURLDraft)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } footer: {
                    if let linkValidationError {
                        Text(linkValidationError).foregroundStyle(.red)
                    } else if linkEditRange == nil {
                        Text("Nothing was selected, so this inserts new linked text at the cursor.")
                    }
                }
                if linkHasExistingURL {
                    Section {
                        Button("Remove Link", role: .destructive) { removeLink(model) }
                    }
                }
            }
            .navigationTitle(linkHasExistingURL ? "Edit Link" : "Add Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingLinkSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLinkSheet(model) }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveLinkSheet(_ model: RichTextEditorModel) {
        var urlString = linkURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            linkValidationError = "Enter a URL first."
            return
        }
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString) else {
            linkValidationError = "That doesn't look like a valid URL."
            return
        }
        let trimmedText = linkTextDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        model.applyLink(text: trimmedText.isEmpty ? urlString : linkTextDraft, url: url, range: linkEditRange)
        showingLinkSheet = false
    }

    private func removeLink(_ model: RichTextEditorModel) {
        if let range = linkEditRange { model.removeLink(range: range) }
        showingLinkSheet = false
    }

    // MARK: - Image insertion

    private func handlePickedPhoto(_ item: PhotosPickerItem, model: RichTextEditorModel) async {
        defer { photoItem = nil }
        guard let imageUploader else {
            model.reportError("No image uploader configured for this editor.")
            return
        }
        isUploading = true
        defer { isUploading = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            model.reportError("Could not read the picked image.")
            return
        }
        guard let jpeg = ImageDownscaler.downscaledJPEG(from: data, configuration: configuration.imageDownscaling),
              let preview = PlatformImage(data: jpeg)
        else {
            model.reportError("Could not re-encode the picked image.")
            return
        }
        do {
            let key = try await imageUploader.upload(jpeg)
            pendingImage = (key: key, image: preview)
            altDraft = ""
            showingAltPrompt = true
        } catch {
            model.reportError("Upload failed — you need a connection to insert an image. (\(error))")
        }
    }

    private func insertPendingImage(into model: RichTextEditorModel) {
        defer { pendingImage = nil }
        guard let pendingImage else { return }
        model.insertImage(key: pendingImage.key, alt: altDraft.isEmpty ? nil : altDraft, image: pendingImage.image)
    }

    // MARK: - Banners

    @ViewBuilder
    private func banners(_ model: RichTextEditorModel) -> some View {
        VStack(spacing: 6) {
            if let failure = model.integrityFailure {
                banner(failure, tint: .red, systemImage: "exclamationmark.octagon.fill")
            }
            if let error = model.lastError {
                banner(error, tint: .orange, systemImage: "exclamationmark.triangle.fill")
            }
            if model.isDirty {
                banner("Unsaved", tint: .gray, systemImage: "circle.fill")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .animation(.default, value: model.integrityFailure)
        .onTapGesture { model.clearErrors() }
    }

    private func banner(_ text: String, tint: Color, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
    }
}
