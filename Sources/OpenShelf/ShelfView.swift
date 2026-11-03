import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookUI
import LinkPresentation
import CryptoKit

extension Color {
    init(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if digits.count == 3 || digits.count == 4 { digits = digits.map { "\($0)\($0)" }.joined() }
        let alpha = digits.count == 8
        let value = UInt64(digits, radix: 16) ?? 0x8E8E93
        let rgb = alpha ? value >> 8 : value
        self.init(.sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: alpha ? Double(value & 255) / 255 : 1)
    }
}

struct ShelfView: View {
    @ObservedObject var store: Store
    @ObservedObject var app: AppDelegate
    @State private var search = ""
    @State private var tab = "history"
    @State private var types: Set<String> = []
    @State private var selected: Set<UUID> = []
    @State private var focused: UUID?
    @State private var anchor: UUID?
    @State private var groupEditor: Group?
    @State private var creatingGroup = false
    @State private var groupName = ""
    @State private var groupColor = "#0A84FF"
    @State private var folderPath = ""
    @State private var folderItems: [Clip] = []
    @State private var showingShortcuts = false
    @State private var savePicker = false
    @State private var clipsForNewGroup: [Clip] = []
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    var horizontal: Bool { store.settings.position.rawValue == "bottom" }
    var folder: Folder? { store.folders.first { $0.id.uuidString == tab } }
    var group: Group? { store.groups.first { $0.id.uuidString == tab } }
    var items: [Clip] {
        let base: [Clip]
        if folder != nil { base = folderItems }
        else if tab == "pinned" { base = store.clips.filter { $0.pinned || !$0.groupIDs.isEmpty } }
        else if let group { base = store.clips.filter { $0.groupIDs.contains(group.id) } }
        else { base = store.clips }
        return base.filter { clip in
            (types.isEmpty || types.contains(clip.kind.filterCategory)) && (search.isEmpty || "\(clip.text) \(clip.sourceName) \(clip.filePaths.joined(separator: " "))".localizedStandardContains(search))
        }
    }
    var chosen: [Clip] { items.filter { selected.contains($0.id) } }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if !horizontal { tabs.padding(.horizontal, 16).padding(.bottom, 8) }
            if store.settings.showTypeFilters { filters }
            if folder != nil { breadcrumbs }
            if let message = store.errorMessage ?? app.feedback {
                HStack {
                    Image(systemName: "info.circle")
                    Text(message).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { store.errorMessage = nil; app.feedback = nil }.buttonStyle(.borderless)
                }.padding(10).background(.yellow.opacity(0.15))
            }
            if items.isEmpty { emptyState }
            else { content }
            footer
        }
        .background { ShelfBackdrop(store: store) }
        .preferredColorScheme(store.settings.itemColors == .softDark ? .dark : nil)
        .clipShape(RoundedRectangle(cornerRadius: store.settings.floating ? 22 : 0))
        .onAppear { searchFocused = true; focused = items.first?.id; installKeys(); refreshFolder() }
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
        .onChange(of: search) { _, _ in resetSelection() }
        .onChange(of: types) { _, _ in resetSelection() }
        .onChange(of: tab) { _, _ in folderPath = ""; refreshFolder(); resetSelection() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in if folder != nil { refreshFolder() } }
        .sheet(isPresented: $savePicker) { saveSheet }
        .sheet(isPresented: $creatingGroup) { groupSheet }
        .sheet(item: $groupEditor) { existing in editGroupSheet(existing) }
    }
    var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard and folders", text: $search).textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Search clipboard and folders")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
            }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 9)).frame(maxWidth: horizontal ? 260 : .infinity)
            if horizontal { tabs }
            Menu {
                Button("New Group…", systemImage: "plus.circle") { creatingGroup = true }
                Button("Add Folder…", systemImage: "folder.badge.plus") { app.addFolder() }
                if let folder { Button("Remove Folder Tab", role: .destructive) { store.removeFolder(folder.id); tab = "history" } }
            } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("New group or folder")
            if horizontal { Spacer(minLength: 0) }
            Button { app.showSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .overlay(alignment: .bottom) { if !horizontal { EmptyView() } }
    }
    var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tabButton("Clipboard", icon: "clock.arrow.circlepath", key: "history")
                tabButton("Pinned", icon: "pin", key: "pinned")
                ForEach(store.folders) { f in tabButton(f.name, icon: "folder", key: f.id.uuidString) }
                ForEach(store.groups) { g in
                    Button { tab = g.id.uuidString } label: {
                        HStack(spacing: 5) { Circle().fill(Color(hex: g.color)).frame(width: 8, height: 8); Text(g.name).lineLimit(1) }
                            .padding(.horizontal, 10).padding(.vertical, 6).background(tab == g.id.uuidString ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit Group…") { groupEditor = g }
                        Button("Delete Group", role: .destructive) { store.removeGroup(g.id); if tab == g.id.uuidString { tab = "history" } }
                    }
                    .onDrop(of: ["org.openshelf.clip-reference"], isTargeted: nil) { providers in
                        for provider in providers {
                            _ = provider.loadDataRepresentation(forTypeIdentifier: "org.openshelf.clip-reference") { data, _ in
                                guard let data, let string = String(data: data, encoding: .utf8) else { return }
                                let ids = Set(string.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
                                Task { @MainActor in
                                    for clip in folderItems where ids.contains(clip.id) { persistFolderClip(clip) }
                                    store.setGroup(ids: ids, groupID: g.id)
                                }
                            }
                        }
                        return !providers.isEmpty
                    }
                }
            }.font(.system(size: 12, weight: .medium))
        }
    }
    func tabButton(_ title: String, icon: String, key: String) -> some View {
        Button { tab = key } label: { Label(title, systemImage: icon).padding(.horizontal, 10).padding(.vertical, 6).background(tab == key ? Color.accentColor.opacity(0.2) : .clear, in: Capsule()) }.buttonStyle(.plain)
    }
    var filters: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("All") { types = [] }.buttonStyle(.bordered).tint(types.isEmpty ? .accentColor : .gray)
                    ForEach(["text", "image", "video", "audio", "link", "file", "color"], id: \.self) { type in
                        Button { if types.contains(type) { types.remove(type) } else { types.insert(type) } } label: { Label(type == "richText" ? "Rich Text" : type.capitalized, systemImage: symbol(type)) }
                            .buttonStyle(.bordered).tint(types.contains(type) ? .accentColor : .gray)
                    }
                }.controlSize(.small)
            }
        }.padding(.horizontal, 16).padding(.bottom, 8)
    }
    var breadcrumbs: some View {
        HStack {
            Button { folderPath = ""; refreshFolder() } label: { Label(folder?.name ?? "Folder", systemImage: "folder") }
            if !folderPath.isEmpty {
                Image(systemName: "chevron.right").font(.caption)
                Text(folderPath).lineLimit(1).truncationMode(.head)
                Button { goBack() } label: { Image(systemName: "arrow.up") }.help("Go to parent folder")
            }
            Spacer()
            Button { refreshFolder() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh folder")
        }.buttonStyle(.borderless).font(.caption).padding(.horizontal, 16).padding(.bottom, 8)
    }
    @ViewBuilder var content: some View {
        ScrollViewReader { proxy in
            SwiftUI.Group {
                if horizontal {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) { ForEach(items) { clip in clipCell(clip, compact: false).frame(width: 238).id(clip.id) } }.padding(.horizontal, 16).padding(.vertical, 4)
                    }
                } else if store.settings.position.rawValue == "window" && store.settings.windowLayout.rawValue == "grid" {
                    ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: 12) { ForEach(items) { clip in clipCell(clip, compact: false).frame(height: 230).id(clip.id) } }.padding(16) }
                } else {
                    ScrollView { LazyVStack(spacing: 8) { ForEach(items) { clip in clipCell(clip, compact: true).id(clip.id) } }.padding(.horizontal, 16).padding(.vertical, 4) }
                }
            }.onChange(of: focused) { _, value in if let value { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value, anchor: .center) } } }
        }
    }
    func clipCell(_ clip: Clip, compact: Bool) -> some View {
        ClipCard(clip: clip, compact: compact, loadPreviews: store.settings.loadLinkPreviews, itemColors: store.settings.itemColors, selected: selected.contains(clip.id) || (selected.isEmpty && focused == clip.id))
            .overlay(alignment: .topTrailing) {
                if showingShortcuts, let index = items.firstIndex(where: { $0.id == clip.id }), index < 9 {
                    Text("⌘\(index + 1)").font(.system(.caption, design: .monospaced)).padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)).padding(8).allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(count: 2) { activate(clip) }
            .onTapGesture { select(clip, modifiers: NSEvent.modifierFlags) }
            .contextMenu {
                Button("Paste") { app.paste([clip]) }
                Button("Paste as Plain Text") { app.paste([clip], plainText: true) }
                Button("Copy Only") { app.paste([clip], copyOnly: true) }
                Button("Quick Look") { app.preview(clip) }
                Divider()
                Button(clip.pinned ? "Unpin" : "Pin") { persistFolderClip(clip); store.togglePin(clip.id) }
                Menu("Pin To") { ForEach(store.groups) { g in Button(g.name) { persistFolderClip(clip); store.setGroup(ids: [clip.id], groupID: g.id) } } }
                if let group { Button("Remove from Group") { if let index = store.clips.firstIndex(where: { $0.id == clip.id }) { store.clips[index].groupIDs.remove(group.id); store.save() } } }
                if !clip.filePaths.isEmpty { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(clip.filePaths.map { URL(fileURLWithPath: $0) }) } }
                if folder == nil { Divider(); Button("Delete", role: .destructive) { store.remove(ids: [clip.id]) } }
            }
            .onDrag { dragProvider(clip) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(clip.kind.rawValue), \(clip.text.prefix(160))\(clip.pinned ? ", pinned" : "")")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate(clip) }
    }
    func dragProvider(_ clip: Clip) -> NSItemProvider {
        let provider: NSItemProvider
        if let path = clip.filePaths.first { provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider() }
        else if let image = clipImage(clip) { provider = NSItemProvider(object: image) }
        else { provider = NSItemProvider(object: clip.text as NSString) }
        let draggedIDs = selected.contains(clip.id) ? selected : [clip.id]
        provider.registerDataRepresentation(forTypeIdentifier: "org.openshelf.clip-reference", visibility: .ownProcess) { completion in completion(draggedIDs.map(\.uuidString).sorted().joined(separator: ",").data(using: .utf8), nil); return nil }
        return provider
    }
    func persistFolderClip(_ clip: Clip) {
        if !store.clips.contains(where: { $0.id == clip.id }) { store.clips.insert(clip, at: 0) }
    }
    var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.paused ? "pause.circle" : "clipboard").font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
            Text(store.paused ? "Clipboard history is paused" : search.isEmpty ? "Nothing here yet" : "No matches").font(.title3.weight(.medium))
            Text(store.paused ? "Resume recording from the menu bar." : folder != nil ? "Files in this folder appear here. Search filters this folder." : "Copy something in any app, then press ⇧⌘V. Pin what you reuse.").foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
    var footer: some View {
        HStack(spacing: 12) {
            Text(selected.isEmpty ? "\(items.count) items" : "\(selected.count) selected").monospacedDigit()
            Spacer()
            if !selected.isEmpty { Button("Paste Selection") { app.paste(chosen) }.buttonStyle(.borderless) }
            Text("↑ ↓ navigate   ↵ paste   ⌘S save   Esc close").lineLimit(1).minimumScaleFactor(0.7)
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
    }
    var saveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save to Group").font(.headline)
            Button("Pin to Favorites") {
                for clip in saveCandidates { store.keep(clip) }; savePicker = false
            }
            ForEach(store.groups) { group in
                Button { for clip in saveCandidates { store.keep(clip, groupID: group.id) }; savePicker = false } label: { Label(group.name, systemImage: "circle.fill").foregroundStyle(Color(hex: group.color)) }
            }
            Divider()
            Button("New Group…") { clipsForNewGroup = saveCandidates; savePicker = false; creatingGroup = true }
            HStack { Spacer(); Button("Cancel") { savePicker = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 320)
    }
    var saveCandidates: [Clip] { selected.isEmpty ? items.filter { $0.id == focused } : chosen }
    var groupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Group").font(.headline)
            TextField("Group name", text: $groupName).onSubmit { createGroup() }
            colorPicker
            HStack { Spacer(); Button("Cancel") { clipsForNewGroup = []; creatingGroup = false }; Button("Create") { createGroup() }.keyboardShortcut(.defaultAction).disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 340)
    }
    func editGroupSheet(_ existing: Group) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Group").font(.headline)
            TextField("Group name", text: $groupName)
            colorPicker
            HStack { Spacer(); Button("Cancel") { groupEditor = nil }; Button("Save") {
                if let index = store.groups.firstIndex(where: { $0.id == existing.id }) { store.groups[index].name = groupName; store.groups[index].color = groupColor; store.save() }; groupEditor = nil
            }.keyboardShortcut(.defaultAction).disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 340).onAppear { groupName = existing.name; groupColor = existing.color }
    }
    var colorPicker: some View {
        HStack { ForEach(["#FF453A", "#FF9F0A", "#FFD60A", "#30D158", "#64D2FF", "#0A84FF", "#BF5AF2", "#FF375F", "#8E8E93"], id: \.self) { color in
            Button { groupColor = color } label: { Circle().fill(Color(hex: color)).frame(width: 22, height: 22).overlay(Circle().stroke(groupColor == color ? Color.primary : .clear, lineWidth: 2).padding(-3)) }.buttonStyle(.plain).accessibilityLabel("Group color \(color)")
        } }
    }
    func createGroup() { let name = groupName.trimmingCharacters(in: .whitespaces); guard !name.isEmpty else { return }; store.addGroup(name: name, color: groupColor); if let group = store.groups.last { for clip in clipsForNewGroup { store.keep(clip, groupID: group.id) } }; clipsForNewGroup = []; creatingGroup = false; groupName = "" }
    func resetSelection() { selected = []; focused = items.first?.id; anchor = nil }
    func refreshFolder() { if let folder { folderItems = store.folderContents(folder: folder, subpath: folderPath) } else { folderItems = [] } }
    func goBack() { folderPath = (folderPath as NSString).deletingLastPathComponent; refreshFolder(); resetSelection() }
    func select(_ clip: Clip, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor, let start = items.firstIndex(where: { $0.id == anchor }), let end = items.firstIndex(where: { $0.id == clip.id }) { selected.formUnion(items[min(start, end)...max(start, end)].map(\.id)) }
        else if modifiers.contains(.command) { if selected.contains(clip.id) { selected.remove(clip.id) } else { selected.insert(clip.id) }; anchor = clip.id }
        else { selected = [clip.id]; anchor = clip.id }
        focused = clip.id
    }
    func activate(_ clip: Clip) {
        if let path = clip.filePaths.first {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue, let folder {
                let base = URL(fileURLWithPath: folder.path).standardizedFileURL.path
                let full = URL(fileURLWithPath: path).standardizedFileURL.path
                guard full.hasPrefix(base + "/") else { return }
                folderPath = String(full.dropFirst(base.count + 1)); refreshFolder(); resetSelection(); return
            }
        }
        app.paste(selected.count > 1 ? chosen : [clip])
    }
    func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard NSApp.keyWindow === app.panel, !creatingGroup, !savePicker, groupEditor == nil else { return event }
            if event.type == .flagsChanged { showingShortcuts = event.modifierFlags.contains(.command); return event }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," { app.showSettings(); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "f" { searchFocused = true; return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "s" { savePicker = true; return nil }
            if event.modifierFlags.contains(.command), event.keyCode == 126, folder != nil { goBack(); return nil }
            if event.modifierFlags.contains(.command), event.keyCode == 125, let clip = items.first(where: { $0.id == focused }) { activate(clip); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a", !searchFocused { selected = Set(items.map(\.id)); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c", !searchFocused, let clip = items.first(where: { $0.id == focused }) { app.paste(selected.count > 1 ? chosen : [clip], copyOnly: true); return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "p", let clip = items.first(where: { $0.id == focused }) { persistFolderClip(clip); store.togglePin(clip.id); return nil }
            if event.modifierFlags.contains(.command), let value = Int(event.charactersIgnoringModifiers ?? ""), value > 0, value <= items.count, value <= 9 { app.paste([items[value - 1]]); return nil }
            if [123,124,125,126].contains(event.keyCode) {
                if searchFocused && [123,124].contains(event.keyCode) { return event }
                searchFocused = false
                let index = items.firstIndex(where: { $0.id == focused }) ?? -1
                let delta = event.keyCode == 123 || event.keyCode == 126 ? -1 : 1
                guard !items.isEmpty else { return nil }
                let next = items[max(0, min(items.count - 1, index + delta))]
                if event.modifierFlags.contains(.shift) { select(next, modifiers: .shift) } else { focused = next.id; selected = []; anchor = next.id }
                return nil
            }
            if event.keyCode == 36, let clip = items.first(where: { $0.id == focused }) { activate(clip); return nil }
            if event.keyCode == 49, !searchFocused, let clip = items.first(where: { $0.id == focused }) { app.preview(clip); return nil }
            if event.keyCode == 53 { if !search.isEmpty { search = "" } else if !folderPath.isEmpty { goBack() } else { app.panel?.orderOut(nil) }; return nil }
            if event.keyCode == 51, !searchFocused, folder == nil { store.remove(ids: selected.isEmpty ? Set([focused].compactMap { $0 }) : selected); resetSelection(); return nil }
            if event.keyCode == 48 {
                let keys = ["history", "pinned"] + store.folders.map { $0.id.uuidString } + store.groups.map { $0.id.uuidString }
                let index = keys.firstIndex(of: tab) ?? 0
                tab = keys[(index + (event.modifierFlags.contains(.shift) ? keys.count - 1 : 1)) % keys.count]
                return nil
            }
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty, !(event.characters ?? "").isEmpty { searchFocused = true }
            return event
        }
    }
}

func symbol(_ kind: String) -> String {
    switch kind { case "image": return "photo"; case "link": return "link"; case "color": return "paintpalette"; case "file": return "doc"; case "video": return "video"; case "audio": return "waveform"; case "richText": return "textformat"; default: return "text.alignleft" }
}
func clipImage(_ clip: Clip) -> NSImage? {
    for representation in clip.representations {
        for type in [NSPasteboard.PasteboardType.png.rawValue, NSPasteboard.PasteboardType.tiff.rawValue] { if let data = representation[type], let image = NSImage(data: data) { return image } }
    }
    return nil
}

struct ClipCard: View {
    let clip: Clip
    let compact: Bool
    let loadPreviews: Bool
    let itemColors: ItemColors
    let selected: Bool
    var tint: Color {
        switch clip.kind.rawValue { case "link": return .cyan; case "image": return .purple; case "color": return Color(hex: clip.text); case "file": return .orange; default: return .blue }
    }
    var body: some View {
        SwiftUI.Group {
            if compact {
                HStack(spacing: 12) {
                    thumbnail.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 4) { Text(clip.text.isEmpty ? clip.kind.rawValue.capitalized : clip.text).lineLimit(2).font(.system(size: 13, weight: .medium)); metadata }
                    Spacer(minLength: 0)
                    if clip.pinned || !clip.groupIDs.isEmpty { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                }.padding(10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) { Text(clip.kind.rawValue == "richText" ? "Rich Text" : clip.kind.rawValue.capitalized).font(.system(size: 12, weight: .semibold)); Text(clip.createdAt, style: .relative).font(.system(size: 10)).opacity(0.8) }
                        Spacer()
                        if clip.pinned || !clip.groupIDs.isEmpty { Image(systemName: "pin.fill").font(.caption) }
                        Image(nsImage: appIcon).resizable().frame(width: 24, height: 24)
                    }.padding(10).background(tint.opacity(itemColors == .softLight ? 0.22 : itemColors == .softDark ? 0.4 : 0.8))
                    thumbnail.frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
                    HStack(alignment: .bottom) { VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1); Text(clip.sourceName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Image(systemName: symbol(clip.kind.rawValue)).font(.caption).foregroundStyle(.secondary) }.padding(10)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.09), lineWidth: selected ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    var title: String { clip.filePaths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? (clip.text.isEmpty ? clip.kind.rawValue.capitalized : clip.text) }
    var metadata: some View { HStack { Text(clip.sourceName); Text("·"); Text(clip.createdAt, style: .relative) }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
    var appIcon: NSImage { NSWorkspace.shared.urlForApplication(withBundleIdentifier: clip.sourceBundleID).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)! }
    @ViewBuilder var thumbnail: some View {
        if clip.kind.rawValue == "color" { RoundedRectangle(cornerRadius: 8).fill(Color(hex: clip.text)).overlay(alignment: .bottom) { if !compact { Text(clip.text).font(.system(.caption, design: .monospaced)).padding(8).background(.regularMaterial, in: Capsule()).padding(8) } } }
        else if let image = clipImage(clip) { Image(nsImage: image).resizable().scaledToFit() }
        else if let path = clip.filePaths.first { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit() }
        else if clip.kind.rawValue == "link", loadPreviews, let url = URL(string: clip.text) { LinkCardPreview(url: url) }
        else if compact { Image(systemName: symbol(clip.kind.rawValue)).font(.title2).foregroundStyle(tint) }
        else { Text(clip.text).font(.system(size: 14, design: .default)).lineLimit(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
    }
}

struct ShelfBackdrop: View {
    @ObservedObject var store: Store
    var body: some View {
        ZStack {
            switch store.settings.background.rawValue {
            case "image":
                Rectangle().fill(.ultraThinMaterial)
                if let image = NSImage(contentsOfFile: store.settings.backgroundImagePath) { GeometryReader { geo in Image(nsImage: image).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped().blur(radius: store.settings.backgroundBlur).overlay(.black.opacity(store.settings.backgroundDim)) } }
            case "frostedGlass": Rectangle().fill(.regularMaterial)
            default:
                #if compiler(>=6.2)
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: .rect(cornerRadius: store.settings.floating ? 22 : 0))
                } else { Rectangle().fill(.ultraThinMaterial) }
                #else
                Rectangle().fill(.ultraThinMaterial)
                #endif
            }
        }
    }
}

struct ClipPreview: View {
    let clip: Clip
    var body: some View {
        if let path = clip.filePaths.first { FileQuickLook(url: URL(fileURLWithPath: path)) }
        else if let image = clipImage(clip) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
        else { ScrollView { Text(clip.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
    }
}
struct FileQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { QLPreviewView(frame: .zero, style: .normal)! }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}

@MainActor final class LinkCache {
    static let shared = LinkCache()
    var values: [URL: LPLinkMetadata] = [:]
    var pending: [URL: Task<LPLinkMetadata?, Never>] = [:]
    private var providers: [URL: LPMetadataProvider] = [:]
    private var generation = UUID()
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenShelf/LinkPreviews")
    func key(_ url: URL) -> String { SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() }
    func clear() throws {
        generation = UUID()
        for provider in providers.values { provider.cancel() }
        for task in pending.values { task.cancel() }
        providers = [:]; pending = [:]; values = [:]
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func metadata(_ url: URL) async -> LPLinkMetadata? {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        if let cached = values[url] { return cached }
        let file = directory.appendingPathComponent(key(url))
        if let data = try? Data(contentsOf: file), let value = try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data) { values[url] = value; return value }
        if let task = pending[url] { return await task.value }
        let requestGeneration = generation
        let provider = LPMetadataProvider(); provider.timeout = 8
        providers[url] = provider
        let task = Task<LPLinkMetadata?, Never> {
            return try? await provider.startFetchingMetadata(for: url)
        }
        pending[url] = task
        let value = await task.value
        guard generation == requestGeneration, !task.isCancelled else { return nil }
        pending[url] = nil; providers[url] = nil
        if let value {
            values[url] = value
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true) { try? data.write(to: file, options: .atomic) }
        }
        return value
    }
}
struct LinkCardPreview: View {
    let url: URL
    @State private var metadata: LPLinkMetadata?
    var body: some View {
        SwiftUI.Group { if let metadata { NativeLinkView(metadata: metadata) } else { VStack(alignment: .leading, spacing: 8) { Image(systemName: "link").font(.title); Text(url.host ?? url.absoluteString).font(.headline); Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(3) }.frame(maxWidth: .infinity, alignment: .leading) } }
            .task(id: url) { metadata = await LinkCache.shared.metadata(url) }
    }
}
struct NativeLinkView: NSViewRepresentable {
    let metadata: LPLinkMetadata
    func makeNSView(context: Context) -> LPLinkView { LPLinkView(metadata: metadata) }
    func updateNSView(_ view: LPLinkView, context: Context) { view.metadata = metadata }
}
