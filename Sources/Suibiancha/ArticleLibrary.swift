import Foundation
import Combine

@MainActor
final class ArticlePracticeLibrary: ObservableObject {
    @Published private(set) var documents: [ArticlePracticeDocument] = []
    @Published var error = ""
    private let url: URL
    private var canSave = true

    init(folder: URL? = nil, seed: ArticlePracticeDocument? = nil) {
        let directory = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Suibiancha", isDirectory: true)
        url = directory.appendingPathComponent("article-practice.json")
        var items: [ArticlePracticeDocument] = []
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                items = try JSONDecoder().decode([ArticlePracticeDocument].self, from: Data(contentsOf: url))
                try items.forEach { try $0.validate() }
                guard Set(items.map(\.id)).count == items.count else { throw ArticlePracticeError.invalidCoverage }
            } catch {
                self.error = "文章库读取失败，原文件已保留：\(error.localizedDescription)"
                canSave = false
            }
        }
        if let seed = seed ?? (try? ArticlePracticeDocument.bundled()), !items.contains(where: { $0.id == seed.id }) {
            items.insert(seed, at: 0)
        }
        documents = items
    }

    func existing(_ source: String) -> ArticlePracticeDocument? {
        documents.first { $0.id == ArticlePracticeDocument.identity(source) }
    }

    func add(_ document: ArticlePracticeDocument) throws {
        guard canSave else { throw ArticleImportError.message("文章库文件异常，暂未写入。原文件已保留，请先检查文章库。") }
        try document.validate()
        guard existing(document.source) == nil else { return }
        let updated = [document] + documents
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: url, options: .atomic)
        documents = updated
    }
}
