import SwiftUI
import AppKit
import ServiceManagement
import Carbon
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var app: AppDelegate
    @State private var section = "General"
    @State private var excludedID = ""
    @State private var confirmClear = false
    let sections = ["General", "Appearance", "Pasting", "History", "Privacy", "Sounds", "Keyboard", "About"]
    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self, selection: $section) { name in Label(name, systemImage: icon(name)).tag(name) }.navigationSplitViewColumnWidth(150)
        } detail: {
            Form {
                switch section {
                case "General": general
                case "Appearance": appearance
                case "Pasting": pasting
                case "History": history
                case "Privacy": privacy
                case "Sounds": sounds
                case "Keyboard": keyboard
                default: about
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }.formStyle(.grouped).navigationTitle(section)
        }
        .onChange(of: store.settings) { _, _ in store.save(); app.positionShelf() }
        .alert("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { store.clearHistory() }
        } message: { Text("This removes all unpinned clips outside groups. Pinned clips and files in folder tabs are kept.") }
    }
    func icon(_ name: String) -> String {
        switch name { case "General": return "gearshape"; case "Appearance": return "paintpalette"; case "Pasting": return "doc.on.clipboard"; case "History": return "clock.arrow.circlepath"; case "Privacy": return "hand.raised"; case "Sounds": return "speaker.wave.2"; case "Keyboard": return "keyboard"; default: return "info.circle" }
    }
    var general: some View {
        SwiftUI.Group {
            Section("At your fingertips") {
                LabeledContent("Open shelf") { ShortcutRecorder(code: $store.settings.hotKeyCode, modifiers: $store.settings.hotKeyModifiers) { app.registerShortcut() }.frame(width: 150, height: 28) }
                Text("Default: Shift–Command–V. Click the shortcut to record a new combination.").font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; store.settings.launchAtLogin = enabled }
                    catch { store.errorMessage = "Could not change launch at login: \(error.localizedDescription)" }
                }))
                if SMAppService.mainApp.status == .requiresApproval { Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() } }
                Toggle("Pause clipboard recording", isOn: $store.paused)
            }
            UpdateSettingsView(updates: app.updates)
            Section("Folders") {
                ForEach(store.folders) { folder in
                    HStack { VStack(alignment: .leading) { Text(folder.name); Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Button(role: .destructive) { store.removeFolder(folder.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove \(folder.name) tab") }
                }
                Button("Add Folder…") { app.addFolder() }
                Button("Add Downloads") { store.addFolder(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) }
                Text("Folders get their own shelf tabs. Removing a tab never deletes its files.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    var appearance: some View {
        SwiftUI.Group {
            Section("Shelf") {
                Button("Open Shelf") { app.toggleShelf() }
                Picker("Position", selection: $store.settings.position) { ForEach(ShelfPosition.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Float above the screen edge", isOn: $store.settings.floating)
                Picker("Window layout", selection: $store.settings.windowLayout) { ForEach(WindowLayout.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                Toggle("Show type filters", isOn: $store.settings.showTypeFilters)
            }
            Section("Item colors") {
                Picker("Colors", selection: $store.settings.itemColors) { ForEach(ItemColors.allCases, id: \.self) { Text(backgroundName($0.rawValue)).tag($0) } }
            }
            Section("Background") {
                Picker("Style", selection: $store.settings.background) { ForEach(ShelfBackground.allCases, id: \.self) { Text(backgroundName($0.rawValue)).tag($0) } }
                if store.settings.background.rawValue == "image" {
                    Button("Choose Picture…") { chooseBackground() }
                    Slider(value: $store.settings.backgroundBlur, in: 0...40) { Text("Blur") }
                    Slider(value: $store.settings.backgroundDim, in: 0...0.85) { Text("Dim") }
                }
                Text("Open the shelf to see changes. Material styles use native macOS translucency.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    func backgroundName(_ value: String) -> String { switch value { case "softLight": return "Soft Light"; case "softDark": return "Soft Dark"; case "liquidGlass": return "Liquid Glass"; case "frostedGlass": return "Frosted Glass"; default: return value.capitalized } }
    func chooseBackground() {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.image]; picker.canChooseDirectories = false
        if picker.runModal() == .OK, let url = picker.url {
            do {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenShelf/Backgrounds")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try Data(contentsOf: url)
                guard NSImage(data: data) != nil else { store.errorMessage = "That file is not a readable image."; return }
                let destination = directory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                try data.write(to: destination, options: .atomic)
                store.settings.backgroundImagePath = destination.path
            } catch { store.errorMessage = "Could not save background: \(error.localizedDescription)" }
        }
    }
    var pasting: some View {
        Section("Paste back") {
            Toggle("Paste directly into the previous app", isOn: $store.settings.pasteDirectly)
            Text("When off, choosing a clip copies it. Press Command–V in the destination app.").font(.caption).foregroundStyle(.secondary)
            Toggle("Always paste plain text", isOn: $store.settings.alwaysPlainText)
            Text("Hold Shift when pasting to reverse this option for one paste. Multiple text clips are joined with newlines; files retain their file references.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Direct paste access", value: app.directPasteAllowed ? "Allowed" : "Not enabled")
            Button("Enable Direct Paste…") { app.requestAccessibility() }
        }
    }
    var history: some View {
        Section("Retention") {
            LabeledContent("Items in history", value: "\(store.clips.count)")
            Picker("Maximum unpinned items", selection: $store.settings.maxItems) { ForEach([100,500,1000,5000,10000,0], id: \.self) { Text($0 == 0 ? "Unlimited" : "\($0)").tag($0) } }
            Picker("Remove items unused for", selection: $store.settings.maxAgeDays) { ForEach([1,7,14,30,90,365,0], id: \.self) { Text($0 == 0 ? "Never" : "\($0) days").tag($0) } }
            Text("Pins and grouped clips are always kept and do not count toward the limit. History is stored only on this Mac.").font(.caption).foregroundStyle(.secondary)
            Button("Apply Retention Now") { store.prune(); store.save() }
            Button("Clear History…", role: .destructive) { confirmClear = true }
        }
    }
    var privacy: some View {
        SwiftUI.Group {
            Section("Your clipboard stays here") {
                Toggle("Ignore passwords and confidential content", isOn: $store.settings.ignoreConfidential)
                Text("Skips known password managers and clips marked confidential, temporary, or automatically generated. An app must mark sensitive content for reliable detection.").font(.caption).foregroundStyle(.secondary)
                Toggle("Load link previews", isOn: $store.settings.loadLinkPreviews)
                Text("When enabled, viewing links contacts their websites through Apple's Link Presentation framework. Previews are cached on this Mac. Off by default.").font(.caption).foregroundStyle(.secondary)
                Button("Clear Link Preview Cache") {
                    do { try LinkCache.shared.clear() }
                    catch { store.errorMessage = error.localizedDescription }
                }
            }
            Section("Never record from these apps") {
                ForEach(store.settings.excludedApps, id: \.self) { id in HStack { Text(id); Spacer(); Button { store.settings.excludedApps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove exclusion for \(id)") } }
                HStack { TextField("Bundle ID, e.g. com.apple.Terminal", text: $excludedID); Button("Add") { addExcluded() }.disabled(excludedID.trimmingCharacters(in: .whitespaces).isEmpty) }
                Button("Choose Application…") {
                    let picker = NSOpenPanel(); picker.allowedContentTypes = [.application]; picker.directoryURL = URL(fileURLWithPath: "/Applications")
                    if picker.runModal() == .OK, let url = picker.url, let id = Bundle(url: url)?.bundleIdentifier { excludedID = id; addExcluded() }
                }
            }
        }
    }
    func addExcluded() { let id = excludedID.trimmingCharacters(in: .whitespacesAndNewlines); if !id.isEmpty, !store.settings.excludedApps.contains(id) { store.settings.excludedApps.append(id) }; excludedID = "" }
    var sounds: some View { Section("Recording") { Toggle("Play a sound when a clip is recorded", isOn: $store.settings.playSound); Text("Skipped, private, and paused copies stay silent.").font(.caption).foregroundStyle(.secondary) } }
    var keyboard: some View {
        Section("Shelf shortcuts") {
            ForEach([("↑ ↓ / ← →", "Move through clips"), ("Return / double-click", "Paste, or open a folder"), ("Shift–Return", "Reverse plain-text setting"), ("Command–click / Shift–click", "Select several clips"), ("Command–1…9", "Paste by position"), ("Command–S", "Save selection to a group"), ("Command–F", "Search"), ("Command–P", "Pin or unpin focused clip"), ("Command–C", "Copy and close"), ("Space", "Quick Look, or open a link"), ("Tab / Shift–Tab", "Switch shelf tabs"), ("Delete", "Delete selected history clips"), ("Escape", "Clear search, go back, or close")], id: \.0) { key, action in LabeledContent(action) { Text(key).font(.system(.caption, design: .monospaced)) } }
        }
    }
    var about: some View {
        Section("OpenShelf \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")") {
            Text("A little memory for your clipboard.").font(.title3)
            Text("Free and open source. Built with SwiftUI and AppKit for macOS 14 and later. MIT licensed.")
            Text("Independent implementation inspired by MinimalPaste. No affiliation. Source code and the feature-parity research ship with this app.").font(.caption).foregroundStyle(.secondary)
            Text("Updates are checked and installed by Sparkle when a signed release channel is configured.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var code: UInt32
    @Binding var modifiers: UInt32
    var onChange: () -> Void
    func makeNSView(context: Context) -> ShortcutButton { let button = ShortcutButton(); button.update = { newCode, newModifiers in code = newCode; modifiers = newModifiers; onChange() }; return button }
    func updateNSView(_ button: ShortcutButton, context: Context) { button.code = code; button.modifiers = modifiers; button.refreshTitle() }
}
final class ShortcutButton: NSButton {
    var code: UInt32 = 9
    var modifiers: UInt32 = UInt32(cmdKey | shiftKey)
    var update: ((UInt32, UInt32) -> Void)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); bezelStyle = .rounded; target = self; action = #selector(record); setAccessibilityLabel("Record activation shortcut") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func record() { recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override func resignFirstResponder() -> Bool { recording = false; refreshTitle(); return true }
    override func keyDown(with event: NSEvent) { capture(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { if recording { capture(event); return true }; return super.performKeyEquivalent(with: event) }
    func capture(_ event: NSEvent) {
        guard recording else { return }
        if event.keyCode == 53 { recording = false; refreshTitle(); return }
        guard !event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return }
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }; if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }; if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }; if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        code = UInt32(event.keyCode); modifiers = flags; recording = false; refreshTitle(); update?(code, modifiers)
    }
    func refreshTitle() {
        guard !recording else { return }
        var prefix = ""
        if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }; if modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }; if modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }; if modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
        let keys: [UInt32:String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",49:"Space"]
        title = prefix + (keys[code] ?? "Key \(code)")
    }
}


struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateController
    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updates.automaticChecks).disabled(!updates.configured)
            Button("Check for Updates…") { updates.checkForUpdates() }.disabled(!updates.canCheck)
            if updates.configured {
                Text("Checks once a day at \(updates.feedHost ?? "the release server"). Update downloads are verified before installation.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("This development build has no signed release channel. You can build newer versions from source.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
