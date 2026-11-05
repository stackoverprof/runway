import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GhosttyKit

/// Engine-agnostic description of what a terminal pane should run. Keeping this
/// separate from the engine means call sites never depend on GhosttyKit.
struct TerminalConfig: Equatable {
    /// Command to launch. `nil` = the user's default login shell.
    var command: String? = nil
    /// Working directory. `nil` = default (home).
    var workingDirectory: String? = nil
    /// Extra environment variables.
    var environment: [String: String] = [:]
}

/// Runway's libghostty host + the themed config used to override colors.
///
/// libghostty loads the user's real Ghostty config and exposes no color API, so
/// we build our own config (their config + our neutral theme loaded LAST, so our
/// colors win) and apply it to the app and to each surface. The `ghostty_*` C
/// symbols come from GhosttyKit's `@_exported import CGhosttyKitBinary`.
@MainActor
enum RunwayTerminalHost {
    static let shared: GhosttyTerminalHost? = {
        let host = try? GhosttyTerminalHost(loadDefaultTheme: false)
        if let host, let cfg = themedConfig {
            ghostty_app_update_config(host.app, cfg)
        }
        return host
    }()

    /// User's config + Runway's neutral theme last. Applied app-wide here; each
    /// surface also gets it via `session.updateConfig` after it attaches.
    /// Rebuilt when the terminal font changes.
    private(set) static var themedConfig: ghostty_config_t? = buildConfig()

    private static func buildConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(cfg)
        RunwayTerminal.themeFilePath.withCString { ghostty_config_load_file(cfg, $0) }
        ghostty_config_finalize(cfg)
        return cfg
    }

    /// Rewrite the theme file from the current settings and push it to every
    /// live terminal, so a font change lands without restarting the app or
    /// disturbing a single running session.
    static func reloadTheme() {
        RunwayTerminal.installTheme()
        guard let next = buildConfig() else { return }
        let previous = themedConfig
        themedConfig = next
        if let host = shared {
            ghostty_app_update_config(host.app, next)
        }
        for session in RunwayTerminalSessions.live() {
            session.updateConfig(next)
            forceTerminalLayoutUpdate(for: session)
        }
        // Freed only after every surface has taken the new one, the same order
        // GhosttyKit uses for its own config reload.
        if let previous { ghostty_config_free(previous) }
    }
}

/// Live terminal sessions, so a config change can reach all of them. GhosttyKit
/// keeps its own registry but does not publish it.
@MainActor
enum RunwayTerminalSessions {
    private struct WeakSession {
        weak var value: GhosttyTerminalSession?
    }

    private static var sessions: [WeakSession] = []
    private static var boxIDs: [ObjectIdentifier: UUID] = [:]

    static func register(_ session: GhosttyTerminalSession, boxID: UUID? = nil) {
        sessions.removeAll { $0.value == nil || $0.value === session }
        sessions.append(WeakSession(value: session))
        if let boxID { boxIDs[ObjectIdentifier(session)] = boxID }
    }

    static func live() -> [GhosttyTerminalSession] {
        sessions.removeAll { $0.value == nil }
        let liveIDs = Set(sessions.compactMap { $0.value.map(ObjectIdentifier.init) })
        boxIDs = boxIDs.filter { liveIDs.contains($0.key) }
        return sessions.compactMap(\.value)
    }

    static func boxID(for session: GhosttyTerminalSession) -> UUID? {
        boxIDs[ObjectIdentifier(session)]
    }
}

import UniformTypeIdentifiers

/// The swappable terminal seam. Everything in Runway embeds `TerminalSurfaceView`;
/// switching the terminal engine means rewriting only this file. Today it is
/// backed by libghostty's GPU renderer via GhosttyKit.
struct TerminalSurfaceView: View {
    let boxID: UUID
    let workspace: Workspace
    /// False for a terminal that is mounted but off screen. A hidden view is
    /// not drawn, and not drawing is the whole point: every visible terminal
    /// renders on the main thread and waits for its own GPU frame, so a
    /// handful of parked flights were enough to stall the window.
    let isVisible: Bool
    @State private var session: GhosttyTerminalSession

    init(
        boxID: UUID,
        workspace: Workspace,
        isVisible: Bool = true,
        config: TerminalConfig
    ) {
        self.boxID = boxID
        self.workspace = workspace
        self.isVisible = isVisible
        let launch = GhosttyTerminalLaunchConfiguration(
            command: config.command,
            workingDirectory: config.workingDirectory,
            environment: config.environment,
            colorScheme: .dark
        )
        // The pool owns the session, not this view, so leaving a flight parks
        // the agent instead of killing it.
        _session = State(
            initialValue: TerminalSessionPool.shared.session(for: boxID, launch: launch)
        )
    }

    var body: some View {
        PooledTerminal(session: session, isVisible: isVisible) {
            Task { @MainActor in workspace.setFocus(boxID) }
        }
            .onAppear {
                TerminalSessionPool.shared.mounted(boxID)
                applyRunwayTheme(to: session, boxID: boxID)
                registerForFocus()
                showOrHide()
            }
            .onChange(of: isVisible) { _, _ in showOrHide() }
            .onDisappear { TerminalSessionPool.shared.parked(boxID) }
            // GhosttyKit's embedded view doesn't accept file drops; replicate
            // Ghostty's behavior by typing the dropped file's path (shell-escaped)
            // into the terminal — Claude Code then picks it up as an image.
            // The whole box takes a drop, including the padding around the
            // glyphs. Without a shape the drop only lands where SwiftUI
            // thinks content is, which is why a drop near an edge did
            // nothing.
            //
            // Over the terminal itself the drop is AppKit's, taken by the
            // container view (see `DropContainer`). This one only covers the
            // padding around it, and only on the seat you can see: a hidden
            // seat stacked on top used to swallow drops meant for the pilot.
            .contentShape(Rectangle())
            .onDrop(of: isVisible ? [.fileURL, .image] : [], isTargeted: nil) { providers in
                handleDropProviders(providers, session: session) {
                    Task { @MainActor in
                        workspace.setFocus(boxID)
                    }
                }
                return true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in
                forceTerminalLayoutUpdate(for: session)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { _ in
                forceTerminalLayoutUpdate(for: session)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeBackingPropertiesNotification)) { _ in
                forceTerminalLayoutUpdate(for: session)
            }
    }

    /// Keep the backing view's hidden flag in step with the pane. AppKit
    /// skips drawing a hidden view, so a parked terminal costs nothing while
    /// its session keeps running.
    private func showOrHide() {
        Task { @MainActor in
            for _ in 0..<40 {
                if let view = session.view {
                    if view.isHidden != !isVisible { view.isHidden = !isVisible }
                    // Its box too, so a hidden seat stacked over the visible
                    // one is skipped when AppKit looks for a drop target.
                    if let box = view.superview as? DropContainer, box.isHidden != !isVisible {
                        box.isHidden = !isVisible
                    }
                    if isVisible { forceTerminalLayoutUpdate(for: session) }
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    /// Register this box's terminal view so clicks on it resolve to the box.
    private func registerForFocus() {
        Task { @MainActor in
            for _ in 0..<100 {
                if let view = session.view {
                    TerminalRegistry.shared.register(view, id: boxID)
                    var didApplyInitialFocus = false
                    for delay in [0.05, 0.15, 0.35, 0.75, 1.5, 3.0] {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        if view.window != nil {
                            // A surface mounting is not a request to type in it:
                            // if the quick terminal already holds the keyboard,
                            // leave it there and only claim the visual focus.
                            if !didApplyInitialFocus, workspace.focusedID == boxID,
                               !workspace.isQuickTerminalFocused {
                                view.window?.makeFirstResponder(view)
                                didApplyInitialFocus = true
                            }
                            forceTerminalLayoutUpdate(for: session)
                        }
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

/// Force libghostty to update its display ID, backing scale factor, and physical surface size.
@MainActor func forceTerminalLayoutUpdate(for session: GhosttyTerminalSession) {
    guard let view = session.view else { return }
    // GhosttyKit paints the host view's layer with its own fallback color, chosen
    // from the appearance: Rosé Pine purple (#191724) or cream (#faf4ed). It sits
    // under the Metal surface and shows through the padding, so overwrite it with
    // Runway's body color and the terminal stays one flat near-black.
    view.layer?.backgroundColor = RunwayTerminal.bodyNSColor.cgColor
    let scale = view.window?.backingScaleFactor ?? 1.0
    view.layer?.contentsScale = scale
    view.viewDidChangeBackingProperties()
    session.updateContentScale()
    session.resize(to: view.bounds.size)
    view.needsLayout = true
    view.needsDisplay = true
}

/// Make a fresh libghostty session backed by Runway's host (falls back to a
/// default session if the host failed to init).
@MainActor func makeRunwaySession(_ config: TerminalConfig = TerminalConfig()) -> GhosttyTerminalSession {
    let launch = GhosttyTerminalLaunchConfiguration(
        command: config.command,
        workingDirectory: config.workingDirectory,
        environment: config.environment,
        colorScheme: .dark
    )
    if let host = RunwayTerminalHost.shared { return host.makeSession(configuration: launch) }
    return GhosttyTerminalSession(configuration: launch)
}

/// Push Runway's themed config onto a session's surface. The surface may not
/// exist on the first call, so retry once shortly after.
@MainActor func applyRunwayTheme(to session: GhosttyTerminalSession, boxID: UUID? = nil) {
    // Every session passes through here, so this is where they become reachable
    // for a later font change.
    RunwayTerminalSessions.register(session, boxID: boxID)
    guard let cfg = RunwayTerminalHost.themedConfig else { return }
    session.updateConfig(cfg)
    forceTerminalLayoutUpdate(for: session)
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 250_000_000)
        session.updateConfig(cfg)
        forceTerminalLayoutUpdate(for: session)
    }
}

/// Backslash-escape shell-special characters (spaces, etc.) like a terminal does
/// on file drop, so paths with spaces (e.g. screenshots) work.
func runwayShellEscape(_ path: String) -> String {
    let special = Set(" \t\"'`\\$&|;<>()[]{}*?!#~")
    var out = ""
    for ch in path {
        if special.contains(ch) { out.append("\\") }
        out.append(ch)
    }
    return out
}

/// Naming for images Runway has to materialize itself (a drag that carried only
/// pixels, never a file on disk).
enum DroppedImageFile {
    /// Prefer the name the drag source suggested, so the path typed into the
    /// terminal still reads like the file the user dragged.
    static func name(
        suggested: String?,
        typeIdentifier: String?,
        timestamp: Int
    ) -> String {
        let fallbackExtension = typeIdentifier
            .flatMap(UTType.init)?
            .preferredFilenameExtension ?? "png"
        guard let suggested, !suggested.isEmpty else {
            return "dropped-image-\(timestamp).\(fallbackExtension)"
        }
        let sanitized = suggested
            .components(separatedBy: CharacterSet(charactersIn: "/:\n\r\t"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty else {
            return "dropped-image-\(timestamp).\(fallbackExtension)"
        }
        if (sanitized as NSString).pathExtension.isEmpty {
            return "\(sanitized).\(fallbackExtension)"
        }
        return sanitized
    }
}

/// Unified, robust drag-and-drop provider handler for file URLs, images, and screenshots
@MainActor func handleDropProviders(
    _ providers: [NSItemProvider],
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void = {}
) {
    for provider in providers {
        nonisolated(unsafe) let safeProvider = provider
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, FileManager.default.fileExists(atPath: url.path) {
                    typeDroppedPath(
                        keptPath(for: url),
                        session: session,
                        onComplete: onComplete
                    )
                } else {
                    // Fall back to image loading if URL was not locally on disk (like a floating screenshot promise)
                    loadAsImage(safeProvider, session: session, onComplete: onComplete)
                }
            }
        } else {
            loadAsImage(safeProvider, session: session, onComplete: onComplete)
        }
    }
}

/// A dropped file that lives somewhere temporary is copied into Runway's own
/// drops folder first, and that copy's path is what gets typed.
///
/// The screenshot thumbnail in the corner of the screen hands over a file in
/// a scratch folder macOS deletes as soon as the thumbnail goes away. The path
/// went into Claude's prompt fine, but if the prompt was sent a few seconds
/// later the file was already gone and the image never arrived, which is why
/// a drop only failed sometimes. A file from Finder is left where it is.
private func keptPath(for url: URL) -> String {
    guard isTemporary(url) else { return url.path }
    let destination = AgentControl.dropsDir.appendingPathComponent(
        DroppedImageFile.name(
            suggested: url.lastPathComponent,
            typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier,
            timestamp: Int(Date().timeIntervalSince1970)
        )
    )
    return adoptDroppedFile(at: url, to: destination)?.path ?? url.path
}

/// Inside a folder the system clears on its own: the per-user temporary
/// folder, where the screenshot thumbnail keeps its file.
private func isTemporary(_ url: URL) -> Bool {
    let path = url.resolvingSymlinksInPath().path
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        .resolvingSymlinksInPath().path
    return path.hasPrefix(temporary)
        || path.contains("/TemporaryItems/")
        || path.hasPrefix("/private/var/folders/")
        || path.hasPrefix("/var/folders/")
}

private func typeDroppedPath(
    _ path: String,
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void
) {
    DispatchQueue.main.async {
        session.insertText(runwayShellEscape(path) + " ")
        onComplete()
    }
}

/// Resolve a dropped image to a path the agent can read.
///
/// The file the user dragged almost always exists on disk already, so ask for it
/// in place first and type that path. Only a drag that carries pixels with no
/// backing file (a screenshot still floating in its preview, an image dragged out
/// of a web page) gets written out, and it goes to Runway's own drops folder.
/// Writing those into ~/Downloads is what used to leave a second copy of every
/// screenshot dropped on a terminal.
private func loadAsImage(
    _ provider: NSItemProvider,
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void
) {
    let imageType = provider.registeredTypeIdentifiers.first {
        UTType($0)?.conforms(to: .image) == true
    } ?? UTType.image.identifier
    guard provider.hasItemConformingToTypeIdentifier(imageType) else { return }
    nonisolated(unsafe) let safeProvider = provider
    let suggestedName = provider.suggestedName

    _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: imageType) { url, isInPlace, _ in
        // The URL is only valid for the duration of this callback, so decide and
        // copy here rather than hopping to the main queue with it.
        if let url, FileManager.default.fileExists(atPath: url.path) {
            if isInPlace, !isTemporary(url) {
                typeDroppedPath(url.path, session: session, onComplete: onComplete)
                return
            }
            let destination = AgentControl.dropsDir.appendingPathComponent(
                DroppedImageFile.name(
                    suggested: suggestedName ?? url.lastPathComponent,
                    typeIdentifier: imageType,
                    timestamp: Int(Date().timeIntervalSince1970)
                )
            )
            if let adopted = adoptDroppedFile(at: url, to: destination) {
                typeDroppedPath(adopted.path, session: session, onComplete: onComplete)
                return
            }
        }
        writeDroppedImageData(
            safeProvider,
            typeIdentifier: imageType,
            suggestedName: suggestedName,
            session: session,
            onComplete: onComplete
        )
    }
}

private func writeDroppedImageData(
    _ provider: NSItemProvider,
    typeIdentifier: String,
    suggestedName: String?,
    session: GhosttyTerminalSession,
    onComplete: @Sendable @escaping () -> Void
) {
    provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
        guard let data else { return }
        let destination = AgentControl.dropsDir.appendingPathComponent(
            DroppedImageFile.name(
                suggested: suggestedName,
                typeIdentifier: typeIdentifier,
                timestamp: Int(Date().timeIntervalSince1970)
            )
        )
        let target = uniqueDropDestination(destination)
        do {
            try data.write(to: target)
            AgentControl.pruneDrops()
            typeDroppedPath(target.path, session: session, onComplete: onComplete)
        } catch {
            NSLog("Runway: failed to write dropped image: \(error.localizedDescription)")
        }
    }
}

private func adoptDroppedFile(at source: URL, to destination: URL) -> URL? {
    let target = uniqueDropDestination(destination)
    do {
        try FileManager.default.copyItem(at: source, to: target)
        AgentControl.pruneDrops()
        return target
    } catch {
        NSLog("Runway: failed to adopt dropped file: \(error.localizedDescription)")
        return nil
    }
}

/// Never overwrite an earlier drop that is still on screen in some terminal.
private func uniqueDropDestination(_ url: URL) -> URL {
    guard FileManager.default.fileExists(atPath: url.path) else { return url }
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    for suffix in 2...99 {
        let candidate = url.deletingLastPathComponent()
            .appendingPathComponent(ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)")
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
    }
    return url
}


/// Hands a pooled terminal's view from one place on screen to another.
///
/// GhosttyKit's own representable builds a fresh view every time SwiftUI
/// mounts it, which is what made leaving a flight expensive: the surface was
/// torn down and rebuilt, and with several alive the main thread sat in
/// `waitUntilCompleted` for seconds. A terminal's view is made once and then
/// only ever reparented, so exactly one surface is in the window per seat and
/// leaving a flight costs nothing.
@MainActor
private struct PooledTerminal: NSViewRepresentable {
    let session: GhosttyTerminalSession
    /// Hidden boxes are never drop targets. Set here, on every update,
    /// rather than later from a task: the task looked the box up through the
    /// terminal's superview, and a terminal still parked in the hangar had
    /// none, so the box of a flight you had left stayed un-hidden, stacked
    /// over the pilot on screen, and took (or refused) its drops.
    var isVisible: Bool = true
    var onDrop: @Sendable () -> Void = {}

    func makeNSView(context: Context) -> NSView {
        let container = DropContainer()
        container.session = session
        container.onDrop = onDrop
        container.isHidden = !isVisible
        container.wantsLayer = true
        container.layer?.backgroundColor = RunwayTerminal.bodyNSColor.cgColor
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if let container = container as? DropContainer {
            container.session = session
            container.onDrop = onDrop
        }
        if container.isHidden != !isVisible { container.isHidden = !isVisible }
        attach(to: container)
    }

    /// Put the session's one view inside this container, making it the first
    /// time and moving it every time after.
    private func attach(to container: NSView) {
        let terminal = session.view ?? session.makeView(configuration: .default)
        guard terminal.superview !== container else { return }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}


/// The box a terminal sits in, and the thing that takes a file or image
/// dropped on it.
///
/// A drop used to be SwiftUI's `onDrop` on the terminal. In v3 the terminal
/// is an AppKit view moved between containers, several seats are stacked
/// with only one visible, and SwiftUI's drop routing over that was a coin
/// toss: the drop went to a hidden seat or nowhere. AppKit hands a drag to
/// the deepest view under the pointer that registered for it, and the
/// terminal view itself registers nothing, so this container is always the
/// one that gets it, for exactly the terminal under the pointer.
///
/// It reads the pasteboard the way v2 handled every case: a real file (typed
/// as its path, copied out first if it lives in a folder macOS clears), a
/// file promise (the screenshot thumbnail in the corner, written into
/// Runway's drops folder), and bare image pixels (saved as a PNG there).
@MainActor
final class DropContainer: NSView {
    weak var session: GhosttyTerminalSession?
    var onDrop: @Sendable () -> Void = {}

    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(
            [.fileURL]
                + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
                + Self.imageTypes
        )
    }

    required init?(coder: NSCoder) { nil }

    /// Live only while it is shown and still holds its terminal: a box whose
    /// terminal has moved to another box is an empty shell.
    private var takesDrops: Bool {
        guard !isHiddenOrHasHiddenAncestor, let terminal = session?.view else { return false }
        return terminal.superview === self && !terminal.isHidden
    }

    /// AppKit asks the deepest registered view under the pointer and stops
    /// there, even when it refuses. A dead box hands the hit test on, so
    /// the drag reaches the box that is really on screen.
    override func hitTest(_ point: NSPoint) -> NSView? {
        takesDrops ? super.hitTest(point) : nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        takesDrops ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        takesDrops ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let session, takesDrops else { return false }
        let pasteboard = sender.draggingPasteboard
        let done = onDrop

        // A real file on disk.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !existing.isEmpty {
                for url in existing {
                    typeDroppedPath(keptPath(for: url), session: session, onComplete: done)
                }
                return true
            }
        }

        // A promise to write the file, as the screenshot thumbnail makes.
        if let promises = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver], !promises.isEmpty {
            let folder = AgentControl.dropsDir
            for promise in promises {
                promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: .main) { url, error in
                    guard error == nil else {
                        NSLog("Runway: a dropped file promise failed: \(error!.localizedDescription)")
                        return
                    }
                    MainActor.assumeIsolated {
                        AgentControl.pruneDrops()
                        typeDroppedPath(url.path, session: session, onComplete: done)
                    }
                }
            }
            return true
        }

        // Bare pixels, from a browser or an app with no file behind them.
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let target = uniqueDropDestination(
                AgentControl.dropsDir.appendingPathComponent(
                    DroppedImageFile.name(
                        suggested: nil,
                        typeIdentifier: UTType.png.identifier,
                        timestamp: Int(Date().timeIntervalSince1970)
                    )
                )
            )
            do {
                try png.write(to: target)
                AgentControl.pruneDrops()
                typeDroppedPath(target.path, session: session, onComplete: done)
                return true
            } catch {
                NSLog("Runway: failed to write a dropped image: \(error.localizedDescription)")
            }
        }
        return false
    }
}

