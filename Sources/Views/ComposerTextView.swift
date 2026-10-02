import AppKit
import SwiftUI

/// Multiline composer field. SwiftUI `TextField` on macOS does not reliably
/// become the pasteboard responder (⌘C / ⌘V / ⌘X / ⌘A), so the box is a real
/// `NSTextView`. Return sends; Shift-Return inserts a newline.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var caretUTF16: Int
    var placeholder: String
    var focusNonce: Int
    var measuredHeight: Binding<CGFloat>
    var onSubmit: () -> Void
    var onTab: () -> Bool
    var onVertical: (Int) -> Bool
    var onEscape: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let textView = RelayTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.focusRingType = .none
        textView.font = .systemFont(ofSize: 13.5)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.parent = self
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        textView.placeholder = placeholder
        textView.onSubmit = onSubmit
        textView.onTab = onTab
        textView.onVertical = onVertical
        textView.onEscape = onEscape

        let width = max(scroll.contentSize.width, 40)
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if textView.frame.width != width { textView.frame.size.width = width }

        // Don't clobber an IME composition, and don't push the string back
        // into the view when the view itself just published it.
        var replacedText = false
        if !textView.hasMarkedText(), textView.string != text {
            context.coordinator.applying = true
            textView.string = text
            context.coordinator.applying = false
            replacedText = true
        }
        // A mouse or keyboard selection reports only its start through
        // caretUTF16. Echoing that as a zero-length range collapses the
        // selection on the next SwiftUI update. Move the caret when the
        // text was replaced, or when SwiftUI asked for a different position.
        if !textView.hasMarkedText() {
            let length = (textView.string as NSString).length
            let loc = min(max(0, caretUTF16), length)
            let current = textView.selectedRange()
            if replacedText || current.location != loc {
                let range = NSRange(location: loc, length: 0)
                if current != range {
                    context.coordinator.applying = true
                    textView.setSelectedRange(range)
                    context.coordinator.applying = false
                }
            }
        }
        context.coordinator.publishHeight()

        if context.coordinator.appliedFocus != focusNonce {
            context.coordinator.appliedFocus = focusNonce
            scroll.window?.makeFirstResponder(textView)
        }
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: RelayTextView?
        var applying = false
        var appliedFocus = -1

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !applying, let textView else { return }
            parent.text = textView.string
            parent.caretUTF16 = textView.selectedRange().location
            publishHeight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !applying, let textView else { return }
            let loc = textView.selectedRange().location
            if parent.caretUTF16 != loc { parent.caretUTF16 = loc }
        }

        func publishHeight() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            let height = min(max(ceil(used.height + textView.textContainerInset.height * 2) + 4, 28), 110)
            if abs(parent.measuredHeight.wrappedValue - height) > 0.5 {
                parent.measuredHeight.wrappedValue = height
            }
        }
    }
}

final class RelayTextView: NSTextView {
    var placeholder = ""
    var onSubmit: () -> Void = {}
    var onTab: () -> Bool = { false }
    var onVertical: (Int) -> Bool = { _ in false }
    var onEscape: () -> Bool = { false }

    override func keyDown(with event: NSEvent) {
        // Command-key equivalents (copy, paste, undo) stay on the responder
        // chain. Only the bare editing keys are intercepted.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        // Return confirms an IME candidate. Sending here would post the
        // unfinished composition. Arrows, Escape, and Tab belong to the
        // input method for the same reason.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            if flags.contains(.shift) { insertNewline(nil); return }
            onSubmit()
        case 48: // Tab
            if !onTab() { super.keyDown(with: event) }
        case 126: // Up
            if !onVertical(-1) { super.keyDown(with: event) }
        case 125: // Down
            if !onVertical(1) { super.keyDown(with: event) }
        case 53: // Escape
            if !onEscape() { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)
        }
    }

    /// Paste as plain text. A rich paste from a browser would otherwise land
    /// as attributed runs an IRC line cannot carry.
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13.5),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let origin = NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: attrs)
    }
}
