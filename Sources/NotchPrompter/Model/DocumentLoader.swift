import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Turns supported files into plain text for the prompter.
enum DocumentLoader {
    static var supportedTypes: [UTType] {
        var types: [UTType] = [.plainText, .rtf, .rtfd, .pdf, .html]
        for ext in ["md", "markdown", "docx", "doc", "odt"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    enum LoadError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Couldn't read \(name)."
            }
        }
    }

    static func loadText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let text = PDFDocument(url: url)?.string, !text.isEmpty else {
                throw LoadError.unreadable(url.lastPathComponent)
            }
            return joinPDFLines(normalize(text))
        case "md", "markdown":
            return stripMarkdown(try readPlainText(url))
        case "txt", "text", "":
            return normalize(try readPlainText(url))
        default:
            // RTF, Word (.docx/.doc), OpenDocument, HTML — handled by AppKit.
            let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return normalize(attributed.string)
        }
    }

    private static func readPlainText(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }

    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    /// PDFs break every printed line; join lines that don't end a sentence.
    private static func joinPDFLines(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?<![.!?:;\n])\n(?!\n)"#, with: " ", options: .regularExpression)
    }

    private static func stripMarkdown(_ text: String) -> String {
        normalize(text).components(separatedBy: "\n").map { line in
            var line = line
            line = line.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s*"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "• ", options: .regularExpression)
            line = line.replacingOccurrences(of: #"(\*\*|__|`)"#, with: "", options: .regularExpression)
            return line
        }.joined(separator: "\n")
    }
}

/// Keeps the current document between launches.
enum Storage {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchPrompter", isDirectory: true)
    }
    private static var file: URL { folder.appendingPathComponent("document.txt") }

    static func save(text: String, name: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
        UserDefaults.standard.set(name, forKey: "documentName")
    }

    static func load() -> (text: String, name: String)? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return (text, UserDefaults.standard.string(forKey: "documentName") ?? "Script")
    }
}
