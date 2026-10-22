import Foundation

/// Article nodes retain complete source paragraphs. This does not use ⌘4 excerpts.
struct ArticlePracticeDocument: Codable, Identifiable {
    struct Paragraph: Codable, Identifiable, Equatable {
        let id: String
        let paragraph: Int
        let zh: String
        let en: String
        let role: String
    }
    struct Branch: Codable, Identifiable {
        let id: String
        let label: String
        let main: Paragraph
        let evidence: [Paragraph]
        let analysis: String
    }
    struct Coverage: Codable {
        let bodyParagraphs: Int
        let coveredParagraphs: Int
        let bodyWords: Int
        let scope: String
    }
    let title: String
    let author: String
    let publisher: String
    let source: String
    let readback: String
    let root: Paragraph
    let groups: [Branch]
    let paragraphs: [Paragraph]
    let coverage: Coverage
    var englishTitle: String? = nil
    var classification: Classification? = nil
    var importedAt: Date? = nil

    struct Classification: Codable, Equatable {
        let category: String
        let topics: [String]
    }
    var id: String { Self.identity(source) }
    static func identity(_ value: String) -> String {
        guard var parts = URLComponents(string: value) else { return value }
        parts.fragment = nil
        parts.host = parts.host?.lowercased()
        parts.queryItems = parts.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.string ?? value
    }

    var treeParagraphs: [Paragraph] { [root] + groups.flatMap { [$0.main] + $0.evidence } }

    func validate() throws {
        let all = treeParagraphs
        guard coverage.bodyParagraphs > 0,
              all.count == coverage.bodyParagraphs,
              coverage.coveredParagraphs == coverage.bodyParagraphs,
              paragraphs.count == all.count,
              Set(all.map(\.id)).count == all.count,
              Set(all.map(\.paragraph)) == Set(1...coverage.bodyParagraphs),
              Set(groups.map(\.id)).count == groups.count,
              !groups.isEmpty,
              all.allSatisfy({ !$0.zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              all.sorted(by: { $0.paragraph < $1.paragraph }) == paragraphs,
              paragraphs.reduce(0, { $0 + $1.en.split(whereSeparator: \.isWhitespace).count }) == coverage.bodyWords,
              Self.webURL(source) != nil, Self.webURL(readback) != nil else {
            throw ArticlePracticeError.invalidCoverage
        }
    }

    static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    static func load(from url: URL) throws -> Self {
        let document = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try document.validate()
        return document
    }

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "article-data", withExtension: "json", subdirectory: "ArticlePractice") else {
            throw ArticlePracticeError.missingResource
        }
        return try load(from: url)
    }
}

enum ArticlePracticeError: LocalizedError {
    case missingResource, invalidCoverage
    var errorDescription: String? {
        switch self {
        case .missingResource: return "应用内没有找到全文练习，请重新构建 Birdy。"
        case .invalidCoverage: return "文章段落不完整或原文索引不一致，未加载这份练习。"
        }
    }
}
