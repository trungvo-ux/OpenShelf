import SwiftUI
import AppKit
import Carbon
import ApplicationServices
import ServiceManagement

@main
struct OpenShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.showSettings() }.keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var store: Store!
    let updates = UpdateController()
    var panel: ShelfPanel?
    var settingsWindow: NSWindow?
    var previewWindow: NSWindow?
    var status: NSStatusItem!
    var hotKey: EventHotKeyRef?
    var handler: EventHandlerRef?
    private var registeredShortcut: (code: UInt32, modifiers: UInt32)?
    var previousApp: NSRunningApplication?
    var localMonitor: Any?
    var outsideMonitor: Any?
    @Published var session = UUID()
    @Published var feedback: String?
    @Published var directPasteAllowed = CGPreflightPostEventAccess()
    private var activationObserver: NSObjectProtocol?
    var demo = ProcessInfo.processInfo.arguments.contains("--demo") || Bundle.main.bundleIdentifier == "org.openshelf.demo"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let demoURL = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("OpenShelf-Demo-\(ProcessInfo.processInfo.processIdentifier)") : nil
        store = Store(directory: demoURL, monitor: !demo)
        if demo { seedDemo() }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "OpenShelf")
        status.button?.target = self
        status.button?.action = #selector(showMenu)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in self?.previousApp = app }
        }
        if !demo { registerShortcut(); updates.startIfConfigured() }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.demo, self.store.settings.position.rawValue != "window", let panel = self.panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) { panel.orderOut(nil) }
            }
        }
        if demo || !UserDefaults.standard.bool(forKey: "didWelcome") { DispatchQueue.main.async { self.showWelcome() } }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        directPasteAllowed = CGPreflightPostEventAccess()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel?.isVisible != true && settingsWindow?.isVisible != true && previewWindow?.isVisible != true { toggleShelf() }
        return true
    }
    @objc func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Open Shelf", action: #selector(toggleShelf), keyEquivalent: "")
        menu.addItem(withTitle: store.paused ? "Resume Recording" : "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        let updateItem = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.isEnabled = updates.canCheck
        menu.addItem(withTitle: "About OpenShelf", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenShelf", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        status.button?.performClick(nil)
        status.menu = nil
    }
    @objc func checkForUpdates() { updates.checkForUpdates() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func togglePause() { store.paused.toggle() }
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "OpenShelf", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development", .credits: NSAttributedString(string: "Free, open source clipboard history.\nBuilt with SwiftUI and AppKit. MIT licensed.\nIndependent implementation; not affiliated with MinimalPaste.")])
        NSApp.activate(ignoringOtherApps: true)
    }
    func registerShortcut() {
        if let registeredShortcut, registeredShortcut.code == store.settings.hotKeyCode, registeredShortcut.modifiers == store.settings.hotKeyModifiers { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
                guard let data else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
                Task { @MainActor in owner.toggleShelf() }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        var candidate: EventHotKeyRef?
        let result = RegisterEventHotKey(store.settings.hotKeyCode, store.settings.hotKeyModifiers, EventHotKeyID(signature: 0x4f53484c, id: 1), GetApplicationEventTarget(), 0, &candidate)
        if result == noErr {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = candidate
            registeredShortcut = (store.settings.hotKeyCode, store.settings.hotKeyModifiers)
        } else {
            if let registeredShortcut { store.settings.hotKeyCode = registeredShortcut.code; store.settings.hotKeyModifiers = registeredShortcut.modifiers; store.save() }
            store.errorMessage = "That shortcut could not be registered. Your previous shortcut is still active; choose another combination."
        }
    }
    @objc func toggleShelf() {
        if panel?.isVisible == true { panel?.orderOut(nil); return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        store.prune(); store.save()
        session = UUID()
        if panel == nil {
            let p = ShelfPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .resizable, .closable], backing: .buffered, defer: false)
            p.title = "OpenShelf"
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isReleasedWhenClosed = false
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.minSize = NSSize(width: 340, height: 280)
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: ShelfView(store: store, app: self).id(session))
        positionShelf()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    func positionShelf() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let inset: CGFloat = store.settings.floating ? 14 : 0
        let position = store.settings.position.rawValue
        panel.titleVisibility = position == "window" ? .visible : .hidden
        panel.titlebarAppearsTransparent = position != "window"
        if position == "window" { panel.styleMask.remove(.fullSizeContentView); panel.styleMask.insert(.miniaturizable) }
        else { panel.styleMask.insert(.fullSizeContentView); panel.styleMask.remove(.miniaturizable) }
        let rect: NSRect
        switch position {
        case "bottom": rect = NSRect(x: frame.minX + inset, y: frame.minY + inset, width: frame.width - inset * 2, height: min(370, frame.height))
        case "left": rect = NSRect(x: frame.minX + inset, y: frame.minY + inset, width: 370, height: frame.height - inset * 2)
        case "right": rect = NSRect(x: frame.maxX - 370 - inset, y: frame.minY + inset, width: 370, height: frame.height - inset * 2)
        default: rect = NSRect(x: frame.midX - min(800, frame.width) / 2, y: frame.midY - min(600, frame.height) / 2, width: min(800, frame.width), height: min(600, frame.height))
        }
        panel.setFrame(rect, display: true, animate: panel.isVisible)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { panel.standardWindowButton(kind)?.isHidden = position != "window" }
    }
    func paste(_ clips: [Clip], plainText: Bool? = nil, copyOnly: Bool = false) {
        guard !clips.isEmpty else { return }
        let shift = NSEvent.modifierFlags.contains(.shift)
        let plain = plainText ?? (store.settings.alwaysPlainText != shift)
        if demo {
            let board = NSPasteboard(name: .init("OpenShelfDemoPaste"))
            _ = store.write(clips, plainText: plain, pasteboard: board)
            feedback = "Demo: prepared \(clips.count) clip(s) on an isolated clipboard. Your clipboard is unchanged."
            return
        }
        guard store.write(clips, plainText: plain) else { feedback = "The selection could not be written to the clipboard."; return }
        guard !copyOnly, store.settings.pasteDirectly, !demo else {
            panel?.orderOut(nil); previousApp?.activate(options: []); return
        }
        directPasteAllowed = CGPreflightPostEventAccess()
        guard directPasteAllowed else {
            feedback = "Copied. Press ⌘V to paste, or enable Accessibility in Settings for direct paste."
            return
        }
        guard let target = previousApp, !target.isTerminated else { feedback = "Copied. Switch to an app and press ⌘V."; return }
        panel?.orderOut(nil)
        target.activate(options: [])
        deliverPaste(to: target, changeCount: NSPasteboard.general.changeCount, attempt: 0)
    }
    private func deliverPaste(to target: NSRunningApplication, changeCount: Int, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard NSPasteboard.general.changeCount == changeCount else { self.feedback = "Paste cancelled because another app changed the clipboard. Open the shelf and try again."; return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                if attempt < 12 { self.deliverPaste(to: target, changeCount: changeCount, attempt: attempt + 1) }
                else { self.feedback = "Copied. The previous app could not be activated; press ⌘V there." }
                return
            }
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }
    func requestAccessibility() {
        _ = CGRequestPostEventAccess()
        directPasteAllowed = CGPreflightPostEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 580), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "OpenShelf Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(store: store, app: self))
            window.minSize = NSSize(width: 600, height: 520)
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func preview(_ clip: Clip) {
        if clip.kind.rawValue == "link", let url = URL(string: clip.text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "OpenShelf Preview"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ClipPreview(clip: clip).padding(24))
        window.center(); window.makeKeyAndOrderFront(nil); previewWindow = window
    }
    func addFolder() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.prompt = "Add Folder"; picker.message = "Browse this folder from the shelf. Files remain in their original location."
        if picker.runModal() == .OK, let url = picker.url { store.addFolder(url) }
    }
    func showWelcome() {
        if demo { toggleShelf(); return }
        let alert = NSAlert()
        alert.messageText = "A little memory for your clipboard."
        alert.informativeText = "OpenShelf keeps copied text, links, images, files, and colors on this Mac. Press ⇧⌘V to open your shelf. Pin favorites, create groups, or add folders from +.\n\nRecording is active. Password managers and confidential clips are skipped. Enable Accessibility in Settings if you want Return to paste into the previous app."
        alert.addButton(withTitle: "Open Shelf"); alert.addButton(withTitle: "Settings")
        UserDefaults.standard.set(true, forKey: "didWelcome")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { toggleShelf() } else { showSettings() }
    }
    func seedDemo() {
        let examples = ["A little memory for your clipboard.", "https://developer.apple.com/swiftui/", "#FF8DA1", "Meeting notes\n\nKeep the interface simple.\nMake the everyday things feel effortless.", "let shelf = ClipboardHistory()\nshelf.keepWhatMatters()", "https://www.swift.org/"]
        for text in examples.reversed() {
            let p = NSPasteboard(name: .init("OpenShelfDemo")); p.clearContents(); p.setString(text, forType: .string)
            store.capture(pasteboard: p, sourceName: "Safari", sourceBundleID: "com.apple.Safari")
        }
        store.addGroup(name: "Work", color: "#FF6464"); store.addGroup(name: "Design", color: "#FF9F0A")
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.save()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
}
