import AppKit

/// One compound item lets rich-text destinations paste a mixed selection as a whole.
@MainActor
enum PasteComposer {
    static func item(for clips: [Clip], plainText: Bool) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        let text = clips.map { clip in
            clip.text.isEmpty ? clip.filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n") : clip.text
        }.joined(separator: "\n")
        item.setString(text, forType: .string)
        guard !plainText else { return item }

        let compound = NSMutableAttributedString(string: "")
        var html: [String] = []
        var hasHTMLOnlyFormatting = false
        for (index, clip) in clips.enumerated() {
            if index > 0 { compound.append(NSAttributedString(string: "\n")) }
            if let image = clip.imageData, let decoded = NSImage(data: image), let tiff = decoded.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                let wrapper = FileWrapper(regularFileWithContents: png)
                wrapper.preferredFilename = "Image.png"
                compound.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
                html.append("<div><img src=\"data:image/png;base64,\(png.base64EncodedString())\"></div>")
                continue
            }
            let rich = attributedString(for: clip)
            compound.append(rich ?? NSAttributedString(string: clip.text.isEmpty ? clip.title : clip.text))
            if let source = clip.representations.compactMap({ $0[NSPasteboard.PasteboardType.html.rawValue] }).first,
               let markup = String(data: source, encoding: .utf8) {
                // Keep markup as clipboard data; importing HTML through WebKit could fetch remote resources.
                html.append("<div>\(bodyFragment(markup))</div>")
                if rich == nil { hasHTMLOnlyFormatting = true }
            } else if let rich, let data = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]), let markup = String(data: data, encoding: .utf8) {
                html.append("<div>\(bodyFragment(markup))</div>")
            } else if !clip.filePaths.isEmpty {
                html.append("<div>" + clip.filePaths.map { path in
                    "<a href=\"\(escape(URL(fileURLWithPath: path).absoluteString))\">\(escape(URL(fileURLWithPath: path).lastPathComponent))</a>"
                }.joined(separator: "<br>") + "</div>")
            } else {
                html.append("<div>\(escape(clip.text).replacingOccurrences(of: "\n", with: "<br>"))</div>")
            }
        }
        item.setString("<html><body>\(html.joined())</body></html>", forType: .html)
        // Avoid advertising a plain RTF alternative ahead of a richer HTML-only source.
        if !hasHTMLOnlyFormatting {
            let range = NSRange(location: 0, length: compound.length)
            if let data = compound.rtfd(from: range, documentAttributes: [:]) { item.setData(data, forType: .rtfd) }
            if let data = compound.rtf(from: range, documentAttributes: [:]) { item.setData(data, forType: .rtf) }
        }
        return item
    }

    static func attributedString(for clip: Clip) -> NSAttributedString? {
        for representation in clip.representations {
            if let data = representation[NSPasteboard.PasteboardType.rtfd.rawValue], let value = NSAttributedString(rtfd: data, documentAttributes: nil) { return value }
            if let data = representation[NSPasteboard.PasteboardType.rtf.rawValue], let value = NSAttributedString(rtf: data, documentAttributes: nil) { return value }
        }
        return nil
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func bodyFragment(_ markup: String) -> String {
        guard let opening = markup.range(of: "<body\\b[^>]*>", options: [.regularExpression, .caseInsensitive]),
              let closing = markup.range(of: "</body\\s*>", options: [.regularExpression, .caseInsensitive, .backwards]), opening.upperBound <= closing.lowerBound else { return markup }
        // Preserve head styles when the producer uses CSS classes in its body.
        let expression = try? NSRegularExpression(pattern: "(?is)<style\\b[^>]*>.*?</style\\s*>")
        let styles = expression?.matches(in: markup, range: NSRange(markup.startIndex..., in: markup)).compactMap { Range($0.range, in: markup).map { String(markup[$0]) } }.joined() ?? ""
        return styles + String(markup[opening.upperBound..<closing.lowerBound])
    }
}
