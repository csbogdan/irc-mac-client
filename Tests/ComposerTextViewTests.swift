import AppKit
import SwiftUI
import XCTest
@testable import RelayIRC

/// Selection and input-method behavior of the composer field.
/// The window stays offscreen so the test does not take keyboard focus.
final class ComposerTextViewTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() {
        window?.orderOut(nil)
        window = nil
        super.tearDown()
    }

    func testSelectionSurvivesASwiftUIUpdate() {
        let model = ComposerHarnessModel(text: "hello", caret: 0)
        let textView = mount(model)
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        model.focus += 1
        settle()
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 5))
    }

    func testSelectionStartingAwayFromTheCaretSurvives() {
        let model = ComposerHarnessModel(text: "hello", caret: 5)
        let textView = mount(model)
        settle()
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        settle()
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 5))
    }

    func testProgrammaticCaretMoveCollapsesTheSelection() {
        let model = ComposerHarnessModel(text: "hello", caret: 0)
        let textView = mount(model)
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        model.caret = 2
        settle()
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testReturnWhileComposingDoesNotSend() {
        let model = ComposerHarnessModel(text: "", caret: 0)
        let textView = mount(model)
        textView.setMarkedText("あ", selectedRange: NSRange(location: 0, length: 1), replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(textView.hasMarkedText())
        textView.keyDown(with: key(code: 36, characters: "\r"))
        XCTAssertEqual(model.submits, 0)
    }

    func testReturnSendsWhenNotComposing() {
        let model = ComposerHarnessModel(text: "hi", caret: 2)
        let textView = mount(model)
        textView.keyDown(with: key(code: 36, characters: "\r"))
        XCTAssertEqual(model.submits, 1)
    }

    private func mount(_ model: ComposerHarnessModel) -> RelayTextView {
        let host = NSHostingView(rootView: ComposerHarness(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 80)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        self.window = window
        host.layoutSubtreeIfNeeded()
        settle()
        guard let textView = findTextView(in: host) else {
            XCTFail("composer text view was not installed")
            return RelayTextView()
        }
        return textView
    }

    private func settle() {
        let exp = expectation(description: "swiftui update")
        DispatchQueue.main.async {
            DispatchQueue.main.async { exp.fulfill() }
        }
        wait(for: [exp], timeout: 2)
    }

    private func findTextView(in view: NSView) -> RelayTextView? {
        if let textView = view as? RelayTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }

    private func key(code: UInt16, characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: code
        )!
    }
}

private final class ComposerHarnessModel: ObservableObject {
    @Published var text: String
    @Published var caret: Int
    @Published var focus: Int
    var submits = 0

    init(text: String, caret: Int) {
        self.text = text
        self.caret = caret
        self.focus = 0
    }
}

private struct ComposerHarness: View {
    @ObservedObject var model: ComposerHarnessModel

    var body: some View {
        ComposerTextView(
            text: $model.text,
            caretUTF16: $model.caret,
            placeholder: "",
            focusNonce: model.focus,
            measuredHeight: .constant(28),
            onSubmit: { model.submits += 1 },
            onTab: { false },
            onVertical: { _ in false },
            onEscape: { false }
        )
        .frame(height: 36)
    }
}
