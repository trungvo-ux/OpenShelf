import XCTest
import AppKit
@testable import OpenShelf

final class PasteComposerTests: XCTestCase {
    @MainActor
    func testBulkRichTextPreservesFormattingAndOrder() async throws {
        let rich = NSAttributedString(string: "Bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 17)])
        let data = try XCTUnwrap(rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]))
        let clips = [Clip(kind: .richText, text: "Bold", representations: [[NSPasteboard.PasteboardType.rtf.rawValue: data]]), Clip(text: "Then plain")]
        let item = PasteComposer.item(for: clips, plainText: false)
        XCTAssertEqual(item.string(forType: .string), "Bold\nThen plain")
        let output = try XCTUnwrap(item.data(forType: .rtf))
        let restored = try XCTUnwrap(NSAttributedString(rtf: output, documentAttributes: nil))
        XCTAssertEqual(restored.string, "Bold\nThen plain")
        let font = try XCTUnwrap(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    @MainActor
    func testMixedImageAndTextProduceOneRichItem() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let clips = [Clip(text: "Caption"), Clip(kind: .image, representations: [[NSPasteboard.PasteboardType.png.rawValue: image]])]
        let item = PasteComposer.item(for: clips, plainText: false)
        let data = try XCTUnwrap(item.data(forType: .rtfd))
        let restored = try XCTUnwrap(NSAttributedString(rtfd: data, documentAttributes: nil))
        XCTAssertTrue(restored.string.hasPrefix("Caption\n"))
        XCTAssertNotNil(restored.attribute(.attachment, at: restored.length - 1, effectiveRange: nil))
        XCTAssertTrue(try XCTUnwrap(item.string(forType: .html)).contains("data:image/png;base64,"))
        let board = NSPasteboard(name: .init("openshelf-compose-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects([item]))
        XCTAssertEqual(board.pasteboardItems?.count, 1)
    }

    @MainActor
    func testPlainTextAndHTMLOnlyFormattingStayDistinct() async throws {
        let clip = Clip(kind: .richText, text: "Strong", representations: [[NSPasteboard.PasteboardType.html.rawValue: Data("<html><head><style>.strong{font-weight:bold}</style></head><body><span class='strong'>Strong</span></body></html>".utf8)]])
        let rich = PasteComposer.item(for: [clip, Clip(text: "& next")], plainText: false)
        let html = try XCTUnwrap(rich.string(forType: .html))
        XCTAssertTrue(html.contains("font-weight:bold"))
        XCTAssertTrue(html.contains("<span class='strong'>Strong</span>"))
        XCTAssertTrue(html.contains("&amp; next"))
        XCTAssertNil(rich.data(forType: .rtf))
        let plain = PasteComposer.item(for: [clip, Clip(text: "& next")], plainText: true)
        XCTAssertEqual(plain.string(forType: .string), "Strong\n& next")
        XCTAssertNil(plain.data(forType: .html))
        XCTAssertNil(plain.data(forType: .rtfd))
    }

    @MainActor
    func testFolderProjectionRetainsPinAndGroupMembership() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-projection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let folderURL = directory.appendingPathComponent("Fixture")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: folderURL.appendingPathComponent("one.txt"))
        let store = Store(directory: directory, monitor: false)
        store.addFolder(folderURL)
        let folder = try XCTUnwrap(store.folders.first)
        let clip = try XCTUnwrap(store.folderContents(folder: folder).first)
        store.addGroup(name: "Kept", color: "#112233")
        let group = try XCTUnwrap(store.groups.first)
        store.keep(clip, groupID: group.id)
        store.togglePin(clip.id)
        let projected = try XCTUnwrap(store.folderContents(folder: folder).first)
        XCTAssertTrue(projected.pinned)
        XCTAssertEqual(projected.groupIDs, [group.id])
    }
}
