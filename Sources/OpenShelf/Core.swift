import AppKit
import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import Carbon

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text, richText, link, image, file, color, video, audio
    var id: Self { self }
    var filterCategory: String { self == .richText ? "text" : rawValue }
    var title: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .link: return "Link"
        case .image: return "Image"
        case .file: return "File"
        case .color: return "Color"
        case .video: return "Video"
        case .audio: return "Audio"
        }
    }
    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
}

enum ShelfPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, left, right, window
    var id: Self { self }
}
enum WindowLayout: String, Codable, CaseIterable, Identifiable {
    case list, grid
    var id: Self { self }
}
enum ShelfBackground: String, Codable, CaseIterable, Identifiable {
    case liquidGlass, frostedGlass, image
    var id: Self { self }
}

enum ItemColors: String, Codable, CaseIterable { case colorful, softLight, softDark }

struct Settings: Codable, Equatable {
    var itemColors: ItemColors = .colorful
    var position: ShelfPosition = .bottom
    var floating = true
    var windowLayout: WindowLayout = .grid
    var background: ShelfBackground = .frostedGlass
    var backgroundImagePath = ""
    var backgroundBlur: Double = 20
    var backgroundDim: Double = 0.25
    var showTypeFilters = true
    var loadLinkPreviews = false
    var playSound = false
    var pasteDirectly = true
    var alwaysPlainText = false
    var ignoreConfidential = true
    var excludedApps = ["com.agilebits.onepassword7", "com.1password.1password", "com.bitwarden.desktop", "com.lastpass.LastPass", "com.apple.keychainaccess", "com.apple.Passwords"]
    var maxItems = 1000
    var maxAgeDays = 30
    var hotKeyCode: UInt32 = 9
    var hotKeyModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    var launchAtLogin = false
}

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var lastUsedAt = Date()
    var sourceName = ""
    var sourceBundleID = ""
    var kind: ClipKind = .text
    var text = ""
    var representations: [[String: Data]] = []
    var filePaths: [String] = []
    var pinned = false
    var groupIDs: Set<UUID> = []

    var title: String {
        if !filePaths.isEmpty { return filePaths.count == 1 ? URL(fileURLWithPath: filePaths[0]).lastPathComponent : "\(filePaths.count) files" }
        if !text.isEmpty { return String(text.prefix(240)) }
        return kind.title
    }
    var imageData: Data? {
        for item in representations {
            if let data = item[NSPasteboard.PasteboardType.png.rawValue] ?? item[NSPasteboard.PasteboardType.tiff.rawValue] { return data }
        }
        return nil
    }
    var isKept: Bool { pinned || !groupIDs.isEmpty }
    var fingerprint: String {
        var hasher = SHA256()
        if !representations.isEmpty {
            for item in representations {
                hasher.update(data: Data([0]))
                for key in item.keys.sorted() {
                    hasher.update(data: Data(key.utf8))
                    hasher.update(data: Data([0]))
                    hasher.update(data: item[key]!)
                }
            }
        } else {
            hasher.update(data: Data((kind.rawValue + "\0" + text + "\0" + filePaths.joined(separator: "\0")).utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || [text, title, sourceName, sourceBundleID, filePaths.joined(separator: " ")].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct Group: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: String
}
struct Folder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var path: String
}

@MainActor
final class Store: ObservableObject {
    @Published var clips: [Clip] = []
    @Published var groups: [Group] = []
    @Published var folders: [Folder] = []
    @Published var settings = Settings()
    @Published var paused = false
    @Published var errorMessage: String?
    private let directory: URL
    private var timer: Timer?
    private var lastChangeCount: Int
    private var sourceName = "Unknown"
    private var sourceBundleID = ""
    private var activationObserver: NSObjectProtocol?
    private var allowsSave = true
    private struct State: Codable {
        var schemaVersion = 1
        var clips: [Clip]
        var groups: [Group]
        var folders: [Folder]
        var settings: Settings
    }

    init(directory: URL? = nil, monitor: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenShelf", isDirectory: true)
        lastChangeCount = NSPasteboard.general.changeCount
        load()
        prune()
        if monitor {
            let active = NSWorkspace.shared.frontmostApplication
            sourceName = active?.localizedName ?? "Unknown"; sourceBundleID = active?.bundleIdentifier ?? ""
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.transitionSource(name: app.localizedName ?? "Unknown", bundleID: app.bundleIdentifier ?? "") }
            }
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.poll() }
            }
        }
    }
    deinit { timer?.invalidate(); if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) } }

    private func load() {
        let url = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
            guard state.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
            clips = state.clips
            groups = state.groups
            folders = state.folders
            settings = state.settings
        } catch {
            allowsSave = false
            let detail = error as NSError
            if detail.domain == NSCocoaErrorDomain && detail.code == NSFileReadNoPermissionError {
                errorMessage = "Saved history is temporarily inaccessible and has been preserved. Unlock this Mac, check folder access, then quit and reopen OpenShelf. \(error.localizedDescription)"
            } else {
                errorMessage = "Could not read saved history. The original file has been preserved at \(url.path). Quit OpenShelf and move that file aside to start fresh. \(error.localizedDescription)"
            }
        }
    }

    func save() {
        guard allowsSave else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent("history.json")
            let data = try JSONEncoder().encode(State(clips: clips, groups: groups, folders: folders, settings: settings))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            errorMessage = "Could not save history: \(error.localizedDescription)"
        }
    }

    private func skipsSource(_ bundleID: String) -> Bool {
        if settings.excludedApps.contains(bundleID) { return true }
        let passwordApps = ["1password", "onepassword", "bitwarden", "lastpass", "dashlane", "keepass", "enpass", "keychainaccess", "com.apple.Passwords"]
        return settings.ignoreConfidential && passwordApps.contains { bundleID.localizedCaseInsensitiveContains($0) }
    }
    func transitionSource(name: String, bundleID: String, pasteboard board: NSPasteboard = .general) {
        guard bundleID != sourceBundleID else { return }
        if board.changeCount != lastChangeCount {
            // Fail closed across excluded-app transitions; the writer cannot be established reliably.
            if !skipsSource(sourceBundleID), !skipsSource(bundleID) { capture(pasteboard: board, sourceName: sourceName, sourceBundleID: sourceBundleID) }
            lastChangeCount = board.changeCount
        }
        sourceName = name; sourceBundleID = bundleID
    }
    private func poll() {
        let app = NSWorkspace.shared.frontmostApplication
        if let bundleID = app?.bundleIdentifier, bundleID != sourceBundleID {
            transitionSource(name: app?.localizedName ?? "Unknown", bundleID: bundleID)
            return
        }
        let board = NSPasteboard.general
        guard board.changeCount != lastChangeCount else { return }
        lastChangeCount = board.changeCount
        capture(pasteboard: board, sourceName: sourceName, sourceBundleID: sourceBundleID)
    }

    func capture(pasteboard: NSPasteboard, sourceName: String, sourceBundleID: String) {
        guard !paused, allowsSave, !settings.excludedApps.contains(sourceBundleID) else { return }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        if settings.ignoreConfidential {
            let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword", "com.typeit4me.clipping"]
            guard !types.contains(where: { type in markers.contains(where: { type.hasPrefix($0) }) }) else { return }
            let passwordApps = ["1password", "onepassword", "bitwarden", "lastpass", "dashlane", "keepass", "enpass", "keychainaccess", "com.apple.Passwords"]
            guard !passwordApps.contains(where: { sourceBundleID.localizedCaseInsensitiveContains($0) }) else { return }
        }
        var reps: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var values: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { values[type.rawValue] = data }
            }
            if !values.isEmpty { reps.append(values) }
        }
        guard !reps.isEmpty else { return }
        let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        var text = pasteboard.string(forType: .string) ?? ""
        if text.isEmpty, let data = pasteboard.data(forType: .rtfd), let attributed = NSAttributedString(rtfd: data, documentAttributes: nil) { text = attributed.string }
        if text.isEmpty, let data = pasteboard.data(forType: .rtf), let attributed = NSAttributedString(rtf: data, documentAttributes: nil) { text = attributed.string }
        var kind: ClipKind = .text
        if !fileURLs.isEmpty {
            kind = .file
            if fileURLs.count == 1, let type = try? fileURLs[0].resourceValues(forKeys: [.contentTypeKey]).contentType {
                if type.conforms(to: .movie) { kind = .video }
                else if type.conforms(to: .audio) { kind = .audio }
            }
        } else if types.contains(NSPasteboard.PasteboardType.png.rawValue) || types.contains(NSPasteboard.PasteboardType.tiff.rawValue) {
            kind = .image
        } else if types.contains(NSPasteboard.PasteboardType.color.rawValue) {
            kind = .color
            if let color = NSColor(from: pasteboard)?.usingColorSpace(.deviceRGB) {
                text = String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
            }
        } else if Self.isColor(text) {
            kind = .color
        } else if types.contains(NSPasteboard.PasteboardType.URL.rawValue) || Self.isLink(text) {
            kind = .link
            if text.isEmpty { text = pasteboard.string(forType: .URL) ?? "" }
        } else if types.contains(NSPasteboard.PasteboardType.rtfd.rawValue) || types.contains(NSPasteboard.PasteboardType.rtf.rawValue) || types.contains(NSPasteboard.PasteboardType.html.rawValue) {
            kind = .richText
        }
        var clip = Clip(sourceName: sourceName, sourceBundleID: sourceBundleID, kind: kind, text: text, representations: reps, filePaths: fileURLs.map(\.path))
        if let index = clips.firstIndex(where: { $0.fingerprint == clip.fingerprint }) {
            let previous = clips.remove(at: index)
            clip.id = previous.id
            clip.createdAt = previous.createdAt
            clip.pinned = previous.pinned
            clip.groupIDs = previous.groupIDs
        }
        clips.insert(clip, at: 0)
        prune()
        save()
        if settings.playSound { NSSound(named: "Pop")?.play() }
    }

    static func isColor(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$", options: .regularExpression) != nil
    }
    static func isLink(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    func prune(now: Date = Date()) {
        let cutoff = settings.maxAgeDays > 0 ? now.addingTimeInterval(-Double(settings.maxAgeDays) * 86400) : .distantPast
        var retained = 0
        clips = clips.filter { clip in
            if clip.isKept { return true }
            guard clip.lastUsedAt >= cutoff else { return false }
            retained += 1
            return settings.maxItems <= 0 || retained <= settings.maxItems
        }
    }

    @discardableResult
    func write(_ selected: [Clip], plainText: Bool, pasteboard: NSPasteboard = .general) -> Bool {
        guard !selected.isEmpty else { return false }
        for path in selected.flatMap(\.filePaths) where !FileManager.default.fileExists(atPath: path) {
            errorMessage = "The file \(URL(fileURLWithPath: path).lastPathComponent) is no longer at its saved location."
            return false
        }
        let items: [NSPasteboardWriting]
        let canPlainText = selected.allSatisfy { !$0.text.isEmpty && $0.filePaths.isEmpty && ![.image, .video, .audio].contains($0.kind) }
        if plainText && canPlainText {
            items = [selected.map(\.text).joined(separator: "\n") as NSString]
        } else if selected.count > 1 && !selected.allSatisfy({ !$0.filePaths.isEmpty }) {
            items = [PasteComposer.item(for: selected, plainText: plainText)]
        } else {
            var output: [NSPasteboardWriting] = []
            for clip in selected {
                if !clip.filePaths.isEmpty {
                    for path in clip.filePaths {
                        guard FileManager.default.fileExists(atPath: path) else {
                            errorMessage = "The file \(URL(fileURLWithPath: path).lastPathComponent) is no longer at its saved location."
                            return false
                        }
                        output.append(URL(fileURLWithPath: path) as NSURL)
                    }
                } else if !clip.representations.isEmpty {
                    for rep in clip.representations {
                        let item = NSPasteboardItem()
                        for (type, data) in rep { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
                        output.append(item)
                    }
                } else {
                    output.append(clip.text as NSString)
                }
            }
            items = output
        }
        guard !items.isEmpty else { return false }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else {
            errorMessage = "Could not write the selected items to the clipboard."
            return false
        }
        if pasteboard.name == NSPasteboard.general.name { lastChangeCount = pasteboard.changeCount }
        let ids = Set(selected.map(\.id))
        for index in clips.indices where ids.contains(clips[index].id) { clips[index].lastUsedAt = Date() }
        save()
        return true
    }

    func togglePin(_ id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].pinned.toggle()
        save()
    }
    func setGroup(ids: Set<UUID>, groupID: UUID) {
        guard groups.contains(where: { $0.id == groupID }) else { return }
        for index in clips.indices where ids.contains(clips[index].id) { clips[index].groupIDs.insert(groupID) }
        save()
    }
    func removeFromGroup(ids: Set<UUID>, groupID: UUID) {
        for index in clips.indices where ids.contains(clips[index].id) { clips[index].groupIDs.remove(groupID) }
        save()
    }
    func keep(_ clip: Clip, groupID: UUID? = nil) {
        if !clips.contains(where: { $0.id == clip.id }) { clips.insert(clip, at: 0) }
        if let groupID { setGroup(ids: [clip.id], groupID: groupID) }
        else if let index = clips.firstIndex(where: { $0.id == clip.id }) { clips[index].pinned = true; save() }
    }
    func remove(ids: Set<UUID>) { clips.removeAll { ids.contains($0.id) }; save() }
    func clearHistory() { clips.removeAll { !$0.isKept }; save() }
    func addGroup(name: String, color: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        groups.append(Group(name: trimmed, color: color))
        save()
    }
    func removeGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        for index in clips.indices { clips[index].groupIDs.remove(id) }
        prune()
        save()
    }
    func addFolder(_ url: URL) {
        let normalized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory), isDirectory.boolValue else { errorMessage = "Choose a folder that exists on this Mac."; return }
        guard !folders.contains(where: { $0.path == normalized.path }) else { return }
        folders.append(Folder(name: normalized.lastPathComponent, path: normalized.path))
        save()
    }
    func removeFolder(_ id: UUID) { folders.removeAll { $0.id == id }; save() }

    func folderContents(folder: Folder, subpath: String = "") -> [Clip] {
        let root = URL(fileURLWithPath: folder.path).standardizedFileURL.resolvingSymlinksInPath()
        let target = root.appendingPathComponent(subpath).standardizedFileURL.resolvingSymlinksInPath()
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else { errorMessage = "This folder is outside the selected folder."; return [] }
        do {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .contentTypeKey]
            let urls = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            return urls.map { url in
                let metadata = try? url.resourceValues(forKeys: Set(keys))
                var kind: ClipKind = .file
                if metadata?.contentType?.conforms(to: .movie) == true { kind = .video }
                else if metadata?.contentType?.conforms(to: .audio) == true { kind = .audio }
                let bytes = Array(SHA256.hash(data: Data(url.path.utf8)).prefix(16))
                let id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
                let date = metadata?.contentModificationDate ?? .distantPast
                let saved = clips.first { $0.id == id }
                return Clip(id: id, createdAt: date, lastUsedAt: date, sourceName: folder.name, kind: kind, text: url.lastPathComponent, filePaths: [url.path], pinned: saved?.pinned ?? false, groupIDs: saved?.groupIDs ?? [])
            }.sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = "Could not open \(target.lastPathComponent): \(error.localizedDescription)"
            return []
        }
    }
}
