import SwiftUI

/// The default toolbar: lists/link/photo live on a floating glass bar (docked above the keyboard
/// on iOS/iPadOS, above the text on macOS); paragraph style and character formatting live behind
/// `Aa`. Sized to sit close to Apple Notes' own bar (48pt bar height, 44pt buttons, 22pt glyphs)
/// rather than guessed. Pure SwiftUI — no `UIKit`/`AppKit` import — so one implementation serves
/// both platforms, driven by the platform-specific `RichTextEditorModel`.
///
/// Uses the real Liquid Glass API (`glassEffect`/`GlassEffectContainer`), not an approximation —
/// this package's deployment target is iOS 26 / macOS 26, the same OS release that introduced
/// it. Supply your own view instead of this one via `RichTextEditorConfiguration.toolbar` if
/// you'd rather not take the Liquid Glass look, or need to support an earlier OS for the rest of
/// your app.
///
/// visionOS carries its own native materials system rather than opting into Liquid Glass the way
/// iOS/macOS 26 do — `GlassEffectContainer`/`.glassEffect(in:)` are marked
/// `@available(visionOS, unavailable)`. The `#if os(visionOS)` branches below swap in
/// `.glassBackgroundEffect(in:)` and a plain `Group` instead, verified to compile against the
/// real visionOS SDK (see `docs/visionos.md`). On visionOS this bar is also placed in an
/// `.ornament` rather than docked to the content via `.safeAreaInset` — see
/// `RichTextEditor.swift`'s `editor(_:_:)` and `docs/ARCHITECTURE.md`'s visionOS section.
struct RichTextFormatBar: View {
    let model: RichTextEditorModel
    @Binding var isPanelOpen: Bool
    var showsLink: Bool = true
    var showsPhoto: Bool = true
    let onLink: () -> Void
    let onPhoto: () -> Void

    var body: some View {
        #if os(visionOS)
        Group {
            VStack(spacing: 10) {
                if isPanelOpen {
                    formatPanel
                        .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
                }
                bar
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isPanelOpen)
        #else
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 10) {
                if isPanelOpen {
                    formatPanel
                        .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
                }
                bar
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isPanelOpen)
        #endif
    }

    // MARK: - The always-visible bar

    private var bar: some View {
        // Evenly spaced across the whole bar (each button takes an equal share via
        // `.frame(maxWidth: .infinity)` inside `glassButton`) rather than grouped with gaps —
        // a real look-and-feel report from hands-on testing: lists sat cramped together in the
        // middle while Aa/link/photo were pushed to the edges.
        HStack(spacing: 0) {
            glassButton(systemImage: "textformat", isActive: isPanelOpen, label: "Text format") {
                isPanelOpen.toggle()
            }
            glassButton(systemImage: "list.bullet", isActive: model.currentLineStyle == .bullet, label: "Bulleted list") {
                model.setLineStyle(.bullet)
            }
            glassButton(systemImage: "list.number", isActive: model.currentLineStyle == .ordered, label: "Numbered list") {
                model.setLineStyle(.ordered)
            }
            // Deliberately never `.disabled` — a disabled glass button here gives zero visual
            // cue it's inert, and always opening the link sheet (rather than requiring a
            // selection first) is itself the fix for a real report from hands-on testing: a tap
            // with nothing selected used to look exactly like "the button isn't wired up."
            if showsLink {
                glassButton(systemImage: "link", isActive: false, label: "Insert link", action: onLink)
            }
            if showsPhoto {
                glassButton(systemImage: "photo.badge.plus", isActive: false, label: "Insert photo", action: onPhoto)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
        #if os(visionOS)
        .glassBackgroundEffect(in: Capsule())
        #else
        .glassEffect(in: Capsule())
        #endif
    }

    private func glassButton(systemImage: String, isActive: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white))
                .frame(width: 44, height: 44)
                .background(isActive ? Color.accentColor.opacity(0.16) : Color.clear, in: Circle())
                .frame(maxWidth: .infinity)
        }
        // Without `.plain`, this Button's default style tints its label with the app's accent
        // color regardless of the explicit `.foregroundStyle` above — the real cause of a real
        // report from hands-on testing ("why are the icons blue?"); `.plain` lets the label's
        // own styling actually win.
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - The Aa panel

    private var formatPanel: some View {
        VStack(spacing: 0) {
            styleRow(.body, label: "Body", meta: "no block attribute") { Text("Body").font(.body) }
            styleRow(.header1, label: "Header 1", meta: "header: 1") { Text("Header 1").font(.title3) }
            styleRow(.header2, label: "Header 2", meta: "header: 2") { Text("Header 2").font(.system(size: 19, weight: .semibold)) }

            Divider().padding(.horizontal, 14)

            HStack(spacing: 8) {
                charToggle("bold", isActive: model.isBoldActive) { model.toggleBold() }
                charToggle("italic", isActive: model.isItalicActive) { model.toggleItalic() }
                charToggle("underline", isActive: model.isUnderlineActive) { model.toggleUnderline() }
                charToggle("strikethrough", isActive: model.isStrikeActive) { model.toggleStrike() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 4)
        .frame(width: 320)
        #if os(visionOS)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 20))
        #else
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        #endif
    }

    private func styleRow(
        _ style: RichTextEditorModel.LineStyle,
        label: String,
        meta: String,
        @ViewBuilder preview: () -> some View
    ) -> some View {
        let isActive = model.currentLineStyle == style
        return Button {
            model.setLineStyle(style)
        } label: {
            HStack {
                preview()
                Spacer()
                Text(meta)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                    .opacity(isActive ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func charToggle(_ systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .background(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}
