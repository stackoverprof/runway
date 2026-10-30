import AppKit

/// The live terminal views, by the id of whoever owns them, so the app can
/// hand one the keyboard from anywhere.
@MainActor final class TerminalRegistry {
    static let shared = TerminalRegistry()
    private var viewToID: [ObjectIdentifier: UUID] = [:]
    private var idToView: [UUID: NSView] = [:]

    func register(_ view: NSView, id: UUID) {
        viewToID[ObjectIdentifier(view)] = id
        idToView[id] = view
    }

    func unregister(id: UUID) {
        if let view = idToView[id] { viewToID.removeValue(forKey: ObjectIdentifier(view)) }
        idToView.removeValue(forKey: id)
    }

    /// Walks up from `view` to find the first registered terminal and its id.
    func owner(under view: NSView) -> UUID? {
        var node: NSView? = view
        while let current = node {
            if let id = viewToID[ObjectIdentifier(current)] { return id }
            node = current.superview
        }
        return nil
    }

    @discardableResult
    func focusTerminal(_ id: UUID?) -> Bool {
        guard let id, let view = idToView[id], let window = view.window else { return false }
        return window.makeFirstResponder(view)
    }
}
