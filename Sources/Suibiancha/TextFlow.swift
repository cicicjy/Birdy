import Foundation

/// Reflow copied/OCR lines for display only. Never rewrite stored evidence or annotation offsets.
enum TextFlow {
    static func prose(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
        var paragraphs: [String] = []
        var lines: [String] = []
        func finish() {
            if !lines.isEmpty { paragraphs.append(lines.joined(separator: " ")); lines.removeAll() }
        }
        for line in normalized.components(separatedBy: "\n") {
            let cleaned = line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            if cleaned.isEmpty { finish() } else { lines.append(cleaned) }
        }
        finish()
        return paragraphs.joined(separator: "\n\n")
    }
}
