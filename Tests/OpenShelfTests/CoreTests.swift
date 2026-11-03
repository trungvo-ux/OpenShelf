import XCTest
import AppKit
@testable import OpenShelf

final class CoreTests: XCTestCase {
    @MainActor
    private func makeStore() -> (Store, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-test-\(UUID().uuidString)")
        return (Store(directory: directory, monitor: false), directory)
    }
    private func board() -> NSPasteboard { NSPasteboard(name: .init("openshelf-tests-\(UUID().uuidString)")) }

    @MainActor
    func testCapturePreservesRichRepresentationsAndDedupOwnership() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        let rich = Data("<b>Hello</b>".utf8)
        item.setString("Hello", forType: .string)
        item.setData(rich, forType: .html)
        pasteboard.writeObjects([item])
        store.capture(pasteboard: pasteboard, sourceName: "Test", sourceBundleID: "test")
        XCTAssertEqual(store.clips.count, 1)
        XCTAssertEqual(store.clips[0].kind, .richText)
        XCTAssertEqual(store.clips[0].representations[0][NSPasteboard.PasteboardType.html.rawValue], rich)
        let id = try XCTUnwrap(store.clips.first?.id)
        store.togglePin(id)
        store.addGroup(name: "Work", color: "#FF0000")
        store.setGroup(ids: [id], groupID: store.groups[0].id)
        store.capture(pasteboard: pasteboard, sourceName: "Test", sourceBundleID: "test")
        XCTAssertEqual(store.clips.count, 1)
        XCTAssertEqual(store.clips[0].id, id)
        XCTAssertTrue(store.clips[0].pinned)
        XCTAssertEqual(store.clips[0].groupIDs, [store.groups[0].id])
    }

    @MainActor
    func testConfidentialAndExcludedCopiesNeverPersist() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("secret", forType: .string)
        pasteboard.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        store.capture(pasteboard: pasteboard, sourceName: "Test", sourceBundleID: "test")
        XCTAssertTrue(store.clips.isEmpty)
        pasteboard.clearContents()
        pasteboard.setString("secret", forType: .string)
        store.capture(pasteboard: pasteboard, sourceName: "1Password", sourceBundleID: "com.1password.1password")
        XCTAssertTrue(store.clips.isEmpty)
        store.settings.excludedApps.append("test.excluded")
        store.capture(pasteboard: pasteboard, sourceName: "Test", sourceBundleID: "test.excluded")
        XCTAssertTrue(store.clips.isEmpty)
        store.paused = true
        store.capture(pasteboard: pasteboard, sourceName: "Test", sourceBundleID: "test")
        XCTAssertTrue(store.clips.isEmpty)
    }

    @MainActor
    func testRetentionAndClearPreservePinnedAndGroupedItems() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = Date().addingTimeInterval(-100 * 86400)
        let group = UUID()
        store.clips = [Clip(lastUsedAt: old, text: "pin", pinned: true), Clip(lastUsedAt: old, text: "group", groupIDs: [group]), Clip(lastUsedAt: old, text: "expired"), Clip(text: "recent"), Clip(text: "overflow")]
        store.settings.maxItems = 1
        store.settings.maxAgeDays = 30
        store.prune()
        XCTAssertEqual(store.clips.map(\.text), ["pin", "group", "recent"])
        store.clearHistory()
        XCTAssertEqual(store.clips.map(\.text), ["pin", "group"])
    }

    @MainActor
    func testSaveReloadAndCorruptFilePreservation() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.clips = [Clip(text: "saved", pinned: true)]
        store.addGroup(name: "Work", color: "#112233")
        store.settings.maxAgeDays = 0
        store.save()
        let restored = Store(directory: directory, monitor: false)
        XCTAssertEqual(restored.clips, store.clips)
        XCTAssertEqual(restored.groups, store.groups)
        XCTAssertEqual(restored.settings, store.settings)
        let url = directory.appendingPathComponent("history.json")
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: url)
        let broken = Store(directory: directory, monitor: false)
        XCTAssertNotNil(broken.errorMessage)
        broken.save()
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    @MainActor
    func testBulkTextAndRichPasteboardWriting() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(store.write([Clip(text: "one"), Clip(text: "two")], plainText: false, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "one\ntwo")
        let rich = Clip(kind: .richText, text: "hello", representations: [[NSPasteboard.PasteboardType.html.rawValue: Data("<b>hello</b>".utf8), NSPasteboard.PasteboardType.string.rawValue: Data("hello".utf8)]])
        XCTAssertTrue(store.write([rich], plainText: false, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.data(forType: .html), Data("<b>hello</b>".utf8))
        XCTAssertTrue(store.write([rich], plainText: true, pasteboard: pasteboard))
        XCTAssertNil(pasteboard.data(forType: .html))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
    }

    @MainActor
    func testFolderStableIDsAndTraversalBoundary() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("test".utf8).write(to: root.appendingPathComponent("test.txt"))
        store.addFolder(root)
        let first = store.folderContents(folder: store.folders[0])
        let second = store.folderContents(folder: store.folders[0])
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(store.folderContents(folder: store.folders[0], subpath: "../..").isEmpty)
        store.removeFolder(store.folders[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("test.txt").path))
    }
    @MainActor
    func testImagesKeepTheirPayloadWhenPlainTextIsRequested() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let payload = try XCTUnwrap(bitmap.tiffRepresentation)
        let clip = Clip(kind: .image, representations: [[NSPasteboard.PasteboardType.tiff.rawValue: payload]])
        XCTAssertTrue(store.write([clip], plainText: true, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.data(forType: .tiff), payload)
    }

    @MainActor
    func testMissingFileDoesNotEraseClipboard() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("existing content", forType: .string)
        let missing = Clip(kind: .file, text: "missing", filePaths: [directory.appendingPathComponent("missing").path])
        XCTAssertFalse(store.write([missing], plainText: false, pasteboard: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "existing content")
    }

    @MainActor
    func testExcludedSourceTransitionsDiscardAmbiguousCopies() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        store.transitionSource(name: "Editor", bundleID: "test.editor", pasteboard: pasteboard)
        pasteboard.setString("ambiguous copy on entering password app", forType: .string)
        store.transitionSource(name: "Password App", bundleID: "com.1password.1password", pasteboard: pasteboard)
        pasteboard.clearContents(); pasteboard.setString("secret on leaving password app", forType: .string)
        store.transitionSource(name: "Editor", bundleID: "test.editor", pasteboard: pasteboard)
        XCTAssertTrue(store.clips.isEmpty)
        pasteboard.clearContents(); pasteboard.setString("ordinary outgoing copy", forType: .string)
        store.transitionSource(name: "Other", bundleID: "test.other", pasteboard: pasteboard)
        XCTAssertEqual(store.clips.map(\.text), ["ordinary outgoing copy"])
        XCTAssertEqual(store.clips.first?.sourceBundleID, "test.editor")
    }

    @MainActor
    func testPreviewCacheKeysIncludeTheEntireURL() async throws {
        let prefix = "https://example.com/" + String(repeating: "a", count: 250)
        let one = try XCTUnwrap(URL(string: prefix + "?page=one"))
        let two = try XCTUnwrap(URL(string: prefix + "?page=two"))
        XCTAssertNotEqual(LinkCache.shared.key(one), LinkCache.shared.key(two))
        XCTAssertEqual(LinkCache.shared.key(one), LinkCache.shared.key(one))
        XCTAssertEqual(LinkCache.shared.key(one).count, 64)
    }

    @MainActor
    func testNativeColorCaptureAndRoundTrip() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes([.color], owner: nil)
        let color = NSColor(deviceRed: 1, green: 0.5, blue: 0.25, alpha: 1)
        color.write(to: pasteboard)
        XCTAssertNotNil(NSColor(from: pasteboard))
        store.capture(pasteboard: pasteboard, sourceName: "Color Fixture", sourceBundleID: "test.color")
        let clip = try XCTUnwrap(store.clips.first)
        XCTAssertEqual(clip.kind, .color)
        XCTAssertEqual(clip.text, "#FF8040")
        pasteboard.clearContents()
        XCTAssertTrue(store.write([clip], plainText: false, pasteboard: pasteboard))
        let restored = try XCTUnwrap(NSColor(from: pasteboard)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(restored.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(restored.greenComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(restored.blueComponent, 0.25, accuracy: 0.01)
    }

}
