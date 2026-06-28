import SwiftUI
import AppKit

/// A borderless, transparent inline text field that, on focus, places the caret
/// at the END of the text instead of AppKit's default "select all". Auto-focuses
/// when it appears, commits on Return/blur, and cancels on Esc.
struct InlineField: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment = .left
    var placeholder: String = ""
    var maxLength: Int? = nil
    var onEnd: () -> Void = {}

    func makeNSView(context: Context) -> CaretEndTextField {
        let field = CaretEndTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.placeholderString = placeholder
        field.stringValue = text
        field.focusOnAppear = true
        return field
    }

    func updateNSView(_ field: CaretEndTextField, context: Context) {
        context.coordinator.parent = self
        field.font = font
        field.textColor = color
        field.alignment = alignment
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineField
        init(_ parent: InlineField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            var value = field.stringValue
            if let max = parent.maxLength, value.count > max {
                value = String(value.prefix(max))
                field.stringValue = value
            }
            parent.text = value
        }

        func controlTextDidEndEditing(_ note: Notification) {
            parent.onEnd()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:))
                || selector == #selector(NSResponder.cancelOperation(_:)) {
                control.window?.makeFirstResponder(nil)   // commit + blur
                return true
            }
            return false
        }
    }
}

/// NSTextField that focuses itself on appear and moves the caret to the end
/// (rather than selecting all) when it becomes first responder.
final class CaretEndTextField: NSTextField {
    var focusOnAppear = false

    // Editable NSTextFields report no useful intrinsic width, which collapses the
    // field under SwiftUI `.fixedSize()`. Measure the text so it hugs its content.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        let measured = stringValue.isEmpty ? (placeholderString ?? "") : stringValue
        let f = font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let width = (measured as NSString).size(withAttributes: [.font: f]).width
        size.width = ceil(width) + 6   // a little room for the caret
        return size
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        invalidateIntrinsicContentSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusOnAppear, window != nil {
            focusOnAppear = false
            window?.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let editor = currentEditor() {
            let end = (stringValue as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
        return ok
    }
}
